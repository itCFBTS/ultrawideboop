//! sensei-info — print everything we understand about the SteelSeries Sensei Pro (1038:1880).
//!
//! Sends the six READ opcodes SteelSeries GG Web issues on connect (fw, serial, batteries,
//! DPI table, polling profiles, sleep timer) over hidraw and decodes the responses.
//! Nothing is written to the mouse's settings. Protocol: docs/protocol.md.
//! Needs the hidraw uaccess udev rule from udev/71-sensei-pro.rules (no sudo).

use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::fd::AsRawFd;
use std::path::PathBuf;
use std::process::exit;

const HID_ID: &str = "00001038:00001880";

/// All hidraw nodes belonging to the receiver, command interface (bInterfaceNumber 02) first.
fn find_candidates() -> Vec<PathBuf> {
    let mut with_iface: Vec<(u8, PathBuf)> = Vec::new();
    let Ok(rd) = fs::read_dir("/sys/class/hidraw") else { return Vec::new() };
    for entry in rd.flatten() {
        let sys = entry.path();
        let Ok(uevent) = fs::read_to_string(sys.join("device/uevent")) else { continue };
        if !uevent.contains(HID_ID) {
            continue;
        }
        // hidrawN/device -> HID device dir; its parent is the USB interface.
        let iface_num = fs::canonicalize(sys.join("device"))
            .ok()
            .and_then(|hid| fs::read_to_string(hid.parent()?.join("bInterfaceNumber")).ok())
            .and_then(|s| u8::from_str_radix(s.trim(), 16).ok())
            .unwrap_or(0xFF);
        with_iface.push((iface_num, PathBuf::from("/dev").join(entry.file_name())));
    }
    // interface 02 (the command channel) first, then the rest as probe fallbacks
    with_iface.sort_by_key(|(n, _)| if *n == 2 { 0 } else { 1 + *n as u16 });
    with_iface.into_iter().map(|(_, p)| p).collect()
}

/// Send one read opcode; return the 64-byte response that echoes it.
fn query(f: &mut File, opcode: u8) -> Option<[u8; 64]> {
    // hidraw write: byte 0 = report id (0 = unnumbered, stripped by the kernel).
    let mut cmd = [0u8; 65];
    cmd[1] = opcode;
    for _ in 0..3 {
        f.write_all(&cmd).ok()?;
        loop {
            let mut pfd = libc::pollfd { fd: f.as_raw_fd(), events: libc::POLLIN, revents: 0 };
            // SAFETY: valid pollfd pointer, count 1.
            let n = unsafe { libc::poll(&mut pfd, 1, 400) };
            if n <= 0 {
                break; // timed out; retry the command
            }
            let mut buf = [0u8; 64];
            let got = f.read(&mut buf).ok()?;
            if got > 0 && buf[0] == opcode {
                return Some(buf);
            }
        }
    }
    None
}

fn cstr(b: &[u8]) -> String {
    let end = b.iter().position(|&c| c == 0).unwrap_or(b.len());
    String::from_utf8_lossy(&b[..end]).into_owned()
}

fn main() {
    let mut show_serial = false;
    let mut verbose = false;
    let mut battery_only = false;
    for a in std::env::args().skip(1) {
        match a.as_str() {
            "--serial" | "-s" => show_serial = true,
            "--verbose" | "-v" => verbose = true,
            "--battery" | "-b" => battery_only = true,
            "-h" | "--help" => {
                println!("sensei-info — read-only status of the SteelSeries Sensei Pro\n");
                println!("  --battery, -b   print only \"<mouse%> <base%>\" (single query; for scripts/widgets)");
                println!("  --serial, -s    also print the device serial number (never shown otherwise)");
                println!("  --verbose, -v   also show firmware, all DPI stages, all poll profiles,");
                println!("                  sleep timer, battery status byte and the hidraw node");
                return;
            }
            other => {
                eprintln!("unknown option: {other} (try --help)");
                exit(2);
            }
        }
    }
    let candidates = find_candidates();
    if candidates.is_empty() {
        eprintln!("Sensei Pro not found. Receiver plugged in? Mouse on?");
        exit(1);
    }
    // Probe each candidate; use the node that actually answers. In battery mode the probe
    // IS the battery query, so the whole run is a single command.
    let probe_op: u8 = if battery_only { 0x92 } else { 0x90 };
    let mut found = None;
    for node in &candidates {
        match OpenOptions::new().read(true).write(true).open(node) {
            Ok(mut f) => {
                if let Some(r) = query(&mut f, probe_op) {
                    found = Some((node.clone(), f, r));
                    break;
                }
            }
            Err(e) => eprintln!("note: cannot open {} ({e})", node.display()),
        }
    }
    let Some((node, mut f, first)) = found else {
        eprintln!(
            "No response on any hidraw node of the receiver ({}). Is the GG Web tab holding it? Try after closing it.",
            candidates.iter().map(|p| p.display().to_string()).collect::<Vec<_>>().join(", ")
        );
        exit(1);
    };
    if battery_only {
        println!("{} {}", first[2], first[4]);
        return;
    }
    if verbose {
        println!("[{}]", node.display());
        println!("firmware      : {}", cstr(&first[2..]));
    }
    if show_serial {
        match query(&mut f, 0xB0) {
            Some(r) => println!("serial        : {}", cstr(&r[2..])),
            None => println!("serial        : no reply"),
        }
    }
    match query(&mut f, 0x92) {
        Some(r) => {
            if verbose {
                println!("mouse battery : {}%   (status byte {:#04x})", r[2], r[3]);
            } else {
                println!("mouse battery : {}%", r[2]);
            }
            println!("base battery  : {}%", r[4]);
        }
        None => println!("batteries     : no reply"),
    }
    match query(&mut f, 0xB4) {
        Some(r) => {
            let (n, active) = (r[2] as usize, r[3] as usize);
            // 6 bytes per stage: X u16, Y u16, then 2 unknown bytes (0x0303 observed).
            let dpi_at = |i: usize| u16::from_le_bytes([r[4 + 6 * i], r[5 + 6 * i]]);
            if verbose {
                let stages: Vec<String> = (0..n.min(10))
                    .map(|i| if i == active { format!("[{}]", dpi_at(i)) } else { dpi_at(i).to_string() })
                    .collect();
                println!("dpi stages    : {}  (active bracketed)", stages.join(" "));
            } else if active < n.min(10) {
                println!("dpi           : {}", dpi_at(active));
            }
        }
        None => println!("dpi           : no reply"),
    }
    match query(&mut f, 0xAD) {
        Some(r) => {
            let (n, active) = (r[2] as usize, r[3] as usize);
            let level = |i: usize| {
                let sensor = 8000u32 >> r[4 + 2 * i].min(6);
                let uwb = 8000u32 >> r[5 + 2 * i].min(6);
                (sensor, uwb)
            };
            if verbose {
                let levels: Vec<String> = (0..n.min(10))
                    .map(|i| {
                        let (sensor, uwb) = level(i);
                        let t = format!("L{}:{sensor}/{uwb}", i + 1);
                        if i == active { format!("[{t}]") } else { t }
                    })
                    .collect();
                println!("poll profiles : {}  (sensor/UWB Hz, active bracketed)", levels.join("  "));
            } else if active < n.min(10) {
                let (sensor, uwb) = level(active);
                println!("poll profile  : L{} — {sensor} Hz sensor / {uwb} Hz UWB", active + 1);
            }
        }
        None => println!("poll profile  : no reply"),
    }
    if verbose {
        match query(&mut f, 0x9B) {
            Some(r) => println!("max performance: {}", if r[2] == 1 { "on" } else { "off" }),
            None => println!("max performance: no reply"),
        }
        match query(&mut f, 0xA9) {
            Some(r) => {
                let ms = u32::from_le_bytes([r[2], r[3], r[4], r[5]]);
                println!("sleep timer   : {} s", ms / 1000);
            }
            None => println!("sleep timer   : no reply"),
        }
    }
}
