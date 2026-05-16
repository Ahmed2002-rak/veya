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
    # 1. Enable scan for `duration` seconds using bluetoothctl with a timeout
    scan_timeout = duration + 3
    _, scan_out, scan_err = _btctl(
        "scan on",
        f"sleep {duration}",
        "scan off",
        "devices",
        "quit",
        timeout=scan_timeout + 5,
    )

    # If that hung, fall back to hcitool scan (classic inquiry)
    if not scan_out.strip():
        rc, out, err = _run(["hcitool", "scan", "--length", str(duration // 2 or 4)],
                            timeout=duration + 10)
        if rc != 0:
            return {"devices": [], "error": err.strip() or "scan failed"}
        devices = []
        for line in out.splitlines():
            line = line.strip()
            if not line or line.startswith("Scanning"):
                continue
            parts = line.split(None, 1)
            if len(parts) == 2:
                mac, name = parts
                devices.append({"mac": mac.upper(), "name": name, "paired": False, "connected": False})
        return {"devices": devices, "error": ""}

    # Parse bluetoothctl "devices" output to get discovered MACs/names
    devices: list[dict] = []
    seen: set[str] = set()
    for line in scan_out.splitlines():
        # Lines like: "Device AA:BB:CC:DD:EE:FF Device Name"
        if "Device " in line:
            parts = line.strip().split()
            try:
                idx = parts.index("Device")
                mac = parts[idx + 1].upper()
                name = " ".join(parts[idx + 2:]) if len(parts) > idx + 2 else ""
            except (ValueError, IndexError):
                continue
            if len(mac) == 17 and mac not in seen:
                seen.add(mac)
                devices.append({"mac": mac, "name": name, "paired": False, "connected": False})

    # Enrich with paired/connected status
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
    # We need to run pair/trust/connect sequentially with appropriate timeouts.
    # Use NoInputNoOutput agent to skip PIN confirmation for devices that support SSP.
    _, pair_out, pair_err = _btctl(
        "agent NoInputNoOutput",
        "default-agent",
        f"pair {mac}",
        "quit",
        timeout=30,
    )
    combined = (pair_out + pair_err).lower()
    if "failed" in combined or "error" in combined:
        # Check if it was already paired
        if "already exists" not in combined:
            return {"ok": False, "error": pair_out.strip() or pair_err.strip()}

    # Trust the device so it auto-connects later
    _, trust_out, trust_err = _btctl(f"trust {mac}", "quit", timeout=10)
    trust_combined = (trust_out + trust_err).lower()
    if "failed" in trust_combined:
        return {"ok": False, "error": trust_out.strip() or trust_err.strip()}

    # Connect
    _, conn_out, conn_err = _btctl(f"connect {mac}", "quit", timeout=20)
    conn_combined = (conn_out + conn_err).lower()
    if "failed" in conn_combined and "already connected" not in conn_combined:
        # Connection might still succeed if SPP is busy — treat as partial success
        # because pairing itself worked
        return {"ok": True, "error": conn_err.strip() or "paired but connect failed"}

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
