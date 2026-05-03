"""
VEYA — ELM327 Telemetry Source                       elm327_source.py
=====================================================================

Standalone TCP-client script that bridges a real ELM327 USB OBD-II
adapter into the VEYA core wire contract. Queries 8 PIDs (RPM, SPEED,
COOLANT_TEMP, THROTTLE_POS, ENGINE_LOAD, CONTROL_MODULE_VOLTAGE,
FUEL_LEVEL, INTAKE_TEMP) and packages them as telemetry frames.

Requires `python-obd`. If the library is not installed, exits with
code 2 and a clean error message.

Usage:
    python -m services.veya_core.sources.elm327_source \\
        --host 127.0.0.1 --port 9000 \\
        --device /dev/ttyUSB0 --baud 38400

This script is NOT spawned automatically by core.py. For Phase 2.0
real mode just listens on the TCP port and waits for a source to
connect — run this script manually (or wait for the ESP32 firmware).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import signal
import sys
import time
from typing import Any, Dict, Optional

if __package__ in (None, ""):
    _ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    if _ROOT not in sys.path:
        sys.path.insert(0, _ROOT)

from services.veya_core import contract


log = logging.getLogger("elm327_source")


# ── Mode → telemetry rate ──────────────────────────────────────────────────

def _rate_for_mode(mode: str, base_hz: float) -> float:
    if mode == contract.MODE_DIAGNOSTIC:
        return 1.0
    return base_hz


# ── ELM327 helper, runs blocking python-obd calls in the executor ───────────

class _Adapter:
    def __init__(self, device: str, baud: int) -> None:
        try:
            import obd as _obd
        except ImportError:
            print(
                "ERROR: python-obd is not installed.\n"
                "       Run:  source .venv/bin/activate && pip install obd\n"
                "       Then re-run elm327_source.py.",
                file=sys.stderr,
            )
            sys.exit(2)

        self._obd = _obd
        self.device = device
        self.baud = baud
        self._conn: Optional[Any] = None
        self._last_fuel = 80.0

    async def connect(self) -> None:
        loop = asyncio.get_running_loop()
        self._conn = await loop.run_in_executor(
            None,
            lambda: self._obd.OBD(
                portstr=self.device, baudrate=self.baud, timeout=10, fast=True
            ),
        )
        if not self._conn.is_connected():
            raise RuntimeError(
                f"ELM327 on {self.device} — vehicle not responding "
                "(key must be ON or engine running)."
            )
        cmds = [
            self._obd.commands.RPM, self._obd.commands.SPEED,
            self._obd.commands.COOLANT_TEMP, self._obd.commands.THROTTLE_POS,
            self._obd.commands.ENGINE_LOAD,
            self._obd.commands.CONTROL_MODULE_VOLTAGE,
            self._obd.commands.FUEL_LEVEL, self._obd.commands.INTAKE_TEMP,
        ]
        supported = [c.name for c in cmds if self._conn.supports(c)]
        log.info("[elm] connected ✓  supported PIDs: %s", ", ".join(supported))

    async def sample(self) -> Dict[str, Any]:
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, self._sample_sync)

    def _sample_sync(self) -> Dict[str, Any]:
        obd = self._obd
        conn = self._conn

        def q(cmd):
            try:
                r = conn.query(cmd)
                if not r.is_null():
                    return float(r.value.magnitude)
            except Exception:
                pass
            return None

        rpm     = q(obd.commands.RPM)                    or 0.0
        speed   = q(obd.commands.SPEED)                  or 0.0
        coolant = q(obd.commands.COOLANT_TEMP)           or 0.0
        thr     = q(obd.commands.THROTTLE_POS)           or 0.0
        load    = q(obd.commands.ENGINE_LOAD)            or 0.0
        batt    = q(obd.commands.CONTROL_MODULE_VOLTAGE) or 12.4
        fuel    = q(obd.commands.FUEL_LEVEL)
        if fuel is None:
            fuel = self._last_fuel
        else:
            self._last_fuel = fuel
        intake = q(obd.commands.INTAKE_TEMP) or 25.0

        return {
            "rpm":           int(rpm),
            "speed_kph":     round(speed, 1),
            "coolant_c":     round(coolant, 1),
            "throttle_pct":  round(thr, 1),
            "engine_load":   round(load, 1),
            "battery_v":     round(batt, 2),
            "fuel_level":    round(fuel, 1),
            "intake_temp_c": round(intake, 1),
        }

    async def query_dtcs(self) -> list[Dict[str, str]]:
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, self._query_dtcs_sync)

    def _query_dtcs_sync(self) -> list[Dict[str, str]]:
        obd = self._obd
        try:
            r = self._conn.query(obd.commands.GET_DTC)
            if r.is_null() or not r.value:
                return []
            out = []
            for entry in r.value:
                # python-obd returns (code, description) tuples
                code = entry[0] if isinstance(entry, tuple) else str(entry)
                out.append({"code": str(code), "status": "active"})
            return out
        except Exception as exc:
            log.warning("[elm] query_dtcs failed: %s", exc)
            return []

    async def close(self) -> None:
        if self._conn is None:
            return
        loop = asyncio.get_running_loop()
        await loop.run_in_executor(None, self._conn.close)
        self._conn = None


# ── TCP client ──────────────────────────────────────────────────────────────

class Elm327SourceClient:

    def __init__(
        self,
        host: str,
        port: int,
        base_hz: float,
        device: str,
        baud: int,
    ) -> None:
        self.host = host
        self.port = port
        self.base_hz = base_hz
        self.mode = contract.MODE_DRIVE
        self._adapter = _Adapter(device, baud)
        self._stop = asyncio.Event()
        self._writer: Optional[asyncio.StreamWriter] = None

    def request_stop(self) -> None:
        self._stop.set()

    async def run(self) -> None:
        log.info("[elm] connecting ELM327 …")
        try:
            await self._adapter.connect()
        except RuntimeError as exc:
            log.error("[elm] %s", exc)
            return

        log.info("[elm] connecting to core %s:%d", self.host, self.port)
        try:
            reader, writer = await asyncio.open_connection(self.host, self.port)
        except (ConnectionRefusedError, OSError) as exc:
            log.error("[elm] cannot connect: %s", exc)
            await self._adapter.close()
            return

        self._writer = writer
        try:
            await self._send(contract.build_hello("elm327-001", "veya-elm327"))
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
            await self._adapter.close()
            log.info("[elm] disconnected")

    async def _tx_loop(self) -> None:
        next_tick = time.monotonic()
        while not self._stop.is_set():
            try:
                sample = await self._adapter.sample()
            except Exception as exc:
                log.warning("[elm] sample failed: %s", exc)
                self._stop.set()
                return
            frame = contract.build_telemetry(ts=time.time(), **sample)
            try:
                await self._send(frame)
            except (ConnectionError, OSError) as exc:
                log.warning("[elm] send failed: %s", exc)
                self._stop.set()
                return

            next_tick += 1.0 / max(0.5, _rate_for_mode(self.mode, self.base_hz))
            sleep_s = next_tick - time.monotonic()
            if sleep_s > 0:
                await asyncio.sleep(sleep_s)
            else:
                next_tick = time.monotonic()

    async def _rx_loop(self, reader: asyncio.StreamReader) -> None:
        while not self._stop.is_set():
            line = await reader.readline()
            if not line:
                log.info("[elm] core closed connection")
                self._stop.set()
                return
            try:
                cmd = json.loads(line)
            except json.JSONDecodeError as exc:
                log.warning("[elm] bad JSON from core: %s", exc)
                continue

            ftype = cmd.get("type")
            if ftype == contract.FRAME_SET_MODE:
                new_mode = cmd.get("mode")
                if new_mode in contract.VALID_MODES:
                    if new_mode != self.mode:
                        log.info("[elm] mode: %s → %s", self.mode, new_mode)
                    self.mode = new_mode
                else:
                    log.warning("[elm] unknown mode: %r — ignoring", new_mode)

            elif ftype == contract.FRAME_QUERY_DTC:
                codes = await self._adapter.query_dtcs()
                log.info("[elm] query_dtc → %d code(s)", len(codes))
                await self._send(contract.build_dtc(codes))

            else:
                log.debug("[elm] ignoring command type=%r", ftype)

    async def _send(self, frame: Dict[str, Any]) -> None:
        if self._writer is None:
            raise ConnectionError("not connected")
        payload = (json.dumps(frame, separators=(",", ":")) + "\n").encode("utf-8")
        self._writer.write(payload)
        await self._writer.drain()


# ── Entry point ─────────────────────────────────────────────────────────────

def _build_argparser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="elm327_source",
        description="Standalone ELM327 telemetry source for the VEYA core service.")
    ap.add_argument("--host",    default="127.0.0.1",
                    help="VEYA core host (default: 127.0.0.1)")
    ap.add_argument("--port",    type=int, default=contract.DEFAULT_TCP_PORT,
                    help=f"VEYA core TCP port (default: {contract.DEFAULT_TCP_PORT})")
    ap.add_argument("--rate-hz", type=float, default=4.0,
                    help="Base telemetry rate in Hz (default: 4 — ELM327 typical)")
    ap.add_argument("--device",  default="/dev/ttyUSB0",
                    help="ELM327 serial device (default: /dev/ttyUSB0)")
    ap.add_argument("--baud",    type=int, default=38400,
                    help="ELM327 baud rate (default: 38400; try 9600 for clones)")
    return ap


async def _amain() -> None:
    args = _build_argparser().parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-7s %(name)s %(message)s",
    )
    client = Elm327SourceClient(
        args.host, args.port, args.rate_hz, args.device, args.baud,
    )

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
