"""
VEYA — Mock Telemetry Source                          mock_source.py
=====================================================================

Standalone TCP-client script that pretends to be a vehicle. Sends
telemetry frames to the VEYA core service over the wire contract
defined in services/veya_core/contract.py.

Drive-cycle simulation, coolant warm-up, fuel drain, battery sag and
intake heat-soak are preserved bit-for-bit from the legacy
obd_service.py MockProvider.

Usage:
    python -m services.veya_core.sources.mock_source --host 127.0.0.1 --port 9000
    python services/veya_core/sources/mock_source.py --port 9000 --rate-hz 10

Responds to set_mode commands from the core:
    drive       → 10 Hz   (default)
    live_scan   → 10 Hz
    diagnostic  →  1 Hz
    idle        → 10 Hz   (low-rate idle could be added later)

Returns a fixed mock DTC list on query_dtc:
    [{"code": "P0300", "status": "active"},
     {"code": "P0420", "status": "pending"}]
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import random
import signal
import sys
import time
from typing import Any, Dict, Optional

# Allow `python services/.../mock_source.py …` (script form) by adding
# the project root to sys.path. The `python -m …` form imports normally.
if __package__ in (None, ""):
    _ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    if _ROOT not in sys.path:
        sys.path.insert(0, _ROOT)

from services.veya_core import contract


log = logging.getLogger("mock_source")


# ── Drive-cycle state machine (copied verbatim from legacy MockProvider) ────

class _DriveCycle:
    """Generates plausible (speed_kph, rpm, throttle_pct) tuples."""

    STATES = [
        # (name,           dur_s, tgt_spd, tgt_rpm, thr_pct)
        ("idle",              5,    0,     820,   2),
        ("city_accel",        9,   60,    3100,  68),
        ("city_cruise",      12,   60,    2400,  28),
        ("city_decel",        6,   15,    1100,   5),
        ("idle2",             4,    0,     820,   2),
        ("highway_accel",    14,  120,    3800,  72),
        ("highway_cruise",   22,  120,    2700,  32),
        ("highway_decel",    10,    0,     880,   5),
    ]

    def __init__(self) -> None:
        self._idx = 0
        self._t0  = time.monotonic()
        self._spd = 0.0
        self._rpm = 820.0

    @staticmethod
    def _ease(t: float) -> float:
        t = max(0.0, min(1.0, t))
        return t * t * (3.0 - 2.0 * t)

    def tick(self):
        now = time.monotonic()
        _, dur, tgt_spd, tgt_rpm, thr = self.STATES[self._idx]
        prog = self._ease(min((now - self._t0) / dur, 1.0))

        spd = self._spd + (tgt_spd - self._spd) * prog + random.gauss(0, 0.3)
        rpm = self._rpm + (tgt_rpm - self._rpm) * prog + random.gauss(0, 22)
        spd = max(0.0, spd)
        rpm = max(650.0, rpm)

        if (now - self._t0) >= dur:
            self._spd, self._rpm = spd, rpm
            self._idx = (self._idx + 1) % len(self.STATES)
            self._t0  = now

        return spd, rpm, float(thr)


# ── Realistic telemetry generator ──────────────────────────────────────────

class _Sim:
    """Wraps the drive cycle with coolant/fuel/battery/intake models."""

    WARMUP_S       = 90.0
    FUEL_DRAIN_PCT = 0.0028   # % per second

    def __init__(self) -> None:
        self._cycle   = _DriveCycle()
        self._t0      = time.monotonic()
        self._coolant = 22.0
        self._fuel    = 78.0
        self._intake  = 26.0

    def sample(self) -> Dict[str, Any]:
        spd, rpm, thr = self._cycle.tick()
        up = time.monotonic() - self._t0

        wp = min(up / self.WARMUP_S, 1.0)
        target = 22.0 + (92.0 - 22.0) * wp * wp * (3.0 - 2.0 * wp)
        self._coolant += (target - self._coolant) * 0.04 + random.gauss(0, 0.1)

        self._fuel = max(0.0, self._fuel - self.FUEL_DRAIN_PCT)

        load = min(100.0, thr * 0.65 + (rpm / 8000.0) * 35.0 + random.gauss(0, 1.5))
        batt = 12.4 + (1.85 if rpm > 900 else 0.0) + random.gauss(0, 0.04)
        self._intake = 26.0 + min(up / 300.0, 1.0) * 8.0 + random.gauss(0, 0.5)

        return {
            "rpm":           int(rpm),
            "speed_kph":     round(spd, 1),
            "coolant_c":     round(self._coolant, 1),
            "throttle_pct":  round(thr, 1),
            "engine_load":   round(load, 1),
            "battery_v":     round(batt, 2),
            "fuel_level":    round(self._fuel, 1),
            "intake_temp_c": round(self._intake, 1),
        }


# ── Fixed mock DTC payload ─────────────────────────────────────────────────

MOCK_DTC_CODES = [
    {"code": "P0300", "status": "active"},
    {"code": "P0420", "status": "pending"},
]


# ── Mode → telemetry rate ──────────────────────────────────────────────────

def _rate_for_mode(mode: str, base_hz: float) -> float:
    if mode == contract.MODE_DIAGNOSTIC:
        return 1.0
    return base_hz   # drive, live_scan, idle


# ── TCP client ──────────────────────────────────────────────────────────────

class MockSourceClient:

    def __init__(self, host: str, port: int, base_hz: float) -> None:
        self.host = host
        self.port = port
        self.base_hz = base_hz
        self.mode = contract.MODE_DRIVE
        self._sim = _Sim()
        self._stop = asyncio.Event()
        self._writer: Optional[asyncio.StreamWriter] = None

    def request_stop(self) -> None:
        self._stop.set()

    # ── Lifecycle ────────────────────────────────────────────────────────────

    async def run(self) -> None:
        log.info("[mock] connecting to %s:%d (base_hz=%.1f)",
                 self.host, self.port, self.base_hz)
        try:
            reader, writer = await asyncio.open_connection(self.host, self.port)
        except (ConnectionRefusedError, OSError) as exc:
            log.error("[mock] cannot connect: %s", exc)
            return

        self._writer = writer
        try:
            await self._send(contract.build_hello("mock-001", "veya-mock"))
            tx = asyncio.create_task(self._tx_loop())
            rx = asyncio.create_task(self._rx_loop(reader))
            stopper = asyncio.create_task(self._stop.wait())
            done, pending = await asyncio.wait(
                {tx, rx, stopper}, return_when=asyncio.FIRST_COMPLETED
            )
            for t in pending:
                t.cancel()
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass
            self._writer = None
            log.info("[mock] disconnected")

    # ── TX: telemetry stream ─────────────────────────────────────────────────

    async def _tx_loop(self) -> None:
        next_tick = time.monotonic()
        while not self._stop.is_set():
            sample = self._sim.sample()
            frame = contract.build_telemetry(ts=time.time(), **sample)
            try:
                await self._send(frame)
            except (ConnectionError, OSError) as exc:
                log.warning("[mock] send failed: %s", exc)
                self._stop.set()
                return

            next_tick += 1.0 / max(0.5, _rate_for_mode(self.mode, self.base_hz))
            sleep_s = next_tick - time.monotonic()
            if sleep_s > 0:
                await asyncio.sleep(sleep_s)
            else:
                next_tick = time.monotonic()

    # ── RX: command stream ───────────────────────────────────────────────────

    async def _rx_loop(self, reader: asyncio.StreamReader) -> None:
        while not self._stop.is_set():
            line = await reader.readline()
            if not line:
                log.info("[mock] core closed connection")
                self._stop.set()
                return
            try:
                cmd = json.loads(line)
            except json.JSONDecodeError as exc:
                log.warning("[mock] bad JSON from core: %s", exc)
                continue

            ftype = cmd.get("type")
            if ftype == contract.FRAME_SET_MODE:
                new_mode = cmd.get("mode")
                if new_mode in contract.VALID_MODES:
                    if new_mode != self.mode:
                        log.info("[mock] mode: %s → %s", self.mode, new_mode)
                    self.mode = new_mode
                else:
                    log.warning("[mock] unknown mode: %r — ignoring", new_mode)

            elif ftype == contract.FRAME_QUERY_DTC:
                log.info("[mock] query_dtc → returning %d code(s)",
                         len(MOCK_DTC_CODES))
                await self._send(contract.build_dtc(MOCK_DTC_CODES))

            else:
                # Forward-compat: silently ignore unknown commands
                log.debug("[mock] ignoring command type=%r", ftype)

    # ── Wire helpers ─────────────────────────────────────────────────────────

    async def _send(self, frame: Dict[str, Any]) -> None:
        if self._writer is None:
            raise ConnectionError("not connected")
        payload = (json.dumps(frame, separators=(",", ":")) + "\n").encode("utf-8")
        self._writer.write(payload)
        await self._writer.drain()


# ── Entry point ─────────────────────────────────────────────────────────────

def _build_argparser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="mock_source",
        description="Standalone mock telemetry source for the VEYA core service.")
    ap.add_argument("--host",    default="127.0.0.1",
                    help="VEYA core host (default: 127.0.0.1)")
    ap.add_argument("--port",    type=int, default=contract.DEFAULT_TCP_PORT,
                    help=f"VEYA core TCP port (default: {contract.DEFAULT_TCP_PORT})")
    ap.add_argument("--rate-hz", type=float, default=10.0,
                    help="Base telemetry rate in Hz (drive/live_scan; default: 10)")
    return ap


async def _amain() -> None:
    args = _build_argparser().parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-7s %(name)s %(message)s",
    )
    client = MockSourceClient(args.host, args.port, args.rate_hz)

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, client.request_stop)
        except NotImplementedError:
            pass

    await client.run()


def main() -> None:
    try:
        asyncio.run(_amain())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
