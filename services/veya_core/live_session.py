"""
VEYA — Live Session Relay                                  live_session.py
=========================================================================

Relays local telemetry and DTC events from the Pi's core WebSocket to a
remote Django Channels server, giving a remote expert a live view of the
vehicle and the ability to issue "read DTC" commands.

Two WebSocket connections are maintained concurrently:
  INBOUND : ws://127.0.0.1:8765      — local core (same endpoint as QML)
  OUTBOUND: wss://<remote>/ws/obd/  — remote Channels consumer

This is a pure relay — it does NOT modify core.py, ws_server.py, or any
existing file.  The design mirrors ble_bridge.py: standalone module,
started manually for testing, spawnable from ws_server later.

Reconnect policy:
  local  — retry every 2 s (no backoff; core is expected to restart)
  remote — exponential backoff 3 s → 30 s; reset after 60 s of uptime

Status file: /tmp/veya_live_session_status.txt
  "disconnected" | "connecting" | "connected_idle" | "connected_active"

Usage:
  python -m services.veya_core.live_session
  python -m services.veya_core.live_session --url ws://127.0.0.1:9999/ws/obd/
  python -m services.veya_core.live_session --verbose
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
import warnings as _warnings
from typing import Any, Dict, Optional

_warnings.filterwarnings("ignore", category=DeprecationWarning, module="websockets")
import websockets

log = logging.getLogger("veya.live_session")

# ── Paths ─────────────────────────────────────────────────────────────────────
_CONFIG_PATH = pathlib.Path.home() / ".veya" / "server_config.json"
_LOG_PATH    = pathlib.Path.home() / "veya" / "logs" / "live_session.log"
_STATUS_FILE = pathlib.Path("/tmp/veya_live_session_status.txt")

# ── Local WS ──────────────────────────────────────────────────────────────────
_LOCAL_WS_URL        = "ws://127.0.0.1:8765"
_LOCAL_RETRY_INTERVAL = 2.0   # seconds between local reconnect attempts

# ── Remote WS reconnect ───────────────────────────────────────────────────────
_REMOTE_BACKOFF_MIN   =  3.0   # initial retry delay
_REMOTE_BACKOFF_MAX   = 30.0   # maximum retry delay
_REMOTE_RESET_AFTER   = 60.0   # reset backoff if session lasted this long
_REMOTE_WARN_AFTER    = 300.0  # 5 min — log warning but keep retrying

# ── Rate limiting: local broadcasts up to 20 Hz; remote only needs 5 Hz ──────
_UPSTREAM_HZ     = 5.0
_UPSTREAM_PERIOD = 1.0 / _UPSTREAM_HZ   # 0.2 s

# ── DTC handling ──────────────────────────────────────────────────────────────
_DTC_WAIT_TIMEOUT = 10.0   # seconds to wait for {"type":"dtc"} after query

# ── Stats ─────────────────────────────────────────────────────────────────────
_STATS_INTERVAL = 60.0   # log forwarded-frame count every N seconds


# ── Helpers ───────────────────────────────────────────────────────────────────

def _write_status(state: str) -> None:
    """Write connection state to the IPC status file. Silently ignores errors."""
    try:
        _STATUS_FILE.write_text(state)
    except Exception:
        pass


def _setup_logging(verbose: bool) -> None:
    _LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    level = logging.DEBUG if verbose else logging.INFO
    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    fh = logging.handlers.RotatingFileHandler(
        _LOG_PATH, maxBytes=2 * 1024 * 1024, backupCount=3,
    )
    fh.setFormatter(fmt)
    sh = logging.StreamHandler(sys.stderr)
    sh.setFormatter(fmt)
    root = logging.getLogger()
    root.setLevel(level)
    root.addHandler(fh)
    root.addHandler(sh)


def _load_url_from_config() -> str:
    if not _CONFIG_PATH.exists():
        return ""
    try:
        cfg = json.loads(_CONFIG_PATH.read_text())
        return cfg.get("live_session_url", "").strip()
    except Exception as exc:
        log.error("[live_session] could not read server_config.json: %s", exc)
        return ""


def _build_upstream_frame(source: Dict[str, Any]) -> Dict[str, Any]:
    """
    Build the upstream telemetry frame from a local WS telemetry frame.

    Design: "send everything, let the consumer pick."
      1. Copy all fields from source except 'schema' (Channels has its own versioning).
      2. Add "type": "live" so the consumer can route it.
      3. Add 4 alias fields his live.html browser currently expects.
      4. Add "rpm_raw" (verbatim rpm for future consumers using the canonical name).
    Alias fields are skipped if the source field is None or missing.
    """
    frame: Dict[str, Any] = {k: v for k, v in source.items() if k != "schema"}
    frame["type"] = "live"

    rpm       = source.get("rpm")
    speed_kph = source.get("speed_kph")
    coolant_c = source.get("coolant_c")
    fuel_level = source.get("fuel_level")

    if rpm is not None:
        frame["rpm"]     = int(round(float(rpm)))
        frame["rpm_raw"] = rpm
    if speed_kph is not None:
        frame["speed"] = round(float(speed_kph), 1)
    if coolant_c is not None:
        frame["temp"] = round(float(coolant_c), 1)
    if fuel_level is not None:
        frame["fuel"] = round(float(fuel_level), 1)

    return frame


# ── Session ───────────────────────────────────────────────────────────────────

class LiveSession:
    """
    Maintains two concurrent WebSocket connections and relays telemetry and
    DTC events between them.  All reconnect logic lives in run(); the inner
    session logic lives in _run_inner().
    """

    def __init__(self, remote_url: str) -> None:
        self._remote_url = remote_url
        # Latest telemetry frame — written by _local_reader, consumed by _telemetry_sender
        self._latest_telemetry: Optional[Dict[str, Any]] = None
        # DTC response delivery — _local_reader puts here, _dtc_handler gets
        self._dtc_queue: asyncio.Queue[Dict[str, Any]] = asyncio.Queue(maxsize=1)
        # Stats
        self._frames_forwarded: int = 0
        self._stats_reset_ts:   float = time.monotonic()
        # Track first forward for status transition
        self._is_active: bool = False

    def _set_status(self, state: str) -> None:
        log.info("[live_session] status → %s", state)
        _write_status(state)

    def _dtc_response_frame(self, codes: list) -> Dict[str, Any]:
        desc = "Codes défauts détectés" if codes else "OK"
        return {"type": "dtc_response", "codes": codes, "description": desc}

    def _dtc_timeout_frame(self) -> Dict[str, Any]:
        return {
            "type": "dtc_response",
            "codes": [],
            "description": "Aucune réponse du véhicule (timeout)",
        }

    # ── Inner session ──────────────────────────────────────────────────────────

    async def _run_inner(self, local_ws: Any, remote_ws: Any) -> str:
        """
        Run four concurrent tasks until one side closes.

        Tasks:
          _local_reader     — consume local WS; dispatch telemetry + DTC events
          _telemetry_sender — 5 Hz rate-capped uploader to remote WS
          _remote_reader    — receive remote commands; fire DTC handler as tasks
          _stats_logger     — log forwarded-frame count every 60 s

        Returns: "local_closed" | "remote_closed" | "error"
        """
        self._latest_telemetry = None
        self._is_active        = False

        # Drain stale DTC left from a previous session
        while not self._dtc_queue.empty():
            self._dtc_queue.get_nowait()

        loop = asyncio.get_running_loop()
        done: asyncio.Future[str] = loop.create_future()

        def resolve(reason: str) -> None:
            if not done.done():
                done.set_result(reason)

        # ── Task 1: receive from local WS ─────────────────────────────────────
        async def _local_reader() -> None:
            try:
                async for raw in local_ws:
                    try:
                        frame = json.loads(raw)
                    except Exception:
                        continue
                    if not isinstance(frame, dict):
                        continue

                    ftype = frame.get("type")
                    if ftype == "dtc":
                        codes = frame.get("codes", [])
                        log.debug("[live_session] local dtc event: %d code(s)", len(codes))
                        try:
                            self._dtc_queue.put_nowait(frame)
                        except asyncio.QueueFull:
                            log.debug("[live_session] dtc_queue full — duplicate event dropped")
                    elif ftype is not None:
                        # Other event types (clear_dtc_result, mileage_response, …) — ignore
                        pass
                    elif "rpm" in frame or "schema" in frame:
                        # Telemetry frame (no "type" key in local WS telemetry)
                        self._latest_telemetry = frame
            except websockets.ConnectionClosed:
                log.info("[live_session] local WS closed")
                resolve("local_closed")
            except Exception as exc:
                log.exception("[live_session] _local_reader: %s", exc)
                resolve("error")

        # ── Task 2: rate-capped telemetry uploader ────────────────────────────
        async def _telemetry_sender() -> None:
            try:
                while not done.done():
                    await asyncio.sleep(_UPSTREAM_PERIOD)
                    frame = self._latest_telemetry
                    if frame is None:
                        continue
                    self._latest_telemetry = None
                    upstream = _build_upstream_frame(frame)
                    await remote_ws.send(json.dumps(upstream, separators=(",", ":")))
                    self._frames_forwarded += 1
                    if not self._is_active:
                        self._is_active = True
                        self._set_status("connected_active")
            except websockets.ConnectionClosed:
                log.info("[live_session] remote WS closed (telemetry sender)")
                resolve("remote_closed")
            except Exception as exc:
                log.exception("[live_session] _telemetry_sender: %s", exc)
                resolve("error")

        # ── Task 3 (sub): handle a single command received from remote ────────
        async def _handle_remote_cmd(cmd: str) -> None:
            if cmd == "read DTC":
                log.info("[live_session] ← read DTC from remote")
                # Drain stale DTC before sending so we always get a fresh response
                while not self._dtc_queue.empty():
                    self._dtc_queue.get_nowait()
                try:
                    await local_ws.send(json.dumps({"cmd": "esp32_query_dtc"},
                                                   separators=(",", ":")))
                except Exception as exc:
                    log.error("[live_session] failed to send esp32_query_dtc: %s", exc)
                    resolve("local_closed")
                    return
                # Wait for DTC event — _local_reader will put it in the queue
                try:
                    dtc_frame = await asyncio.wait_for(
                        self._dtc_queue.get(), timeout=_DTC_WAIT_TIMEOUT
                    )
                    codes    = dtc_frame.get("codes", [])
                    response = self._dtc_response_frame(codes)
                    log.info("[live_session] → dtc_response codes=%s", codes)
                except asyncio.TimeoutError:
                    log.warning("[live_session] dtc wait timed out after %.0fs",
                                _DTC_WAIT_TIMEOUT)
                    response = self._dtc_timeout_frame()
                try:
                    await remote_ws.send(json.dumps(response, separators=(",", ":")))
                except Exception as exc:
                    log.error("[live_session] failed to send dtc_response: %s", exc)
            # ── Future-ready stubs (enable when consumer wires them) ───────────
            # elif cmd == "clear DTC":
            #     log.info("[live_session] ← clear DTC from remote")
            #     await local_ws.send(json.dumps({"cmd": "esp32_clear_dtc"},
            #                                    separators=(",", ":")))
            # elif cmd == "read mileage":
            #     log.info("[live_session] ← read mileage from remote")
            #     await local_ws.send(json.dumps({"cmd": "esp32_query_mileage"},
            #                                    separators=(",", ":")))
            else:
                log.warning("[live_session] unknown remote command: %r", cmd)

        # ── Task 3: receive from remote WS ────────────────────────────────────
        async def _remote_reader() -> None:
            try:
                async for raw in remote_ws:
                    if isinstance(raw, bytes):
                        raw = raw.decode("utf-8", errors="replace")
                    # JSON → our own echo from the Channels broadcast group; ignore
                    try:
                        json.loads(raw)
                        log.debug("[live_session] remote: JSON received (own echo), ignored")
                        continue
                    except (json.JSONDecodeError, ValueError):
                        pass
                    # Plain-text command
                    cmd = raw.strip()
                    log.debug("[live_session] remote command: %r", cmd)
                    asyncio.create_task(_handle_remote_cmd(cmd))
            except websockets.ConnectionClosed:
                log.info("[live_session] remote WS closed (remote reader)")
                resolve("remote_closed")
            except Exception as exc:
                log.exception("[live_session] _remote_reader: %s", exc)
                resolve("error")

        # ── Task 4: periodic stats log ────────────────────────────────────────
        async def _stats_logger() -> None:
            while not done.done():
                await asyncio.sleep(_STATS_INTERVAL)
                if done.done():
                    break
                elapsed = time.monotonic() - self._stats_reset_ts
                log.info("[live_session] forwarded %d telemetry frames in last %.0fs",
                         self._frames_forwarded, elapsed)
                self._frames_forwarded = 0
                self._stats_reset_ts   = time.monotonic()

        t_local  = asyncio.create_task(_local_reader())
        t_sender = asyncio.create_task(_telemetry_sender())
        t_remote = asyncio.create_task(_remote_reader())
        t_stats  = asyncio.create_task(_stats_logger())

        reason = await done

        for t in (t_local, t_sender, t_remote, t_stats):
            t.cancel()
        await asyncio.gather(t_local, t_sender, t_remote, t_stats, return_exceptions=True)
        return reason

    # ── Outer reconnect loop ───────────────────────────────────────────────────

    async def run(self) -> None:
        """
        Outer reconnect loop.

        Local WS   — retry every 2 s (no backoff)
        Remote WS  — exponential backoff 3 s → 30 s; reset after 60 s uptime
        5-min mark — log warning if remote has been unreachable continuously,
                     but keep retrying indefinitely (server may come up later).
        """
        remote_backoff   = _REMOTE_BACKOFF_MIN
        remote_fail_since: Optional[float] = None   # monotonic ts of first failure

        while True:
            self._set_status("connecting")

            # ── 1. Connect to local WS (retry until core is up) ───────────────
            local_ws: Any = None
            while local_ws is None:
                try:
                    local_ws = await websockets.connect(_LOCAL_WS_URL)
                    log.info("[live_session] connected to local WS %s", _LOCAL_WS_URL)
                except Exception as exc:
                    log.warning("[live_session] local WS unavailable (%s) — "
                                "retry in %.0fs", exc, _LOCAL_RETRY_INTERVAL)
                    await asyncio.sleep(_LOCAL_RETRY_INTERVAL)

            # ── 2. Connect to remote WS ───────────────────────────────────────
            remote_ws: Any = None
            try:
                remote_ws = await websockets.connect(self._remote_url)
                log.info("[live_session] connected to remote WS %s", self._remote_url)
                remote_fail_since = None
                remote_backoff    = _REMOTE_BACKOFF_MIN
            except Exception as exc:
                now = time.monotonic()
                if remote_fail_since is None:
                    remote_fail_since = now
                elif now - remote_fail_since >= _REMOTE_WARN_AFTER:
                    log.warning(
                        "[live_session] remote WS unreachable for %.0f minutes — still retrying",
                        (now - remote_fail_since) / 60.0,
                    )
                log.warning("[live_session] remote WS failed (%s) — retry in %.0fs",
                            exc, remote_backoff)
                try:
                    await local_ws.close()
                except Exception:
                    pass
                await asyncio.sleep(remote_backoff)
                remote_backoff = min(remote_backoff * 2, _REMOTE_BACKOFF_MAX)
                continue

            # ── 3. Inner session ──────────────────────────────────────────────
            self._set_status("connected_idle")
            session_start = time.monotonic()
            try:
                reason = await self._run_inner(local_ws, remote_ws)
            except Exception as exc:
                log.exception("[live_session] inner session crashed: %s", exc)
                reason = "error"
            finally:
                for ws in (local_ws, remote_ws):
                    try:
                        await ws.close()
                    except Exception:
                        pass

            session_duration = time.monotonic() - session_start
            log.info("[live_session] session ended: reason=%s duration=%.0fs",
                     reason, session_duration)
            self._set_status("disconnected")

            # Long session → reset backoff
            if session_duration >= _REMOTE_RESET_AFTER:
                remote_backoff    = _REMOTE_BACKOFF_MIN
                remote_fail_since = None

            if reason == "local_closed":
                # Core went away; retry local quickly, then remote fresh
                log.info("[live_session] local closed — reconnecting in %.0fs",
                         _LOCAL_RETRY_INTERVAL)
                await asyncio.sleep(_LOCAL_RETRY_INTERVAL)
            else:
                # Remote closed or session error — back off before retrying remote
                now = time.monotonic()
                if remote_fail_since is None:
                    remote_fail_since = now
                elif now - remote_fail_since >= _REMOTE_WARN_AFTER:
                    log.warning(
                        "[live_session] remote WS has been failing for %.0f minutes — "
                        "still retrying", (now - remote_fail_since) / 60.0,
                    )
                log.info("[live_session] remote retry in %.0fs", remote_backoff)
                await asyncio.sleep(remote_backoff)
                remote_backoff = min(remote_backoff * 2, _REMOTE_BACKOFF_MAX)


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="VEYA Live Session Relay")
    parser.add_argument(
        "--url", default="",
        help="Remote WebSocket URL (overrides server_config.json live_session_url)",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Enable DEBUG logging",
    )
    args = parser.parse_args()

    _setup_logging(args.verbose)

    url = args.url.strip()
    if not url:
        url = _load_url_from_config()

    if not url:
        log.error(
            "[live_session] no URL configured — set 'live_session_url' in "
            "~/.veya/server_config.json or pass --url",
        )
        sys.exit(1)

    if not (url.startswith("ws://") or url.startswith("wss://")):
        log.error("[live_session] invalid URL (must start with ws:// or wss://): %r", url)
        sys.exit(1)

    log.info("[live_session] starting — remote URL: %s", url)
    _write_status("disconnected")

    session = LiveSession(url)
    try:
        asyncio.run(session.run())
    except KeyboardInterrupt:
        log.info("[live_session] interrupted by user")
        _write_status("disconnected")
        sys.exit(0)


# Support both `python -m services.veya_core.live_session` and direct execution
if __package__ in (None, ""):
    _pkg_root = pathlib.Path(__file__).resolve().parent.parent.parent
    if str(_pkg_root) not in sys.path:
        sys.path.insert(0, str(_pkg_root))

if __name__ == "__main__":
    main()
