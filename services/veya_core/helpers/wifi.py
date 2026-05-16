#!/usr/bin/env python3
"""Wi-Fi management via nmcli.
Usage:
  wifi.py scan                      # returns JSON list of networks
  wifi.py status                    # returns JSON current connection state
  wifi.py connect <SSID> <PASS>     # connect to SSID (password may be empty string)
  wifi.py disconnect                # disconnect current wlan device
"""
from __future__ import annotations
import json
import subprocess
import sys


def scan() -> dict:
    # Trigger a rescan first (non-blocking, best-effort)
    subprocess.run(["nmcli", "device", "wifi", "rescan"],
                   capture_output=True, timeout=8)
    r = subprocess.run(
        ["nmcli", "--terse", "--fields", "SSID,SIGNAL,SECURITY,IN-USE",
         "device", "wifi", "list"],
        capture_output=True, text=True, timeout=15
    )
    if r.returncode != 0:
        return {"error": r.stderr.strip()}

    seen: set[str] = set()
    networks: list[dict] = []
    for line in r.stdout.strip().splitlines():
        if not line:
            continue
        # nmcli --terse uses : as separator; escape colons inside values with \:
        # Split on unescaped colons
        parts = line.replace("\\:", "\x00").split(":")
        parts = [p.replace("\x00", ":") for p in parts]
        if len(parts) < 4:
            continue
        ssid, signal, security, in_use = parts[0], parts[1], parts[2], parts[3]
        if not ssid or ssid in seen:
            continue
        seen.add(ssid)
        networks.append({
            "ssid": ssid,
            "signal": int(signal) if signal.isdigit() else 0,
            "secured": bool(security.strip()),
            "active": in_use.strip() == "*",
        })

    networks.sort(key=lambda n: -n["signal"])
    return {"networks": networks}


def status() -> dict:
    r = subprocess.run(
        ["nmcli", "--terse", "--fields", "NAME,DEVICE,STATE",
         "connection", "show", "--active"],
        capture_output=True, text=True, timeout=5
    )
    if r.returncode != 0:
        return {"connected": False, "error": r.stderr.strip()}
    for line in r.stdout.strip().splitlines():
        if not line:
            continue
        parts = line.split(":")
        if len(parts) >= 3 and "wlan" in parts[1]:
            return {"connected": True, "ssid": parts[0], "device": parts[1]}
    return {"connected": False}


def connect(ssid: str, password: str) -> dict:
    cmd = ["nmcli", "device", "wifi", "connect", ssid]
    if password:
        cmd += ["password", password]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if r.returncode == 0:
        return {"ok": True}
    err = r.stderr.strip() or r.stdout.strip()
    return {"ok": False, "error": err}


def disconnect() -> dict:
    # Find the active wlan device
    st = status()
    device = st.get("device", "wlan0")
    r = subprocess.run(
        ["nmcli", "device", "disconnect", device],
        capture_output=True, text=True, timeout=10
    )
    return {"ok": r.returncode == 0, "error": r.stderr.strip()}


def main() -> None:
    if len(sys.argv) < 2:
        print(json.dumps({"error": "no command"}))
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "scan":
        print(json.dumps(scan()))
    elif cmd == "status":
        print(json.dumps(status()))
    elif cmd == "connect":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "connect requires SSID"}))
            sys.exit(1)
        ssid = sys.argv[2]
        password = sys.argv[3] if len(sys.argv) > 3 else ""
        print(json.dumps(connect(ssid, password)))
    elif cmd == "disconnect":
        print(json.dumps(disconnect()))
    else:
        print(json.dumps({"error": f"unknown command: {cmd}"}))
        sys.exit(1)


if __name__ == "__main__":
    main()
