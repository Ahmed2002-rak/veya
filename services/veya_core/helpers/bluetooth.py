#!/usr/bin/env python3
"""Bluetooth management via bluetoothctl.

Usage:
  bluetooth.py scan                       # returns JSON list of nearby BT-Classic devices
  bluetooth.py status                     # returns JSON paired/connected state + adapter info
  bluetooth.py pair   <MAC>               # pair, trust, and connect a device
  bluetooth.py unpair <MAC>               # remove a device (unpair)
  bluetooth.py connect    <MAC>           # connect to an already-paired device
  bluetooth.py disconnect <MAC>           # disconnect but keep pairing
"""
from __future__ import annotations

import json
import subprocess
import sys
import time


def _run(args: list[str], timeout: int = 10) -> tuple[int, str, str]:
    """Run a command, return (returncode, stdout, stderr)."""
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return 1, "", "command timed out"
    except FileNotFoundError:
        return 1, "", f"{args[0]}: command not found"


def _btctl(*cmds: str, timeout: int = 10) -> tuple[int, str, str]:
    """Run one or more bluetoothctl commands non-interactively via stdin pipe."""
    script = "\n".join(cmds) + "\n"
    try:
        r = subprocess.run(
            ["bluetoothctl"],
            input=script,
            capture_output=True, text=True,
            timeout=timeout,
        )
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return 1, "", "bluetoothctl timed out"
    except FileNotFoundError:
        return 1, "", "bluetoothctl not found"


def is_device_in_range(mac: str) -> bool:
    """Check if a bonded device is currently reachable.
    Uses bluetoothctl info <MAC>, parsing 'Connected: yes'.
    Falls back to l2ping -c 1 -t 2 <MAC> (returns 0 if reachable)."""
    mac = mac.upper()
    _, info_out, _ = _btctl(f"info {mac}", "quit", timeout=5)
    if "Connected: yes" in info_out:
        return True
    rc, _, _ = _run(["l2ping", "-c", "1", "-t", "2", mac], timeout=6)
    return rc == 0


def scan(duration: int = 8) -> dict:
    """Scan for nearby BT-Classic devices.

    Returns {"devices": [...], "error": ""}
    Each device: {"mac": "AA:BB:...", "name": "...", "paired": bool, "connected": bool}
    """
    # Use hcitool scan for raw BR/EDR inquiry. bluetoothctl filters scan output by
    # perceived device type / service profile, silently dropping BT-Classic SPP devices
    # (e.g. ESP32 BluetoothSerial) that don't advertise bluez-recognized service UUIDs.
    # hcitool bypasses that filtering and finds all responding devices.
    # NOTE: hcitool is deprecated in newer BlueZ but is the only practical BR/EDR
    # discovery path short of raw HCI socket programming, which we avoid for simplicity.
    # If BlueZ gains a reliable non-filtered BR/EDR inquiry API, revisit.
    length = max(4, int(duration * 1.25))  # --length units are 1.28 s; *1.25 ≈ wall-clock match
    # Total wall time = (length * 1.28 s inquiry) + ~5-8 s for remote name requests per device.
    # Empirically: --length=8 → ~15 s, --length=10 → ~19 s. Add 8 s buffer; floor at 20 s.
    scan_timeout = max(20, int(length * 1.28) + 8)

    # hcitool requires CAP_NET_ADMIN. Try direct first; fall back to sudo if denied.
    rc, out, err = _run(["hcitool", "scan", "--length", str(length)], timeout=scan_timeout)
    if rc != 0:
        rc, out, err = _run(["sudo", "hcitool", "scan", "--length", str(length)],
                            timeout=scan_timeout)
    if rc != 0:
        return {"devices": [], "error": err.strip() or "hcitool scan failed"}

    # Parse hcitool output:
    #   Scanning ...
    #           04:BD:BF:9B:8C:C5       Galaxy A71
    #           78:1C:3C:F5:E7:2A       VEYA-OBD-SAMPLE
    devices: list[dict] = []
    seen: set[str] = set()
    for line in out.splitlines():
        line = line.strip()
        if not line or line.startswith("Scanning"):
            continue
        parts = line.split(None, 1)
        if not parts:
            continue
        mac = parts[0].upper()
        name = parts[1] if len(parts) == 2 else ""
        if len(mac) == 17 and mac not in seen:
            seen.add(mac)
            devices.append({"mac": mac, "name": name, "paired": False, "connected": False})

    # Enrich with paired/connected status via bluetoothctl (reliable for known-paired devices)
    st = status()
    paired_macs = {d.get("mac", "").upper() for d in st.get("paired", [])}
    connected_macs = {d.get("mac", "").upper() for d in st.get("connected", [])}
    for dev in devices:
        dev["paired"] = dev["mac"] in paired_macs
        dev["connected"] = dev["mac"] in connected_macs

    return {"devices": devices, "error": ""}


def status() -> dict:
    """Return currently paired/connected BT devices and adapter state.

    Returns {"paired": [...], "connected": [...], "adapter_powered": bool, "error": ""}
    Each entry: {"mac": "AA:BB:...", "name": "..."}
    """
    # Check adapter power state
    _, show_out, _ = _btctl("show", "quit", timeout=5)
    powered = "Powered: yes" in show_out

    # List paired devices
    _, dev_out, dev_err = _btctl("devices", "quit", timeout=5)
    paired: list[dict] = []
    connected: list[dict] = []
    for line in dev_out.splitlines():
        if "Device " in line:
            parts = line.strip().split()
            try:
                idx = parts.index("Device")
                mac = parts[idx + 1].upper()
                name = " ".join(parts[idx + 2:]) if len(parts) > idx + 2 else ""
            except (ValueError, IndexError):
                continue
            if len(mac) == 17:
                paired.append({"mac": mac, "name": name})

    # Check which are in range / connected
    for dev in paired:
        dev["in_range"] = is_device_in_range(dev["mac"])
        if dev["in_range"]:
            connected.append({"mac": dev["mac"], "name": dev["name"]})

    return {
        "paired": paired,
        "connected": connected,
        "adapter_powered": powered,
        "error": "",
    }


def pair(mac: str) -> dict:
    """Pair, trust, and connect a device by MAC address.

    Returns {"ok": bool, "error": ""}
    """
    mac = mac.upper()

    # bt-agent systemd service handles NoInputNoOutput globally; registering a duplicate
    # agent here conflicts and causes "Failed to register agent object" / "No agent is
    # registered" errors that break the whole pair flow — so omit agent commands entirely.
    #
    # bluez's device cache must be populated before `pair <mac>` will work; without a
    # prior scan inside bluetoothctl, it returns "Device not available" even when the
    # remote is discoverable.  Run a 5-second classic scan first, then pair/trust/connect
    # all in the same session (one Popen so the cache persists across commands).
    try:
        # --agent NoInputNoOutput makes bluetoothctl's built-in agent auto-accept
        # Numeric Comparison (SSP passkey) prompts without human interaction.
        proc = subprocess.Popen(
            ["bluetoothctl", "--agent", "NoInputNoOutput"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError:
        return {"ok": False, "error": "bluetoothctl not found"}

    try:
        proc.stdin.write("power on\n")
        proc.stdin.write("scan bredr\n")  # BR/EDR inquiry; default "scan on" is LE-only
        proc.stdin.flush()
        time.sleep(8)  # BR/EDR inquiry is slower than LE; 8 s is reliable
        proc.stdin.write(f"pair {mac}\n")
        proc.stdin.flush()
        time.sleep(6)  # wait for pair handshake (NoInputNoOutput is fast, but give margin)
        proc.stdin.write(f"trust {mac}\n")
        proc.stdin.write(f"connect {mac}\n")
        proc.stdin.write("quit\n")
        # Do NOT close stdin here — communicate() flushes and closes it;
        # manually closing first causes ValueError on Python 3.13.
    except BrokenPipeError:
        pass  # bluetoothctl exited early; fall through to collect output

    try:
        out, err = proc.communicate(timeout=45)  # 8s scan + 6s pair + trust + connect
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        return {"ok": False, "error": "pairing timed out"}

    combined = out + err
    combined_lower = combined.lower()

    # Success indicators (check before any failure scan)
    if "pairing successful" in combined_lower:
        return {"ok": True, "error": ""}
    if "connection successful" in combined_lower:
        return {"ok": True, "error": ""}
    if "already exists" in combined_lower or "alreadyexists" in combined_lower:
        return {"ok": True, "error": ""}

    # Device disappeared during pairing
    if f"device {mac.lower()} not available" in combined_lower:
        return {"ok": False, "error": "Device went out of range during pairing"}

    # Explicit pair-failure line from bluetoothctl
    for line in combined.splitlines():
        if "Failed to pair" in line:
            return {"ok": False, "error": line.strip()}

    # Generic fallback — surface the first suspicious line
    if "failed" in combined_lower or "not available" in combined_lower:
        for line in combined.splitlines():
            if "failed" in line.lower() or "not available" in line.lower():
                return {"ok": False, "error": line.strip()}
        return {"ok": False, "error": "pairing failed"}

    return {"ok": True, "error": ""}


def unpair(mac: str) -> dict:
    """Unpair (remove) a device.

    Returns {"ok": bool, "error": ""}
    """
    mac = mac.upper()
    _, out, err = _btctl(f"remove {mac}", "quit", timeout=10)
    combined = (out + err).lower()
    if "removed" in combined or "done" in combined:
        return {"ok": True, "error": ""}
    if "not available" in combined:
        return {"ok": True, "error": ""}  # already gone
    return {"ok": False, "error": out.strip() or err.strip()}


def connect(mac: str) -> dict:
    """Connect to a paired device (does not re-pair).

    Returns {"ok": bool, "error": ""}
    """
    mac = mac.upper()
    _, out, err = _btctl(f"connect {mac}", "quit", timeout=20)
    combined = (out + err).lower()
    if "failed" in combined and "already connected" not in combined:
        return {"ok": False, "error": out.strip() or err.strip()}
    return {"ok": True, "error": ""}


def disconnect(mac: str) -> dict:
    """Disconnect from a device but keep it paired.

    Returns {"ok": bool, "error": ""}
    """
    mac = mac.upper()
    _, out, err = _btctl(f"disconnect {mac}", "quit", timeout=10)
    combined = (out + err).lower()
    if "failed" in combined:
        return {"ok": False, "error": out.strip() or err.strip()}
    return {"ok": True, "error": ""}


def main() -> None:
    if len(sys.argv) < 2:
        print(json.dumps({"error": "no command"}))
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "scan":
        d = int(sys.argv[2]) if len(sys.argv) > 2 else 8
        print(json.dumps(scan(d)))
    elif cmd == "status":
        print(json.dumps(status()))
    elif cmd == "pair":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "pair requires MAC"}))
            sys.exit(1)
        print(json.dumps(pair(sys.argv[2])))
    elif cmd == "unpair":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "unpair requires MAC"}))
            sys.exit(1)
        print(json.dumps(unpair(sys.argv[2])))
    elif cmd == "connect":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "connect requires MAC"}))
            sys.exit(1)
        print(json.dumps(connect(sys.argv[2])))
    elif cmd == "disconnect":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "disconnect requires MAC"}))
            sys.exit(1)
        print(json.dumps(disconnect(sys.argv[2])))
    else:
        print(json.dumps({"error": f"unknown command: {cmd}"}))
        sys.exit(1)


if __name__ == "__main__":
    main()
