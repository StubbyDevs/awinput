# awinput

Switch **Dell and Alienware monitor inputs** from the command line, a hotkey or an
**Elgato Stream Deck** button. No more reaching for the joystick and digging through the OSD.

```
awinput hdmi1        # switch to HDMI 1
awinput dp           # back to DisplayPort
awinput toggle       # DP <-> HDMI 1
awinput cycle        # step through every input the monitor reports
awinput list         # show monitors, current input, supported inputs
```

* **One small exe, nothing to install.** It builds with the C# compiler that's already in Windows.
* **Windowless**, so Stream Deck buttons don't flash a console. Run from a terminal, it prints normally.
* **Dell-style commands.** It sends input changes the way Dell's own firmware tool does (see [docs/PROTOCOL.md](docs/PROTOCOL.md)).
* **Toggle and cycle** read the monitor's current input first, so a single button works.

## Install

**Download:** grab `awinput-win.zip` from [Releases](../../releases), unzip it anywhere, and run
`make-shortcuts.bat` if you want Stream Deck shortcuts.

**Or build it yourself** (Windows 10/11, no SDK needed):

```
git clone https://github.com/StubbyDevs/awinput
cd awinput
build.bat
```

This produces `bin\awinput.exe` plus one shortcut per action (`awinput hdmi1.lnk`, …).

## Stream Deck

1. Drag **System → Open** onto a key.
2. Under **App / File**, pick one of the shortcuts in `bin\` (for example `awinput toggle.lnk`).
3. Press it.

Want a different combination? Duplicate a shortcut and edit its target, e.g.
`awinput.exe toggle dp hdmi2` or `awinput.exe hdmi1 --monitor U2421E`.

## Usage

```
awinput <command> [options]

commands:
  dp | dp2 | hdmi1 | hdmi2 | usbc     switch to that input
  0xNN                                raw VCP 0x60 input code
  toggle [A] [B]                      flip between two inputs (default: dp hdmi1)
  cycle  [A B C ...]                  step through inputs (default: what the monitor reports)
  get                                 print the active input
  list                                monitors, current input, supported inputs
  caps                                raw MCCS capability strings

options:
  -m, --monitor NAME   monitor whose name contains NAME (default: first Alienware/Dell)
  --plain              send 0x00NN instead of Dell's 0xNNNN
```

Exit code is `0` on success. Errors also go to `awinput.log` next to the exe, which helps
when a Stream Deck button seems to do nothing.

## Compatibility

| Monitor | Connection | Status |
|---------|-----------|--------|
| Alienware AW3225QF | DisplayPort | ✅ works: DP ↔ HDMI 1 / HDMI 2 |
| Dell U2421E | DisplayPort | reports inputs `1B 0F 11` (USB-C, DP, HDMI), not yet tested |

Most Dell and Alienware monitors with **DDC/CI enabled in the OSD** should work. Tested
yours? Run `powershell -ExecutionPolicy Bypass -File tools\probe.ps1` and open an issue
or PR with the output.

## Limits and troubleshooting

* **This uses the video cable.** Once the monitor is showing another input, the PC you switched
  away from may not be able to switch it back. Put an `awinput dp` button on the other machine
  too (or a second Stream Deck profile). [USB-based switching](docs/PROTOCOL.md#2-ddcci-over-usb-experimental-not-working-yet),
  which would remove this limit, is under investigation.
* **Nothing happens?** Check that *DDC/CI* is enabled in the monitor OSD (usually under Others). Then run
  `awinput list` from a terminal, try `--plain`, and look at `awinput.log`.
* **Wrong monitor?** Use `--monitor` with part of the name `awinput list` shows. Generic
  "PnP Monitor" names are matched against the model in the capability string.
* Some GPUs, docks and DP MST hubs don't pass DDC/CI through.

## Alternatives

If you need a GUI, brightness control or other platforms, these are great general-purpose tools:
[ControlMyMonitor](https://www.nirsoft.net/utils/control_my_monitor.html) (Windows),
[monitor-input-rs](https://github.com/kojiishi/monitor-input-rs) (cross-platform),
[ddcutil](https://www.ddcutil.com/) (Linux),
[MonitorInputWizzard](https://github.com/lunat1q/monitorinputwizzard) (Windows, hotkeys), and
Dell Display and Peripheral Manager (input hotkeys). `awinput` aims to be the smallest
thing that gets a Dell/Alienware input onto a Stream Deck button, and to document Dell's protocol.

## Repository layout

```
src/awinput.cs                 the whole tool (single file, C# 5 / .NET Framework 4)
build.bat                      build with the in-box compiler + make shortcuts
streamdeck/make-shortcuts.bat  one .lnk per action for Stream Deck "Open"
tools/probe.ps1                dump monitor capabilities for bug reports
docs/PROTOCOL.md               how Dell's tools switch inputs (DDC/CI + USB HID notes)
experimental/usb-hid/          work-in-progress USB HID-to-I²C route
```

## License

[MIT](LICENSE). Not affiliated with or endorsed by Dell Technologies. Dell and Alienware are
trademarks of Dell Inc.
