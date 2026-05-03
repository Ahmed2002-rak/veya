"""
VEYA — Core Service                                            core.py
=====================================================================

Top-level orchestrator. Owns:
  • the TCP listener that accepts ONE data source (mock subprocess,
    ELM327 bridge, ESP32-via-Bluetooth bridge),
  • the WebSocket server that broadcasts telemetry to the QML UI,
  • the live mode state machine (mock | real-waiting | real-connected),
  • the auto-spawn of mock_source.py when running in mock mode.

The wire formats live in two distinct modules:
  • contract.py      — source-facing protocol (TCP, port 9000)
  • ws_server.py     — UI-facing legacy schema (WebSocket, port 8765)

Run:
    python -m services.veya_core.core --mode mock
    python -m services.veya_core.core --mode real
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
import signal
import sys
import time
from typing import Any, Dict, Optional

from . import contract
from .tcp_server import TcpSourceServer
from .ws_server  import UiWebSocketServer, UI_BROADCAST_HARD_HZ


log = logging.getLogger("veya_core")


# ── Internal mode constants ──────────────────────────────────────────────────

INTERNAL_MODE_MOCK = "mock"
INTERNAL_MODE_REAL = "real"

STATE_MOCK           = "mock"            # mock subprocess running
STATE_REAL_WAITING   = "real-waiting"    # real mode, no source yet
STATE_REAL_CONNECTED = "real-connected"  # real mode, source present


# ── Legacy UI status values (compat with VehicleDataProvider.qml) ───────────
#
# The UI's TEST/REAL toggle reads `dataMode === "elm"`. To preserve the
# Phase-1 UX without any QML change, we keep the wire-format `status`
# field at its legacy values: "mock" or "elm". Internally we still
# track current_mode as "mock" or "real".
def _legacy_status(internal_mode: str) -> str:
    return "elm" if internal_mode == INTERNAL_MODE_REAL else "mock"


# ── Warning thresholds (preserved from legacy obd_service.py) ───────────────

WARN_COOLANT_HIGH_C = 105.0
WARN_OVERSPEED_KPH  = 150.0
WARN_LOW_FUEL_PCT   = 15.0
WARN_LOW_BATT_V     = 11.8


# ── Defaults for missing telemetry fields (legacy MockProvider seed) ────────
#
# When a source omits a telemetry field AND we have no cached value yet,
# we fall back to these so the UI never has to render `null`.

_DEFAULT_TELEMETRY: Dict[str, float] = {
    "rpm":           0,
    "speed_kph":     0.0,
    "coolant_c":     0.0,
    "throttle_pct":  0.0,
    "engine_load":   0.0,
    "battery_v":     12.4,
    "fuel_level":    80.0,
    "intake_temp_c": 25.0,
}


# ── How long to wait for a source after switching to real mode ──────────────

REAL_WAITING_TIMEOUT_S = 3.0


# ─────────────────────────────────────────────────────────────────────────────
# Core service
# ─────────────────────────────────────────────────────────────────────────────

class VeyaCore:

    def __init__(
        self,
        listen_host: str,
        tcp_port:    int,
        ws_port:     int,
        initial_mode: str,
        broadcast_hz: float,
    ) -> None:
        if initial_mode not in (INTERNAL_MODE_MOCK, INTERNAL_MODE_REAL):
            raise ValueError(f"initial_mode must be mock|real, got {initial_mode!r}")

        self.listen_host  = listen_host
        self.tcp_port     = tcp_port
        self.ws_port      = ws_port
        self.broadcast_hz = min(broadcast_hz, UI_BROADCAST_HARD_HZ)

        self.current_mode: str = initial_mode      # "mock" | "real"
        self.state:        str = STATE_MOCK if initial_mode == INTERNAL_MODE_MOCK \
                                            else STATE_REAL_WAITING

        self._tcp = TcpSourceServer(listen_host, tcp_port, self._on_source_frame)
        self._ws  = UiWebSocketServer("127.0.0.1", ws_port, self._on_ui_command)

        self._mock_proc: Optional[asyncio.subprocess.Process] = None
        self._real_wait_task: Optional[asyncio.Task[None]] = None

        # Cached last-known telemetry (per field) so missing fields forward
        # the previous value to the UI rather than dropping to defaults.
        self._cache: Dict[str, Any] = dict(_DEFAULT_TELEMETRY)

        self._stop_event = asyncio.Event()

    # ── Lifecycle ────────────────────────────────────────────────────────────

    async def run(self) -> None:
        await self._tcp.start()
        await self._ws.start()

        if self.current_mode == INTERNAL_MODE_MOCK:
            await self._spawn_mock_source()
        else:
            self._schedule_real_wait_timeout()

        log.info("[core] started: mode=%s tcp=%s:%d ws=%s:%d hz=%.1f",
                 self.current_mode, self.listen_host, self.tcp_port,
                 "127.0.0.1", self.ws_port, self.broadcast_hz)

        try:
            await self._stop_event.wait()
        finally:
            await self._shutdown()

    def request_stop(self) -> None:
        self._stop_event.set()

    async def _shutdown(self) -> None:
        log.info("[core] shutting down …")
        if self._real_wait_task is not None:
            self._real_wait_task.cancel()
        await self._kill_mock_source()
        await self._tcp.stop()
        await self._ws.stop()
        log.info("[core] stopped")

    # ── Mock subprocess management ───────────────────────────────────────────

    async def _spawn_mock_source(self) -> None:
        if self._mock_proc is not None and self._mock_proc.returncode is None:
            log.info("[core] mock source already running (pid=%d)", self._mock_proc.pid)
            return
        cmd = [
            sys.executable,
            "-m", "services.veya_core.sources.mock_source",
            "--host", "127.0.0.1",
            "--port", str(self.tcp_port),
            "--rate-hz", str(self.broadcast_hz),
        ]
        log.info("[core] spawning mock source: %s", " ".join(cmd))
        self._mock_proc = await asyncio.create_subprocess_exec(
            *cmd,
            cwd=_project_root(),
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        log.info("[core] mock source pid=%d", self._mock_proc.pid)

    async def _kill_mock_source(self) -> None:
        proc = self._mock_proc
        if proc is None:
            return
        if proc.returncode is None:
            log.info("[core] terminating mock source pid=%d", proc.pid)
            try:
                proc.terminate()
                try:
                    await asyncio.wait_for(proc.wait(), timeout=2.0)
                except asyncio.TimeoutError:
                    log.warning("[core] mock source did not exit; killing")
                    proc.kill()
                    await proc.wait()
            except ProcessLookupError:
                pass
        self._mock_proc = None

    # ── Source frame handling (TCP → translate → UI) ─────────────────────────

    async def _on_source_frame(self, frame: Dict[str, Any]) -> None:
        ftype = frame.get("type")

        if ftype == contract.FRAME_HELLO:
            log.info("[core] source ready: id=%s kind=%s",
                     frame.get("source_id"), frame.get("source_kind"))
            if self.current_mode == INTERNAL_MODE_REAL:
                self.state = STATE_REAL_CONNECTED
                if self._real_wait_task is not None:
                    self._real_wait_task.cancel()
                    self._real_wait_task = None
            return

        if ftype == contract.FRAME_TELEMETRY:
            ui_frame = self._translate_telemetry(frame)
            await self._ws.broadcast(ui_frame)
            return

        if ftype == contract.FRAME_DTC:
            # DTCs aren't part of the legacy UI schema yet; log so the
            # Diagnostic page work in Phase 2.2 can wire it up.
            log.info("[core] DTC frame: %s", frame.get("codes"))
            return

        if ftype == contract.FRAME_PID_RESPONSE:
            log.info("[core] pid_response: pid=%s value=%s",
                     frame.get("pid"), frame.get("value"))
            return

        log.debug("[core] unhandled source frame type: %s", ftype)

    def _translate_telemetry(self, frame: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert a contract.FRAME_TELEMETRY into the UI-facing legacy frame.
        Missing fields fall back to the cache (last-known value or default).
        """
        for name in contract.TELEMETRY_FIELD_NAMES:
            if name in frame:
                self._cache[name] = frame[name]

        rpm   = int(self._cache["rpm"] or 0)
        speed = float(self._cache["speed_kph"])
        cool  = float(self._cache["coolant_c"])
        thr   = float(self._cache["throttle_pct"])
        load  = float(self._cache["engine_load"])
        batt  = float(self._cache["battery_v"])
        fuel  = float(self._cache["fuel_level"])
        intk  = float(self._cache["intake_temp_c"])

        return {
            "schema":        contract.SCHEMA_VERSION,
            "ts":            float(frame.get("ts", time.time())),
            "status":        _legacy_status(self.current_mode),
            "rpm":           rpm,
            "speed_kph":     round(speed, 1),
            "coolant_c":     round(cool,  1),
            "throttle_pct":  round(thr,   1),
            "engine_load":   round(load,  1),
            "battery_v":     round(batt,  2),
            "fuel_level":    round(fuel,  1),
            "intake_temp_c": round(intk,  1),
            "warnings": {
                "coolant_high": cool  > WARN_COOLANT_HIGH_C,
                "overspeed":    speed > WARN_OVERSPEED_KPH,
                "low_fuel":     fuel  < WARN_LOW_FUEL_PCT,
                "low_battery":  batt  < WARN_LOW_BATT_V,
            },
        }

    # ── UI command handling (UI → core) ──────────────────────────────────────

    async def _on_ui_command(self, cmd: Dict[str, Any]) -> None:
        if cmd.get("cmd") != "set_mode":
            log.warning("[core] unknown UI command: %s", cmd)
            return

        ui_mode = cmd.get("mode")
        # UI uses legacy "mock"|"elm"; map elm → real internally.
        target = INTERNAL_MODE_REAL if ui_mode == "elm" else INTERNAL_MODE_MOCK
        if target == self.current_mode:
            log.info("[core] already in %s mode", target)
            return

        log.info("[core] mode switch: %s → %s", self.current_mode, target)
        self.current_mode = target

        if target == INTERNAL_MODE_REAL:
            await self._kill_mock_source()
            self.state = STATE_REAL_CONNECTED if self._tcp.connected \
                                              else STATE_REAL_WAITING
            # Tell whatever source is connected (rare in practice, but
            # supported by the contract) to enter drive mode.
            if self._tcp.connected:
                await self._tcp.send_to_source(
                    contract.build_set_mode(contract.MODE_DRIVE)
                )
            # Immediate UI confirmation so the Home toggle clears its
            # "switching…" spinner before we wait for telemetry.
            await self._broadcast_status_only()
            self._schedule_real_wait_timeout()
            return

        # target == INTERNAL_MODE_MOCK
        if self._real_wait_task is not None:
            self._real_wait_task.cancel()
            self._real_wait_task = None
        self.state = STATE_MOCK
        await self._spawn_mock_source()

    # ── Real-mode "no source" timeout ────────────────────────────────────────

    def _schedule_real_wait_timeout(self) -> None:
        if self._real_wait_task is not None:
            self._real_wait_task.cancel()
        self._real_wait_task = asyncio.create_task(self._real_wait_timeout())

    async def _real_wait_timeout(self) -> None:
        try:
            await asyncio.sleep(REAL_WAITING_TIMEOUT_S)
        except asyncio.CancelledError:
            return
        if self.current_mode == INTERNAL_MODE_REAL and not self._tcp.connected:
            log.info("[core] no source after %.1fs — emitting mode_error",
                     REAL_WAITING_TIMEOUT_S)
            await self._broadcast_status_only(
                mode_error="Waiting for external source..."
            )

    # ── Helpers ──────────────────────────────────────────────────────────────

    async def _broadcast_status_only(
        self,
        mode_error: Optional[str] = None,
    ) -> None:
        """
        Emit a UI frame using cached telemetry, refreshing only the status
        field (and optional mode_error). Bypasses the 20 Hz throttle by
        resetting the gate so the toggle UX feels instant.
        """
        # Build from current cache
        fake = {"ts": time.time()}
        # _translate_telemetry uses self._cache for everything else
        ui_frame = self._translate_telemetry(fake)
        if mode_error is not None:
            ui_frame["mode_error"] = mode_error
        # Force-emit even if a recent broadcast happened.
        self._ws._last_broadcast_ts = 0.0
        await self._ws.broadcast(ui_frame)


# ── Helpers ─────────────────────────────────────────────────────────────────

def _project_root() -> str:
    """Resolve to /home/pfe/veya (two levels up from this file)."""
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", ".."))


# ── Entry point ─────────────────────────────────────────────────────────────

def _build_argparser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="veya_core",
        description="VEYA core service: TCP source listener + WebSocket UI broadcaster")
    ap.add_argument("--listen", default="127.0.0.1",
                    help="TCP listen interface (default: 127.0.0.1; use 0.0.0.0 for LAN)")
    ap.add_argument("--tcp-port", type=int, default=contract.DEFAULT_TCP_PORT,
                    help=f"TCP port for source (default: {contract.DEFAULT_TCP_PORT})")
    ap.add_argument("--ws-port",  type=int, default=contract.DEFAULT_WS_PORT,
                    help=f"WebSocket port for UI (default: {contract.DEFAULT_WS_PORT})")
    ap.add_argument("--mode",     choices=[INTERNAL_MODE_MOCK, INTERNAL_MODE_REAL],
                    default=INTERNAL_MODE_MOCK,
                    help="Initial mode (default: mock — auto-spawns mock_source.py)")
    ap.add_argument("--hz",       type=float, default=10.0,
                    help=f"UI broadcast rate cap in Hz (default: 10; "
                         f"hard ceiling {UI_BROADCAST_HARD_HZ:.0f})")
    return ap


async def _amain() -> None:
    args = _build_argparser().parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-7s %(name)s %(message)s",
    )

    core = VeyaCore(
        listen_host  = args.listen,
        tcp_port     = args.tcp_port,
        ws_port      = args.ws_port,
        initial_mode = args.mode,
        broadcast_hz = args.hz,
    )

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, core.request_stop)
        except NotImplementedError:
            # Windows fallback (not actually used on Pi 5)
            pass

    await core.run()


def main() -> None:
    try:
        asyncio.run(_amain())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
