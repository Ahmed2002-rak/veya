"""
VEYA — BLE GATT/NUS ↔ TCP Bridge                        ble_bridge.py
=====================================================================

Connects to an ESP32-S3 BLE device exposing the Nordic UART Service (NUS)
and forwards line-delimited JSON frames bidirectionally to/from the VEYA
core TCP listener at 127.0.0.1:9000.

PARALLEL transport — bt_bridge.py (Bluetooth Classic SPP) is untouched.
Select which bridge ws_server spawns via the `transport` field in
~/.veya/bt_config.json: "ble" (this file) or "spp" (bt_bridge.py, default).

The status file path, "connected"/"disconnected" strings, TCP slot retry
logic, and the BLE-first ordering are IDENTICAL to bt_bridge.py, so the
Phase 3.0h state machine (ws_server watcher, core transitions) is unchanged.

NUS UUIDs:
  Service  : 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
  TX char  : 6E400003-B5A3-F393-E0A9-E50E24DCCA9E  (ESP32 → Pi, notify)
  RX char  : 6E400002-B5A3-F393-E0A9-E50E24DCCA9E  (Pi → ESP32, write)

Exit codes:
  0 — clean exit (TCP host gone or user interrupt)
  1 — unrecoverable error (bleak import failure, etc.)
  2 — no BLE MAC configured and no name-prefix device found on first scan

Usage:
  python -m services.veya_core.ble_bridge
  python -m services.veya_core.ble_bridge --mac 30:ED:A0:A3:85:C1
  python -m services.veya_core.ble_bridge --tcp-port 9000
"""
from __future__ import annotations

import argparse
import asyncio
import json
import logging
import logging.handlers
import pathlib
import sys
import time
from typing import Optional, Tuple

log = logging.getLogger("veya.ble_bridge")

# ── Config / IPC paths ────────────────────────────────────────────────────────
_CONFIG_PATH    = pathlib.Path.home() / ".veya" / "bt_config.json"
_LOG_PATH       = pathlib.Path.home() / "veya" / "logs" / "ble_bridge.log"
_BT_STATUS_FILE = pathlib.Path("/tmp/veya_bt_bridge_status.txt")

# ── NUS characteristic UUIDs (lowercase for bleak compatibility) ──────────────
_NUS_TX_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"  # ESP32 → Pi (notify)
_NUS_RX_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"  # Pi → ESP32 (write)

# ── BLE device discovery ──────────────────────────────────────────────────────
_BLE_NAME_PREFIX = "VEYA-BLE-OBD"
_DESIRED_MTU     = 247   # request during connection; actual MTU may differ

# ── Reconnect / TCP-slot timing (mirrors bt_bridge.py values) ─────────────────
_BLE_RECONNECT_SLEEP  = 5.0   # seconds between BLE reconnect attempts
_TCP_SLOT_BUDGET      = 15.0  # total seconds to wait for mock_source to vacate
_TCP_SLOT_INTERVAL    = 1.0   # seconds between TCP slot retries
_TCP_CONNECT_TIMEOUT  = 5.0   # seconds for asyncio.open_connection()


# ── Helpers ───────────────────────────────────────────────────────────────────

def _write_bt_status(state: str) -> None:
    """Write connection state to the IPC status file. Silently ignores errors."""
    try:
        _BT_STATUS_FILE.write_text(state)
    except Exception:
        pass


def _touch_status_file() -> None:
    """Touch the status file so the ws_server watcher knows the bridge is live."""
    try:
        import os
        os.utime(str(_BT_STATUS_FILE), None)
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
        log.warning("[ble_bridge] could not read bt_config.json: %s", exc)
        return {}


async def _scan_by_name_prefix(prefix: str, timeout: float = 10.0):
    """Return the first BLEDevice whose name starts with `prefix`, or None."""
    from bleak import BleakScanner
    devices = await BleakScanner.discover(timeout=timeout)
    for d in devices:
        if d.name and d.name.startswith(prefix):
            log.info("[ble_bridge] found device by name: %s (%s)", d.name, d.address)
            return d
    return None


async def _resolve_target(mac: str):
    """Return a target suitable for BleakClient (MAC string or BLEDevice)."""
    if mac:
        # BleakClient accepts a MAC string directly on Linux — no scan needed.
        return mac
    log.info("[ble_bridge] no MAC — scanning for name prefix '%s'", _BLE_NAME_PREFIX)
    device = await _scan_by_name_prefix(_BLE_NAME_PREFIX)
    return device  # may be None


# ── Bidirectional forwarding ──────────────────────────────────────────────────

async def _forward(
    *,
    client,               # BleakClient (connected)
    notify_queue: "asyncio.Queue[Optional[bytes]]",
    tcp_reader: asyncio.StreamReader,
    tcp_writer: asyncio.StreamWriter,
    rx_uuid: str,
    use_response: bool,
    max_write: int,
) -> str:
    """
    Forward frames between BLE and TCP until one side closes.

    BLE → TCP (inbound):
      Notification handler appends bytes to notify_queue.
      This task reassembles \\n-terminated JSON lines from the BLE byte
      stream (which may be fragmented across multiple notifications) and
      writes complete lines to the TCP StreamWriter.

    TCP → BLE (outbound):
      Reads complete \\n-terminated lines from the TCP StreamReader
      (commands from core: query_dtc, clear_dtc, query_mileage, etc.)
      and writes them to the BLE RX characteristic in ≤ max_write-byte
      chunks to satisfy the ATT MTU limit.

    Returns: "ble_closed" | "tcp_closed" | "error"
    """
    from bleak import BleakError

    loop = asyncio.get_running_loop()
    done: asyncio.Future[str] = loop.create_future()

    def _resolve(reason: str) -> None:
        if not done.done():
            done.set_result(reason)

    async def ble_to_tcp() -> None:
        """Reassemble BLE notification chunks into \\n-terminated lines → TCP."""
        buf = b""
        # Alignment phase: discard bytes until the first \n so reassembly
        # starts on a clean JSON line boundary.  Handles any mid-line
        # fragment that accumulated in notify_queue while the slot probe
        # was cycling through TCP rejections.
        try:
            while not done.done():
                try:
                    chunk = await asyncio.wait_for(notify_queue.get(), timeout=30.0)
                except asyncio.TimeoutError:
                    _touch_status_file()
                    continue
                if chunk is None:
                    return
                buf += chunk
                if b"\n" in buf:
                    _, buf = buf.split(b"\n", 1)   # discard up to first \n
                    break
        except asyncio.CancelledError:
            return
        except Exception as exc:
            log.exception("[ble_bridge] ble_to_tcp alignment: %s", exc)
            _resolve("error")
            return

        try:
            while not done.done():
                try:
                    chunk = await asyncio.wait_for(notify_queue.get(), timeout=30.0)
                except asyncio.TimeoutError:
                    # Heartbeat: touch status file so watcher sees us alive.
                    _touch_status_file()
                    continue
                if chunk is None:       # sentinel from cleanup
                    break
                buf += chunk
                # Split reassembled buffer on newlines; forward complete lines.
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    if line:
                        tcp_writer.write(line + b"\n")
                        await tcp_writer.drain()
        except (BrokenPipeError, ConnectionResetError, OSError) as exc:
            log.info("[ble_bridge] TCP write error: %s", exc)
            _resolve("tcp_closed")
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            log.exception("[ble_bridge] ble_to_tcp unexpected: %s", exc)
            _resolve("error")

    async def tcp_to_ble() -> None:
        """Read \\n-terminated command lines from TCP → write to BLE RX char."""
        try:
            while not done.done():
                try:
                    line = await asyncio.wait_for(tcp_reader.readline(), timeout=30.0)
                except asyncio.TimeoutError:
                    continue
                if not line:
                    # EOF: core closed the TCP connection.
                    log.info("[ble_bridge] TCP EOF from core")
                    _resolve("tcp_closed")
                    break
                # Write in max_write-byte chunks (ATT MTU minus 3 overhead).
                # Commands are typically ~40 bytes so this is rarely split.
                data = bytes(line)
                for offset in range(0, len(data), max_write):
                    await client.write_gatt_char(
                        rx_uuid, data[offset:offset + max_write],
                        response=use_response,
                    )
        except BleakError as exc:
            log.info("[ble_bridge] BLE write error: %s", exc)
            _resolve("ble_closed")
        except (BrokenPipeError, ConnectionResetError, OSError) as exc:
            log.info("[ble_bridge] TCP read error: %s", exc)
            _resolve("tcp_closed")
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            log.exception("[ble_bridge] tcp_to_ble unexpected: %s", exc)
            _resolve("error")

    async def ble_watchdog() -> None:
        """Detect BLE disconnect while forwarding is running."""
        while not done.done():
            await asyncio.sleep(1.0)
            if not client.is_connected:
                log.info("[ble_bridge] BLE disconnected (watchdog)")
                _resolve("ble_closed")
                break

    t_b2t = asyncio.create_task(ble_to_tcp())
    t_t2b = asyncio.create_task(tcp_to_ble())
    t_wdg = asyncio.create_task(ble_watchdog())

    reason = await done
    t_b2t.cancel(); t_t2b.cancel(); t_wdg.cancel()
    await asyncio.gather(t_b2t, t_t2b, t_wdg, return_exceptions=True)
    notify_queue.put_nowait(None)   # unblock ble_to_tcp if it is waiting
    return reason


# ── Main session ──────────────────────────────────────────────────────────────

async def run_async(mac: str, tcp_host: str, tcp_port: int) -> int:
    """
    Main BLE bridge loop. Returns exit code (0 = clean, 1 = fatal).

    Structure mirrors bt_bridge.run() exactly:
      outer loop  — BLE reconnect
      inner loop  — TCP slot acquisition (Phase 3.0h race fix)
      _forward()  — bidirectional forwarding
    """
    from bleak import BleakClient, BleakError

    log.info("[ble_bridge] Starting — BLE=%s TCP=%s:%d",
             mac or "(auto-discover)", tcp_host, tcp_port)
    # Clear stale "connected" left by a previous crash so the watcher never
    # fires a spurious B→C transition on stale data.
    _write_bt_status("disconnected")

    while True:
        # ── 1. Resolve BLE target (MAC or auto-scan) ──────────────────────
        target = await _resolve_target(mac)
        if target is None:
            log.warning("[ble_bridge] no BLE device found — retry in %.0fs",
                        _BLE_RECONNECT_SLEEP)
            await asyncio.sleep(_BLE_RECONNECT_SLEEP)
            continue

        # ── 2. Connect BLE (BLE FIRST — do NOT touch TCP until connected) ─
        # Keeping BLE-first prevents the state-B bug: if BT fails, the mock
        # stays running and the dashboard never goes dark.
        reason = "error"
        try:
            async with BleakClient(target, timeout=10.0) as client:
                if not client.is_connected:
                    log.warning("[ble_bridge] BleakClient.connect() returned False")
                    raise BleakError("not connected after context-manager entry")

                log.info("[ble_bridge] BLE GATT connected to %s",
                         getattr(target, "address", target))

                # ── 3. MTU negotiation ─────────────────────────────────────
                # dbus-fast (bleak Linux backend) negotiates MTU automatically
                # during connection. Log the result; request a larger value if
                # the platform supports it.
                current_mtu: int = getattr(client, "mtu_size", 23)
                log.info("[ble_bridge] MTU after connect: %d bytes", current_mtu)
                if hasattr(client, "request_mtu"):
                    try:
                        negotiated = await client.request_mtu(_DESIRED_MTU)
                        current_mtu = negotiated
                        log.info("[ble_bridge] MTU request=%d negotiated=%d",
                                 _DESIRED_MTU, negotiated)
                    except Exception as exc:
                        log.info("[ble_bridge] MTU explicit request not supported "
                                 "on this backend: %s", exc)

                # ATT overhead is 3 bytes (opcode + handle); subtract from MTU
                # to get the maximum payload per write operation.
                max_write = max(20, current_mtu - 3)
                log.info("[ble_bridge] max BLE write chunk: %d bytes", max_write)

                # ── 4. Inspect RX characteristic write properties ───────────
                # NUS RX (6E400002) typically supports write-without-response
                # for throughput. Fall back to write-with-response if the
                # firmware's characteristic doesn't advertise the former.
                rx_char = client.services.get_characteristic(_NUS_RX_UUID)
                if rx_char is None:
                    log.error("[ble_bridge] RX char %s not found in services — "
                              "is the NUS service running?", _NUS_RX_UUID)
                    raise BleakError("RX characteristic not found")

                props = [p.lower() for p in rx_char.properties]
                use_response = "write-without-response" not in props
                log.info("[ble_bridge] RX char properties: %s → "
                         "write_response=%s", props, use_response)

                # ── 5. Subscribe to TX notifications ───────────────────────
                notify_queue: asyncio.Queue[Optional[bytes]] = asyncio.Queue()

                def _on_notify(_sender, data: bytearray) -> None:
                    notify_queue.put_nowait(bytes(data))

                await client.start_notify(_NUS_TX_UUID, _on_notify)
                log.info("[ble_bridge] subscribed to TX notifications (%s)",
                         _NUS_TX_UUID)

                # ── 6. Write "connected" BEFORE opening TCP (Phase 3.0h) ───
                # ws_server watcher reads this file every 1.5 s. Writing here
                # (before TCP open) ensures the correct signal order:
                # watcher fires B→C transition → kills mock_source → TCP slot
                # is freed for us to take.
                _write_bt_status("connected")

                # ── 7. TCP slot retry loop (Phase 3.0h race fix) ────────────
                # TcpSourceServer may reject us immediately (mode_error + close
                # in < 100 ms) if mock_source still holds the slot. We detect
                # fast-close by elapsed time, re-ping the status file, and
                # retry until the slot is free or the budget expires.
                slot_deadline = time.monotonic() + _TCP_SLOT_BUDGET

                while True:
                    if not client.is_connected:
                        log.info("[ble_bridge] BLE lost while waiting for TCP slot")
                        reason = "ble_closed"
                        break

                    try:
                        tcp_reader, tcp_writer = await asyncio.wait_for(
                            asyncio.open_connection(tcp_host, tcp_port),
                            timeout=_TCP_CONNECT_TIMEOUT,
                        )
                        log.info("[ble_bridge] TCP connected → %s:%d",
                                 tcp_host, tcp_port)
                    except (ConnectionRefusedError, OSError,
                            asyncio.TimeoutError) as exc:
                        if time.monotonic() < slot_deadline:
                            log.info("[ble_bridge] TCP unreachable (%s) — "
                                     "retry in %.0fs", exc, _TCP_SLOT_INTERVAL)
                            _write_bt_status("connected")   # re-ping watcher
                            await asyncio.sleep(_TCP_SLOT_INTERVAL)
                            continue
                        log.error("[ble_bridge] TCP core unreachable after "
                                  "%.0fs budget — exiting", _TCP_SLOT_BUDGET)
                        _write_bt_status("disconnected")
                        return 0

                    # ── 8. Slot probe — do NOT enter _forward until accepted ──
                    # An accepted source gets silence; a rejected source gets
                    # a mode_error frame immediately then a TCP close.
                    # Read with a short timeout:
                    #   TimeoutError → silence = slot is ours
                    #   data / EOF   → rejection frame = slot still busy
                    # This keeps _forward (and its ble_to_tcp/tcp_to_ble
                    # tasks) from being started and torn down repeatedly
                    # during slot contention, which was disrupting bleak's
                    # BlueZ notification dispatch.
                    slot_accepted = False
                    try:
                        first_line = await asyncio.wait_for(
                            tcp_reader.readline(), timeout=0.5
                        )
                        if first_line:
                            try:
                                frame = json.loads(first_line)
                                log.info(
                                    "[ble_bridge] TCP slot busy: %s",
                                    frame.get("reason", "(no reason)"),
                                )
                            except Exception:
                                log.info(
                                    "[ble_bridge] TCP slot: unexpected probe "
                                    "data: %s", first_line[:80],
                                )
                        else:
                            log.info("[ble_bridge] TCP slot: probe got EOF")
                    except asyncio.TimeoutError:
                        slot_accepted = True
                        log.info("[ble_bridge] TCP slot acquired — "
                                 "no rejection in 0.5 s")

                    if not slot_accepted:
                        try:
                            tcp_writer.close()
                            await asyncio.wait_for(
                                tcp_writer.wait_closed(), timeout=2.0
                            )
                        except Exception:
                            pass
                        if time.monotonic() < slot_deadline:
                            log.info(
                                "[ble_bridge] TCP slot busy — re-ping watcher, "
                                "retry in %.0fs", _TCP_SLOT_INTERVAL,
                            )
                            _write_bt_status("connected")
                            await asyncio.sleep(_TCP_SLOT_INTERVAL)
                            continue
                        log.error(
                            "[ble_bridge] TCP slot not freed within "
                            "%.0fs budget — exiting", _TCP_SLOT_BUDGET,
                        )
                        _write_bt_status("disconnected")
                        return 0

                    # ── 9. Bidirectional forwarding — called exactly once ───
                    # ble_to_tcp() performs line-boundary alignment before
                    # forwarding to handle any queue fragment from probe phase.
                    reason = await _forward(
                        client=client,
                        notify_queue=notify_queue,
                        tcp_reader=tcp_reader,
                        tcp_writer=tcp_writer,
                        rx_uuid=_NUS_RX_UUID,
                        use_response=use_response,
                        max_write=max_write,
                    )
                    log.info("[ble_bridge] forward ended: %s", reason)

                    try:
                        tcp_writer.close()
                        await asyncio.wait_for(tcp_writer.wait_closed(), timeout=2.0)
                    except Exception:
                        pass

                    break   # real session ended (BLE closed or TCP core closed)

        except BleakError as exc:
            log.warning("[ble_bridge] BLE connect/session error: %s", exc)
            reason = "ble_closed"
        except Exception as exc:
            log.exception("[ble_bridge] unexpected error: %s", exc)
            reason = "error"

        _write_bt_status("disconnected")

        if reason == "tcp_closed":
            log.info("[ble_bridge] Core TCP closed — exiting cleanly")
            return 0

        # BLE closed or error: wait then retry BLE connection.
        log.info("[ble_bridge] BLE disconnected (%s) — retry in %.0fs",
                 reason, _BLE_RECONNECT_SLEEP)
        await asyncio.sleep(_BLE_RECONNECT_SLEEP)
        # loop back to BLE-only retry — do NOT reopen TCP immediately


def main() -> None:
    _setup_logging()

    parser = argparse.ArgumentParser(description="VEYA BLE GATT ↔ TCP bridge")
    parser.add_argument(
        "--mac", default="",
        help="BLE MAC address of the ESP32-S3 (overrides bt_config.json)",
    )
    parser.add_argument("--tcp-host", default="127.0.0.1")
    parser.add_argument("--tcp-port", type=int, default=9000)
    # Accept --rfcomm-channel silently so ws_server can pass identical args
    # to both bt_bridge and ble_bridge without needing to know the transport.
    parser.add_argument("--rfcomm-channel", type=int, default=1,
                        help=argparse.SUPPRESS)
    args = parser.parse_args()

    # Resolve MAC: CLI flag > config file
    mac = args.mac.strip().upper() if args.mac.strip() else ""
    if not mac:
        cfg = _load_config()
        mac = cfg.get("esp32_mac", "").strip().upper()

    if not mac:
        log.info("[ble_bridge] No MAC in config — will auto-discover by name "
                 "prefix '%s'", _BLE_NAME_PREFIX)

    try:
        exit_code = asyncio.run(run_async(mac, args.tcp_host, args.tcp_port))
    except KeyboardInterrupt:
        log.info("[ble_bridge] interrupted by user")
        _write_bt_status("disconnected")
        exit_code = 0

    sys.exit(exit_code)


# Support both `python -m services.veya_core.ble_bridge` and
# `python services/veya_core/ble_bridge.py` (standalone test mode)
if __package__ in (None, ""):
    _pkg_root = pathlib.Path(__file__).resolve().parent.parent.parent
    if str(_pkg_root) not in sys.path:
        sys.path.insert(0, str(_pkg_root))

if __name__ == "__main__":
    main()
