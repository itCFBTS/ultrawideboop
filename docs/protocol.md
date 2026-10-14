# SteelSeries Sensei Pro (1038:1880) — read protocol notes

Reverse-engineered 2026-10-12 from a 30 s usbmon capture of SteelSeries GG Web's connect
handshake (WebHID, Chrome on CachyOS). Receiver/base station = USB `1038:1880`, mouse FW
2.14.1 at time of capture. Read-only opcodes observed; no write commands captured (no
settings were changed during the sniff).

## Transport

- **Command**: HID SET_REPORT control transfer to **interface 2** (`bmRequestType 0x21,
  bRequest 0x09, wValue 0x0200, wIndex 0x0002`), 64-byte payload, first byte = opcode,
  rest zero (for reads).
- **Response**: 64-byte interrupt IN on **endpoint 3**; first byte echoes the opcode.
- Motion reports ride endpoint 1 (8 kHz-capable, 125 µs interval) and are unrelated.
- hidraw access for userspace: `udev/71-sensei-pro.rules` (uaccess on the receiver's hidraw nodes).

## Decoded opcodes

| Opcode | Meaning | Response layout (after `op 00`) |
|---|---|---|
| `0x92` | **Batteries** | byte2 = mouse battery % (0x54=84; **0xFF = no reading**, seen mid-swap with no battery in the mouse), byte3 = status (01 normal, 00 while the mouse had no battery — likely "mouse connected"), byte4 = base-station battery % (the swappable battery docked in the base; 0x64=100; 0 while the slot was empty). Confirmed 2026-10-13 by a battery swap: mouse 42 / base 100 → (FF, 0) during the swap → mouse 100 / base 39 |
| `0x90` | **Firmware version** | ASCII string ("2.14.1") |
| `0xb0` | **Serial number** | ASCII string (arg byte 0/1 seen; both returned same serial) |
| `0xb4` | **DPI table** | `count, active_idx` then count × 6-byte stages: X u16-LE, Y u16-LE, 2 unknown bytes (`03 03` observed; flags/color?). 0190=400, 0320=800, 0640=1600, 0960=2400, 0C80=3200. Active idx 0-based (04 = 3200 = red LED). Stride verified live 2026-10-12 |
| `0xad` | **Polling profile table** | `count, active_idx` then count × (sensor, uwb) byte pairs; rate = 8000 Hz >> n (0=8000, 1=4000, 2=2000, 3=1000). Stock levels: (3,3) (3,0) (2,0) (1,0) (0,0); active 04 = Level 5 = 8k/8k |
| `0xa9` | **Sleep timer** | u32-LE ms (0x0493E0 = 300 000 = 5 min) |
| `0x96` | unknown (returned u16-LE 500) | lift-off / threshold? unconfirmed |
| `0x9b` | **Max Performance state** | byte2 = 01 on / 00 off (confirmed 2026-10-13 by differential handshake sniff) |
| `0x99` | unknown (`00 05 03`) | unconfirmed |
| `0xaa` | unknown (5-entry table ending 0x30) | keybinds/LED? unconfirmed |
| `0xbc`, `0xc3`, `0xc4`, `0xa5`, `0x98`, `0x9a` | queried by GG, empty/ack responses | — |

## Write opcodes (observed 2026-10-13; documented only — ultrawideboop never sends writes)

| Opcode | Meaning |
|---|---|
| `0x1b <01/00>` | Max Performance on/off (sniffed while toggling in GG Web) |
| `0x09` | sent after a settings change; likely "commit to onboard memory" |

Max Performance does not touch the profile table (no `0xad` write seen). Read-back = `0x9b` (confirmed).

## Notes

- Onboard DPI presets are color-coded on the mouse (bottom combined power/DPI button,
  short-press cycles): 400 magenta, 800 cyan, 1600 green, 2400 yellow, **3200 red**.
- Polling profiles are switchable from a button on the base station; configured in GG Web
  (works on Linux via WebHID once hidraw uaccess is granted).
- "9k overpolling" (GG's Level-5 label) is radio-hop oversampling; it is not a host-visible
  rate or a readable field. USB delivers at most 8000 Hz (125 µs interval). Its measurable
  signature would be unusually uniform inter-report intervals (few/no 250 µs doubled gaps).
- **Validated live 2026-10-12** with `ultrawideboop`: all decoded fields match GG Web's display. Command channel = the hidraw node of USB interface 02 (probe-verified).
- Capture hygiene: capture file deleted after analysis; `usbmon` module unloaded.

## Wheel characteristics (measured 2026-10-12/13, evdev, FW 2.14.1)

- Reports whole detents only (hi-res events always ±120); same as the G Pro X Superlight — no
  fractional scrolling on either.
- **UPDATE 2026-10-13 — it's a latched state, not the 8K profile itself.** After a fresh
  receiver plug-in (base station boots straight into L5), the wheel at L5 is normal. Stepping
  from L1 (1000/1000) to L2 (1000/8000) — i.e. switching the UWB link 1000→8000 Hz at runtime —
  breaks it, and it stays broken in every 8K-UWB profile (L2–L5) until the receiver is
  unplugged/replugged. L1 is fine even while latched. Reproduced repeatedly (~20 min on
  scrolltest.net); not port- or OS-related (reboot/port change only "fixed" it via the replug).
  Also reproduced 2026-10-13 with NO host software talking to the mouse (ultrawideboop disabled,
  GG Web closed) — the trigger is purely the base-station button.
- Earlier observation (before the latch was understood): **The wheel's throughput is profile-dependent — the 8K profile strangles it (likely a firmware
  bug; reported to SteelSeries 2026-10-13):** peak flick rate at L5 (8000/8000) = 3–4 detents/0.5 s; at
  **L1 (1000/1000) = 10 detents/0.5 s, identical to the Superlight (11)**. Reproduced in both
  directions (L5→L1→L5). Earlier conclusion that the cap was inherent to the encoder was wrong.
- Not caused by: Max Performance (ON vs OFF: no change), Scroll Jump Protection (ON@100ms vs
  OFF: no change; "off" is genuinely off).
- Open: does the wheel follow the sensor rate or the UWB rate? Test L2 (1000/8000) / L4
  (4000/8000) to map it.
- Workaround: don't cycle up through L2 while running; if the wheel goes sluggish at 8K,
  unplug/replug the receiver. (Open: does a mouse-only power cycle also clear it?)

## GG Web vs desktop (observed in GG Web, 2026-10-12)

- Desktop-only, badged "GG REQUIRED" (host-side processing; N/A on Linux at all):
  Acceleration/Deceleration sensitivity curves ("dynamic sensitivity"), Sensitivity Matcher,
  Rotation (grip-angle), Angle Snapping.
- In Web: button remaps + Macro Editor, Scroll Jump Protection, 5 DPI slots (to 65k, indep. X-Y),
  lift-off/landing 0.7–1.7 (splittable), performance profiles (UWB "8000 Hz with 9k Hz
  overpolling" + sensor rate), LAN Mode, Max Performance, Motion Sync (currently OFF),
  Low Power Mode (auto at chosen battery %, set 20%, polling drops to 1000 Hz!), sleep timer,
  base-station LED display mode, firmware update, factory reset.
- **Test-day trap: below the Low Power threshold (20%) polling silently drops to 1000 Hz.**
  Keep battery above it for any latency testing.
