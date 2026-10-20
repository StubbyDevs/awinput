# USB HID-to-I²C route (experimental)

`usb_switch.ps1` tries to send the DDC/CI input-select command through the monitor's built-in
USB hub instead of the video cable, so switching would work from any input. See
[docs/PROTOCOL.md §2](../../docs/PROTOCOL.md#2-ddcci-over-usb-experimental-not-working-yet)
for the framing.

**Status: not working yet.** On an AW3225QF (bridge `187C:1013`) the configure report is
accepted, then the first I²C write report never completes.

```
powershell -ExecutionPolicy Bypass -File usb_switch.ps1 -Target hdmi1 -RevertAfter 10
```

Every transfer goes to `aw_switch_log.txt`. Ideas to try:

* Read the input report after each command (status/ack) before sending the next one.
* Capture what Dell's updater actually puts on the wire (USBPcap + Wireshark) during its
  monitor-detection phase, which talks to the scaler before flashing anything.
* Check whether the bridge needs `OpenDeviceWithID`-style opening (no configure report).

**Never send VCP `0xF6`.** It puts the scaler into firmware-update mode.
