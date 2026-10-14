# ultrawideboop

A gentle, read-only boop for your **SteelSeries Ultra-Wideband (UWB)** mouse on Linux:
battery and settings readout for the Sensei Pro (and, likely, the Rival Pro and the Minis).

- **`sensei-info`** — a small CLI that reads the mouse and base station over hidraw:
  battery levels, firmware, DPI stages, polling profiles, Max Performance, sleep timer.
- **Sensei Battery** — a KDE Plasma 6 widget (system tray or panel) built on top of it.

SteelSeries GG's desktop app doesn't run on Linux. GG Web works in Chrome for changing
settings, but nothing shows the battery at a glance. This fills that gap.

> Not affiliated with or endorsed by SteelSeries. Protocol reverse-engineered from USB
> captures of GG Web; tested on a Sensei Pro, firmware 2.14.1. The Rival Pro and the Mini
> models share the same UWB platform but are untested and likely use different USB IDs;
> reports welcome. For older (non-UWB) SteelSeries mice, see
> [rivalcfg](https://github.com/flozz/rivalcfg).

## Read-only by design

`sensei-info` only sends the read queries GG Web itself sends when it connects
(`0x90 0x92 0xb4 0xad 0x9b 0xa9`, plus `0xb0` with `--serial`). It never writes settings,
never touches firmware, and has no code path that could. The full decoded protocol is in
[docs/protocol.md](docs/protocol.md).

## Install

### 1. udev rule (lets your user talk to the receiver without sudo)

```bash
sudo cp udev/71-sensei-pro.rules /etc/udev/rules.d/
sudo udevadm control --reload
sudo udevadm trigger
```

This also makes GG Web in Chrome able to see the mouse.

### 2. `sensei-info`

Needs Rust 1.85+ ([rustup](https://rustup.rs)).

```bash
cargo install --path .
```

```console
$ sensei-info
mouse battery : 67%
base battery  : 100%
dpi           : 3200
poll profile  : L5 — 8000 Hz sensor / 8000 Hz UWB

$ sensei-info -v
[/dev/hidraw11]
firmware      : 2.14.1
mouse battery : 67%   (status byte 0x01)
base battery  : 100%
dpi stages    : 400 800 1600 2400 [3200]  (active bracketed)
poll profiles : L1:1000/1000  L2:1000/8000  L3:2000/8000  L4:4000/8000  [L5:8000/8000]  (sensor/UWB Hz, active bracketed)
max performance: off
sleep timer   : 300 s

$ sensei-info --battery      # single query, for scripts
67 100
```

`--serial` / `-s` also prints the serial number (hidden by default so output is safe to share).

If it reports *no response*, close any GG Web tab — only one program can hold the
command channel at a time.

### 3. Plasma widget (KDE Plasma 6 only)

```bash
kpackagetool6 -t Plasma/Applet -i plasmoid
```

Then add **Sensei Battery** from *Add Widgets* (or enable it under the system tray's
*Configure System Tray → Entries*). To update after pulling changes, use `-u` instead of
`-i` and restart Plasma: `systemctl --user restart plasma-plasmashell`.

- **Tray / panel:** mouse battery %, turns red at 15% or below. Polls every 5 minutes
  (one query).
- **Popup:** mouse and base-station battery bars, DPI stages, polling profiles and Max
  Performance, with the active ones highlighted. Refreshes on open.

The widget looks for `sensei-info` in `~/.local/bin`, `~/.cargo/bin` and your `PATH`.

## Other desktops

`sensei-info` works on any distro and desktop. The widget is Plasma 6 only — it won't load
on GNOME, Cinnamon (Linux Mint's default), Xfce, or Plasma 5.

## Known quirks (firmware 2.14.1)

- **Scroll wheel gets stuck slow at 8K:** switching the wireless rate from 1000 to 8000 Hz
  while running (base-station button L1 → L2) cuts the wheel to roughly a third of its normal
  scroll throughput in every 8K profile, until the receiver is unplugged and replugged.
  Reported to SteelSeries. Workaround: avoid cycling up through L2; replug if it happens. Details in
  [docs/protocol.md](docs/protocol.md#wheel-characteristics-measured-2026-10-1213-evdev-fw-2141).
- **Low Power Mode** (set in GG Web) silently drops polling to 1000 Hz once the battery falls
  below its threshold.

## License

[MIT](LICENSE)
