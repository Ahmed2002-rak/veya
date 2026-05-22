#!/usr/bin/env python3
"""CLI helper — set the BLE/SPP transport in ~/.veya/bt_config.json.

Usage:
  set_transport.py ble    — use BLE GATT bridge (ble_bridge.py)
  set_transport.py spp    — use Bluetooth Classic SPP bridge (bt_bridge.py, default)
  set_transport.py show   — print current transport and full config
"""
from __future__ import annotations

import json
import pathlib
import sys

_CONFIG_PATH = pathlib.Path.home() / ".veya" / "bt_config.json"
_VALID = ("ble", "spp")


def _read() -> dict:
    if not _CONFIG_PATH.exists():
        return {}
    try:
        return json.loads(_CONFIG_PATH.read_text())
    except Exception as exc:
        print(f"Warning: could not parse config: {exc}", file=sys.stderr)
        return {}


def _write(cfg: dict) -> None:
    _CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    _CONFIG_PATH.write_text(json.dumps(cfg, indent=2))


def cmd_set(transport: str) -> None:
    cfg = _read()
    cfg["transport"] = transport
    _write(cfg)
    bridge = "ble_bridge.py (BLE GATT)" if transport == "ble" else "bt_bridge.py (SPP)"
    print(f"transport set → {transport}  ({bridge})")
    print(f"Config: {_CONFIG_PATH}")
    mac = cfg.get("esp32_mac", "")
    if not mac:
        print("Warning: esp32_mac is not set — bridge will auto-discover by name prefix.")


def cmd_show() -> None:
    cfg = _read()
    transport = cfg.get("transport", "spp (default)")
    mac       = cfg.get("esp32_mac", "(not set)")
    channel   = cfg.get("rfcomm_channel", 1)
    print(f"Config file : {_CONFIG_PATH}")
    print(f"transport   : {transport}")
    print(f"esp32_mac   : {mac}")
    print(f"rfcomm_ch   : {channel}  (ignored for BLE transport)")
    paired = cfg.get("last_paired", "(never)")
    print(f"last_paired : {paired}")


def main() -> None:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)

    verb = args[0].lower()

    if verb == "show":
        cmd_show()
    elif verb in _VALID:
        cmd_set(verb)
    else:
        print(f"Error: unknown argument '{verb}'. Use: ble | spp | show",
              file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
