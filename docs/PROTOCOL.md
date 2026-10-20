# How Dell / Alienware monitors switch inputs

These notes come from studying how Dell's own **AW3225QF firmware update utility**
(package `M2B110`, `Setup.dll` 2.0.0.148) talks to the monitor, for the purpose of
interoperability. This repository contains none of Dell's code or binaries.

## 1. DDC/CI over the video cable (what `awinput` uses)

Dell's updater calls the standard Windows monitor-configuration API (`dxva2.dll`:
`GetPhysicalMonitorsFromHMONITOR`, `GetVCPFeatureAndVCPFeatureReply`, `SetVCPFeature`),
which sends DDC/CI over the DisplayPort/HDMI cable to I²C address `0x37` (`0x6E`/`0x6F`).

### Input select: VCP `0x60`

Dell's routine that brings a monitor back to its main input does this:

1. `GetVCPFeature(0x60)` → 16-bit value `cur`.
2. `hi = (cur >> 8) & 0xFF`, `lo = cur & 0xFF`. If `hi & 0x80` is set the input is unknown.
3. If `lo != hi`: `SetVCPFeature(0x60, (hi << 8) | hi)`.

So Dell writes the input code **into both bytes** (for example `0x1111` for HDMI 1), and the
read-back packs two things:

| byte | meaning (observed) |
|------|--------------------|
| high | the input that was requested / "main" input |
| low  | the input that is actually active |

On an AW3225QF over DisplayPort: before switching, VCP 60 read back as `0x0F0F`. After
`SetVCPFeature(0x60, 0x1111)` it read back as `0x0F11`, and the panel was showing HDMI 1.

Plain MCCS tools send `0x00NN`. `awinput` sends Dell's form by default, falls back to
`0x00NN` if the call fails, and has a `--plain` switch.

### Input codes (MCCS 2.2)

| code | input | AW3225QF |
|------|-------|----------|
| `0x0F` | DisplayPort 1 | ✔ |
| `0x10` | DisplayPort 2 | |
| `0x11` | HDMI 1 | ✔ |
| `0x12` | HDMI 2 | ✔ |
| `0x1B` | USB-C (Dell) | |

The AW3225QF's capability string reports `60( 0F 11 12)`. Run `awinput list` or
`tools/probe.ps1` to see what your monitor reports.

### Other Dell VCP codes the updater uses

| VCP | value | use in the updater |
|-----|-------|--------------------|
| `0xD6` | `1` on, `4` off | power mode (standard MCCS), used to power-cycle the monitor |
| `0xE1` | `0` | written right after power-on ("wake"), vendor-specific |
| `0xE9` | `0` | if non-zero (PIP/PBP active), set to `0` to return to full screen, vendor-specific |
| `0xF6` | `0xFB80` / `0xFB81` | enter / leave firmware-update (ISP) mode. **Don't send this.** |

## 2. DDC/CI over USB (experimental, not working yet)

The updater can also reach the scaler **through the monitor's built-in USB hub**, so it
works even when the PC isn't driving the active video input. That's the attractive part:
switching would work from any input.

* AW3225QF scaler: **MediaTek MT9810** (from the firmware image header).
* Hub: **Microchip USB5734T**. Its HID-to-I²C bridge enumerates as **VID `0x187C` / PID `0x1013`**,
  vendor usage page `0xFF00`, 64-byte reports plus a report-ID byte (65 total).
* The hub's I²C master is wired to the scaler's DDC port. The updater sends ordinary DDC/CI
  frames to address `0x37` with sub-address `0x51`. For example, its "enter ISP" command is the
  DDC/CI *Set VCP* frame `84 03 F6 FB 80 <xor>`, with the checksum seeded at `0x6E ^ 0x51 = 0x3F`.

### HID report framing (Microchip `hidtoi2c` bridge)

All reports are 65 bytes, report ID `0x00`, padded with `0xFF`.

| purpose | bytes |
|---------|-------|
| configure (sent on open; speed `0` in normal use) | `00 95 00 <speed> 00 00 00 00 00` |
| I²C write (≤60 data bytes per report) | `00 92 <addr7> <len> <00 = last, FF = more follows> <data…>` |
| I²C read request | `00 93 <addr7> <len, 32-bit little-endian>` |
| read reply (input report, after the report ID) | `94 ?? <count> ?? <data…>` |

Switching to HDMI 1 would be the write report
`00 92 37 07 00 51 84 03 60 11 11 D8`.

### Status

On an AW3225QF the bridge opens and accepts the configure report, but the next output report
(the I²C write) never completes. `HidD_SetOutputReport` returns success, yet the input doesn't
change. The current guess is that the bridge queues a status input report after each command,
and that report has to be read before it accepts another one.
[`experimental/usb-hid/usb_switch.ps1`](../experimental/usb-hid/usb_switch.ps1) logs every
transfer. Pull requests welcome.

The updater ships equivalent paths for other hubs used in Dell monitors: Realtek (`RtHIDlib`,
VID `0x0BDA`), TI TUSB8044, and other Microchip parts. The same approach may apply to many models.
