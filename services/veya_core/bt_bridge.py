"""
VEYA — Bluetooth SPP ↔ TCP Bridge                      bt_bridge.py
=====================================================================

Reads the paired ESP32 MAC from ~/.veya/bt_config.json, opens an
RFCOMM (BT-Classic SPP) socket to the ESP32, and forwards bytes
bidirectionally to/from the VEYA core TCP listener at 127.0.0.1:9000.

Exit codes:
  0 — clean exit (no config, TCP host gone, or user interrupt)
  1 — unrecoverable error (BT adapter not found, permission denied)
  2 — no ESP32 MAC configured

Usage:
  python -m services.veya_core.bt_bridge
  python -m services.veya_core.bt_bridge --mac AA:BB:CC:DD:EE:FF
  python -m services.veya_core.bt_bridge --tcp-port 9000 --rfcomm-channel 1
"""
from __future__ import annotations

import argparse
import json
import logging
import logging.handlers
import os
import pathlib
import socket
import sys
import time

log = logging.getLogger("veya.bt_bridge")

# ── Config paths ──────────────────────────────────────────────────────────────
_CONFIG_PATH    = pathlib.Path.home() / ".veya" / "bt_config.json"
_LOG_PATH       = pathlib.Path.home() / "veya" / "logs" / "bt_bridge.log"
_BT_STATUS_FILE = pathlib.Path("/tmp/veya_bt_bridge_status.txt")

# ── Reconnect timing ──────────────────────────────────────────────────────────
_BT_RECONNECT_SLEEP = 5   # seconds between BT reconnect attempts
_TCP_CONNECT_TIMEOUT = 5  # seconds


def _write_bt_status(state: str) -> None:
    """Write connection state to the IPC status file. Silently ignores errors."""
    try:
        _BT_STATUS_FILE.write_text(state)
    except Exception:
        pass


def _setup_logging() -> None:
    _LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s",
                            datefmt="%Y-%m-%d %H:%M:%S")
    fh = logging.handlers.RotatingFileHandler(
        _LOG_PATH, maxBytes=2 * 1024 * 1024, backupCount=3
    )
    fh.setFormatter(fmt)
    sh = logging.StreamHandler(sys.stderr)
    sh.setFormatter(fmt)
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    root.addHandler(fh)
    root.addHandler(sh)


def _load_config() -> dict:
    if not _CONFIG_PATH.exists():
        return {}
    try:
        return json.loads(_CONFIG_PATH.read_text())
    except Exception as exc:
        log.warning("Could not read bt_config.json: %s", exc)
        return {}


def _connect_tcp(host: str, port: int) -> socket.socket:
    """Connect to the VEYA core TCP listener. Raises on failure."""
    s = socket.create_connection((host, port), timeout=_TCP_CONNECT_TIMEOUT)
    s.settimeout(None)  # blocking I/O after connect
    log.info("[bridge] TCP connected → %s:%d", host, port)
    return s


def _connect_bt(mac: str, channel: int) -> socket.socket:
    """Open an RFCOMM socket to the ESP32 using Linux's native BTPROTO_RFCOMM.
    No external libraries needed — AF_BLUETOOTH is part of the stdlib on Linux."""
    log.info("[bridge] connecting to %s channel %d", mac, channel)
    s = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM)
    s.settimeout(10.0)
    s.connect((mac, channel))
    s.settimeout(None)  # blocking I/O after connect
    log.info("[bridge] BT RFCOMM socket open")
    return s


def _forward(bt_sock: "socket.socket", tcp_sock: socket.socket) -> str:
    """Forward bytes bidirectionally until one side closes.

    Returns "bt_closed" | "tcp_closed" to indicate which side dropped.
    Uses blocking select() so we don't busy-spin.
    """
    import select

    bt_fd  = bt_sock.fileno()
    tcp_fd = tcp_sock.fileno()

    while True:
        try:
            readable, _, _ = select.select([bt_fd, tcp_fd], [], [], 30.0)
        except Exception as exc:
            log.warning("[bridge] select error: %s", exc)
            return "error"

        for fd in readable:
            try:
                data = os.read(fd, 4096)
            except OSError as exc:
                log.info("[bridge] read error on fd=%d: %s", fd, exc)
                return "bt_closed" if fd == bt_fd else "tcp_closed"

            if not data:
                return "bt_closed" if fd == bt_fd else "tcp_closed"

            dest_fd = tcp_fd if fd == bt_fd else bt_fd
            try:
                os.write(dest_fd, data)
            except OSError as exc:
                log.info("[bridge] write error on fd=%d: %s", dest_fd, exc)
                return "bt_closed" if dest_fd == bt_fd else "tcp_closed"
            try:
                os.utime("/tmp/veya_bt_bridge_status.txt", None)
            except Exception:
                pass


def run(mac: str, tcp_host: str, tcp_port: int, rfcomm_channel: int) -> int:
    """Main bridge loop. Returns exit code."""
    log.info("[bridge] Starting — ESP32 MAC=%s TCP=%s:%d RFCOMM ch=%d",
             mac, tcp_host, tcp_port, rfcomm_channel)
    # Clear any stale "connected" left by a previous crash so the ws_server
    # watcher never auto-switches to REAL based on stale file content.
    _write_bt_status("disconnected")

    while True:
        # ── 1. Connect to ESP32 over BT RFCOMM (BT FIRST) ────────────────
        # Do NOT touch TCP until BT succeeds — core must not see a source
        # connection while we have no real telemetry, as that would kill
        # mock_source and leave the dashboard with dead gauges (state-B bug).
        try:
            bt_sock = _connect_bt(mac, rfcomm_channel)
        except Exception as exc:
            log.warning("[bridge] BT connect failed (%s) — will retry in %ds", exc, _BT_RECONNECT_SLEEP)
            time.sleep(_BT_RECONNECT_SLEEP)
            continue

        # ── 2. Signal "connected" BEFORE opening TCP ──────────────────────
        # ws_server watcher reads this file to trigger B→C state transition
        # (kill mock_source, accept REAL source). Writing before TCP open
        # ensures the state machine sees the correct signal order.
        _write_bt_status("connected")

        # ── 3. Connect to TCP core (with retry for state-B→C race) ─────────
        # TcpSourceServer accepts the TCP handshake even when a source is
        # already connected, then immediately sends a mode_error frame and
        # closes the connection — _forward() returns "tcp_closed" in ~100 ms.
        # We detect this by elapsed time: if < 2 s we were rejected (mock
        # still holds the slot). Keep BT open and retry until ws_server's
        # watcher kills mock (~1-3 s after it reads the "connected" file).
        _TCP_SLOT_BUDGET   = 15.0   # total seconds to wait for the slot
        _TCP_SLOT_INTERVAL = 1.0    # seconds between retries
        slot_deadline = time.monotonic() + _TCP_SLOT_BUDGET
        reason = "tcp_closed"

        while True:
            try:
                tcp_sock = _connect_tcp(tcp_host, tcp_port)
            except (ConnectionRefusedError, OSError) as exc:
                if time.monotonic() < slot_deadline:
                    log.info("[bridge] TCP unreachable (%s) — retry in %.0fs",
                             exc, _TCP_SLOT_INTERVAL)
                    _write_bt_status("connected")   # keep watcher triggered
                    time.sleep(_TCP_SLOT_INTERVAL)
                    continue
                log.error("[bridge] TCP core unreachable after %.0fs — exiting",
                          _TCP_SLOT_BUDGET)
                _write_bt_status("disconnected")
                bt_sock.close()
                return 0

            # ── 4. Bidirectional forward ───────────────────────────────────
            connect_time = time.monotonic()
            reason = _forward(bt_sock, tcp_sock)
            elapsed = time.monotonic() - connect_time
            log.info("[bridge] Forward ended: %s (elapsed=%.2fs)", reason, elapsed)

            # Close TCP first so core's "source disconnect" fires immediately
            # and respawns mock_source — this is the C→B state machine transition.
            try:
                tcp_sock.close()
            except Exception:
                pass

            if reason == "tcp_closed" and elapsed < 2.0:
                # Immediate close = TcpSourceServer rejected us because
                # mock_source still holds the slot. Wait for ws_server
                # watcher to kill mock, then retry.
                if time.monotonic() < slot_deadline:
                    log.info("[bridge] TCP slot busy (rejected in %.2fs) — "
                             "waiting %.0fs then retry",
                             elapsed, _TCP_SLOT_INTERVAL)
                    _write_bt_status("connected")   # re-ping watcher
                    time.sleep(_TCP_SLOT_INTERVAL)
                    continue
                log.error("[bridge] TCP slot not freed within %.0fs budget — exiting",
                          _TCP_SLOT_BUDGET)
                _write_bt_status("disconnected")
                bt_sock.close()
                return 0

            # Real session ended — exit the TCP retry loop.
            break

        _write_bt_status("disconnected")

        try:
            bt_sock.close()
        except Exception:
            pass

        if reason == "tcp_closed":
            log.info("[bridge] Core TCP closed — exiting cleanly")
            return 0
        elif reason == "bt_closed":
            log.info("[bridge] ESP32 BT disconnected — will retry in %ds", _BT_RECONNECT_SLEEP)
            time.sleep(_BT_RECONNECT_SLEEP)
            # loop back to BT-only retry — do NOT immediately reopen TCP
        else:
            log.warning("[bridge] Unexpected reason=%s — retrying in %ds", reason, _BT_RECONNECT_SLEEP)
            time.sleep(_BT_RECONNECT_SLEEP)


def main() -> None:
    _setup_logging()

    parser = argparse.ArgumentParser(description="VEYA Bluetooth ↔ TCP bridge")
    parser.add_argument("--mac",             default="",    help="Override ESP32 MAC from config")
    parser.add_argument("--tcp-port",        type=int, default=9000)
    parser.add_argument("--rfcomm-channel",  type=int, default=1)
    parser.add_argument("--tcp-host",        default="127.0.0.1")
    args = parser.parse_args()

    # Resolve MAC: CLI flag > config file
    mac = args.mac.strip().upper() if args.mac.strip() else ""
    if not mac:
        cfg = _load_config()
        mac = cfg.get("esp32_mac", "").strip().upper()

    if not mac:
        log.info("[bridge] No ESP32 MAC configured — exiting (code 2)")
        sys.exit(2)

    sys.exit(run(mac, args.tcp_host, args.tcp_port, args.rfcomm_channel))


# Support both `python -m services.veya_core.bt_bridge` and
# `python services/veya_core/bt_bridge.py`
if __package__ in (None, ""):
    _pkg_root = pathlib.Path(__file__).resolve().parent.parent.parent
    if str(_pkg_root) not in sys.path:
        sys.path.insert(0, str(_pkg_root))

if __name__ == "__main__":
    main()
