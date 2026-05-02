#!/usr/bin/env python3
"""
VEYA – OBD WebSocket Service                          obd_service.py
====================================================================

Usage:
    python obd_service.py                   # mock mode, 10 Hz
    python obd_service.py --mode elm        # real ELM327, 4 Hz
    python obd_service.py --mode elm --elm-port /dev/ttyUSB1

WebSocket endpoint: ws://127.0.0.1:8765

Outgoing frames (JSON, every tick):
    See Telemetry.to_dict() — fields match VehicleDataProvider.qml exactly.

Incoming commands (from VehicleDataProvider.sendModeCommand()):
    {"cmd": "set_mode", "mode": "mock"}
    {"cmd": "set_mode", "mode": "elm"}
    The server hot-swaps providers without restarting.

Error frame (sent once if mode switch fails — backend reverts to mock):
    { ...normal telemetry..., "mode_error": "description" }
"""

import argparse
import asyncio
import json
import random
import signal
import time
import warnings
from dataclasses import dataclass, field
from typing import Any, Dict, Optional, Set

warnings.filterwarnings("ignore", category=DeprecationWarning, module="websockets")

import websockets

# ── Telemetry contract ────────────────────────────────────────────────────────

SCHEMA_VERSION = 1


@dataclass
class Telemetry:
    ts:           float
    status:       str         # "mock" | "elm"
    rpm:          int
    speed_kph:    float
    coolant_c:    float
    throttle_pct: float
    engine_load:  float = 0.0
    battery_v:    float = 12.4
    fuel_level:   float = 80.0
    intake_temp_c:float = 25.0
    warnings:     Dict[str, bool] = field(default_factory=dict)
    mode_error:   Optional[str]   = None    # only set when mode switch fails

    def to_dict(self) -> Dict[str, Any]:
        d: Dict[str, Any] = {
            "schema":       SCHEMA_VERSION,
            "ts":           self.ts,
            "status":       self.status,
            "rpm":          int(self.rpm),
            "speed_kph":    float(self.speed_kph),
            "coolant_c":    float(self.coolant_c),
            "throttle_pct": float(self.throttle_pct),
            "engine_load":  float(self.engine_load),
            "battery_v":    float(self.battery_v),
            "fuel_level":   float(self.fuel_level),
            "intake_temp_c":float(self.intake_temp_c),
            "warnings":     self.warnings,
        }
        if self.mode_error is not None:
            d["mode_error"] = self.mode_error
        return d


# ── Provider base class ───────────────────────────────────────────────────────

class TelemetryProvider:
    async def start(self) -> None:
        pass

    async def read(self) -> Telemetry:
        raise NotImplementedError

    async def stop(self) -> None:
        pass


# ── MockProvider — realistic drive-cycle simulation ──────────────────────────

class _DriveCycle:
    """
    Simple state machine that generates plausible speed/RPM/throttle sequences.
    idle → city_accel → city_cruise → decel → idle → highway_accel → highway_cruise → decel_hwy → …
    """
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

    def __init__(self):
        self._idx = 0
        self._t0  = time.monotonic()
        self._spd = 0.0
        self._rpm = 820.0

    @staticmethod
    def _ease(t: float) -> float:
        """Smooth-step so values don't jump linearly."""
        t = max(0.0, min(1.0, t))
        return t * t * (3.0 - 2.0 * t)

    def tick(self):
        """Returns (speed_kph, rpm, throttle_pct)."""
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


class MockProvider(TelemetryProvider):
    """
    Realistic mock telemetry:
    - Drive cycle state machine for speed/RPM/throttle
    - Engine coolant warming from cold start (22 °C → 92 °C over ~90 s)
    - Fuel slow drain
    - Battery voltage tied to RPM
    - Intake air heat soak
    """
    WARMUP_S       = 90.0
    FUEL_DRAIN_PCT = 0.0028   # % per second → empty tank in ~10 sim-hours

    def __init__(self):
        self._cycle   = _DriveCycle()
        self._t0      = None
        self._coolant = 22.0
        self._fuel    = 78.0
        self._intake  = 26.0

    async def start(self):
        self._t0 = time.monotonic()
        print("[mock] Drive-cycle simulation started")

    async def read(self) -> Telemetry:
        spd, rpm, thr = self._cycle.tick()
        up = time.monotonic() - self._t0

        # Coolant warm-up
        wp = min(up / self.WARMUP_S, 1.0)
        target = 22.0 + (92.0 - 22.0) * wp * wp * (3.0 - 2.0 * wp)
        self._coolant += (target - self._coolant) * 0.04 + random.gauss(0, 0.1)

        # Fuel drain
        self._fuel = max(0.0, self._fuel - self.FUEL_DRAIN_PCT)

        # Engine load
        load = min(100.0, thr * 0.65 + (rpm / 8000.0) * 35.0 + random.gauss(0, 1.5))

        # Battery: ~14.2 V with engine running
        batt = 12.4 + (1.85 if rpm > 900 else 0.0) + random.gauss(0, 0.04)

        # Intake air heat soak
        self._intake = 26.0 + min(up / 300.0, 1.0) * 8.0 + random.gauss(0, 0.5)

        warnings = {
            "coolant_high": self._coolant > 105.0,
            "overspeed":    spd > 150.0,
            "low_fuel":     self._fuel < 15.0,
            "low_battery":  batt < 11.8,
        }
        return Telemetry(
            ts=time.time(), status="mock",
            rpm=int(rpm),
            speed_kph=round(spd, 1),
            coolant_c=round(self._coolant, 1),
            throttle_pct=round(thr, 1),
            engine_load=round(load, 1),
            battery_v=round(batt, 2),
            fuel_level=round(self._fuel, 1),
            intake_temp_c=round(self._intake, 1),
            warnings=warnings,
        )


# ── Elm327Provider — real OBD-II via python-obd ──────────────────────────────

class Elm327Provider(TelemetryProvider):
    """
    Real vehicle data via ELM327 USB adapter + python-obd library.

    Prerequisites:
        pip install obd
        ELM327 on /dev/ttyUSB0 (or pass --elm-port)
        Vehicle key-on or engine running

    python-obd docs: https://python-obd.readthedocs.io
    """

    def __init__(self, port: str = "/dev/ttyUSB0", baud: int = 38400):
        self.port  = port
        self.baud  = baud
        self._conn = None
        self._last_fuel = 80.0   # cache — some cars respond slowly to FUEL_LEVEL

        try:
            import obd as _obd
            self._obd = _obd
        except ImportError:
            raise RuntimeError(
                "python-obd not installed.\n"
                "Run:  source .venv/bin/activate && pip install obd\n"
                "Then retry --mode elm or send the set_mode command."
            )

    async def start(self) -> None:
        print(f"[elm] Connecting to ELM327 on {self.port} @ {self.baud} baud …")
        loop = asyncio.get_running_loop()
        self._conn = await loop.run_in_executor(
            None,
            lambda: self._obd.OBD(
                portstr=self.port, baudrate=self.baud, timeout=10, fast=True
            )
        )
        if not self._conn.is_connected():
            raise RuntimeError(
                f"ELM327 on {self.port} — vehicle not responding.\n"
                "Key must be ON (or engine running)."
            )
        cmds = [
            self._obd.commands.RPM, self._obd.commands.SPEED,
            self._obd.commands.COOLANT_TEMP, self._obd.commands.THROTTLE_POS,
            self._obd.commands.ENGINE_LOAD, self._obd.commands.CONTROL_MODULE_VOLTAGE,
            self._obd.commands.FUEL_LEVEL, self._obd.commands.INTAKE_TEMP,
        ]
        supported = [c.name for c in cmds if self._conn.supports(c)]
        print(f"[elm] Connected ✓  Supported PIDs: {', '.join(supported)}")

    async def read(self) -> Telemetry:
        loop = asyncio.get_running_loop()
        return await loop.run_in_executor(None, self._query_sync)

    def _query_sync(self) -> Telemetry:
        obd = self._obd

        def q(cmd):
            try:
                r = self._conn.query(cmd)
                if not r.is_null():
                    return float(r.value.magnitude)
            except Exception:
                pass
            return None

        rpm     = q(obd.commands.RPM)                    or 0.0
        speed   = q(obd.commands.SPEED)                  or 0.0
        coolant = q(obd.commands.COOLANT_TEMP)           or 0.0
        thr     = q(obd.commands.THROTTLE_POS)           or 0.0
        load    = q(obd.commands.ENGINE_LOAD)             or 0.0
        batt    = q(obd.commands.CONTROL_MODULE_VOLTAGE)  or 12.4
        fuel    = q(obd.commands.FUEL_LEVEL)
        if fuel is None:
            fuel = self._last_fuel
        else:
            self._last_fuel = fuel
        intake = q(obd.commands.INTAKE_TEMP) or 25.0

        # DTC presence → surface as coolant_high warning
        check_engine = False
        try:
            dtc = self._conn.query(obd.commands.GET_DTC)
            if not dtc.is_null() and len(dtc.value) > 0:
                check_engine = True
        except Exception:
            pass

        warnings = {
            "coolant_high": coolant > 105.0 or check_engine,
            "overspeed":    speed   > 150.0,
            "low_fuel":     fuel    < 15.0,
            "low_battery":  batt    < 11.8,
        }
        return Telemetry(
            ts=time.time(), status="elm",
            rpm=int(rpm), speed_kph=round(speed, 1),
            coolant_c=round(coolant, 1), throttle_pct=round(thr, 1),
            engine_load=round(load, 1), battery_v=round(batt, 2),
            fuel_level=round(fuel, 1), intake_temp_c=round(intake, 1),
            warnings=warnings,
        )

    async def stop(self) -> None:
        if self._conn:
            try:
                self._conn.close()
            except Exception:
                pass
        print("[elm] Disconnected")


# ── WebSocket server ──────────────────────────────────────────────────────────

class TelemetryServer:

    def __init__(
        self,
        provider:   TelemetryProvider,
        host:       str,
        port:       int,
        hz:         float,
        elm_port:   str = "/dev/ttyUSB0",
        elm_baud:   int = 38400,
    ):
        self.provider  = provider
        self.host      = host
        self.port      = port
        self.period    = 1.0 / max(0.5, hz)
        self.elm_port  = elm_port
        self.elm_baud  = elm_baud
        self.clients:  Set[Any] = set()
        self._stop     = asyncio.Event()
        self._cmdq:    Optional[asyncio.Queue] = None

    # ── Client connection handler ─────────────────────────────────────────

    async def _client_handler(self, ws: Any) -> None:
        self.clients.add(ws)
        print(f"[ws] + {ws.remote_address}  ({len(self.clients)} connected)")
        try:
            async for raw in ws:
                try:
                    obj = json.loads(raw)
                    if obj.get("cmd") == "set_mode":
                        mode = obj.get("mode")
                        if mode in ("mock", "elm") and self._cmdq is not None:
                            print(f"[ws] ← set_mode={mode} from {ws.remote_address}")
                            await self._cmdq.put({"cmd": "set_mode", "mode": mode})
                except (json.JSONDecodeError, AttributeError):
                    pass
        except websockets.ConnectionClosed:
            pass
        finally:
            self.clients.discard(ws)
            print(f"[ws] - {ws.remote_address}  ({len(self.clients)} connected)")

    # ── Live mode switch ──────────────────────────────────────────────────

    async def _handle_set_mode(self, new_mode: str) -> None:
        current = "mock" if isinstance(self.provider, MockProvider) else "elm"
        if new_mode == current:
            print(f"[cmd] Already in {current} mode — ignoring")
            return

        print(f"[cmd] Switching {current} → {new_mode} …")
        await self.provider.stop()

        error_msg: Optional[str] = None
        try:
            if new_mode == "elm":
                try:
                    new_provider: TelemetryProvider = Elm327Provider(
                        self.elm_port, self.elm_baud
                    )
                except (ImportError, RuntimeError) as exc:
                    # Elm327Provider.__init__ raises RuntimeError when `import obd` fails
                    if isinstance(exc, ImportError) or "python-obd not installed" in str(exc):
                        raise RuntimeError(
                            "python-obd not installed — REAL mode unavailable"
                        )
                    raise
            else:
                new_provider = MockProvider()

            await new_provider.start()
            self.provider = new_provider
            print(f"[cmd] Mode switched to {new_mode} ✓")
        except Exception as exc:
            error_msg = str(exc)
            print(f"[cmd] Switch to {new_mode} failed: {exc}  → reverting to mock")
            self.provider = MockProvider()
            await self.provider.start()

        if error_msg:
            # One-shot error frame so the UI knows the switch failed
            sample = await self.provider.read()
            sample.mode_error = error_msg
            payload = json.dumps(sample.to_dict(), separators=(",", ":"))
            for ws in list(self.clients):
                try:
                    await ws.send(payload)
                except websockets.ConnectionClosed:
                    pass

    # ── Broadcast loop ────────────────────────────────────────────────────

    async def _broadcast_loop(self) -> None:
        self._cmdq = asyncio.Queue()
        await self.provider.start()
        try:
            next_tick = time.monotonic()
            while not self._stop.is_set():

                # Drain command queue (non-blocking)
                try:
                    cmd = self._cmdq.get_nowait()
                    if cmd.get("cmd") == "set_mode":
                        await self._handle_set_mode(cmd["mode"])
                except asyncio.QueueEmpty:
                    pass

                # Read + broadcast
                sample  = await self.provider.read()
                payload = json.dumps(sample.to_dict(), separators=(",", ":"))

                dead = []
                for ws in list(self.clients):
                    try:
                        await ws.send(payload)
                    except websockets.ConnectionClosed:
                        dead.append(ws)
                for ws in dead:
                    self.clients.discard(ws)

                # Precise timing
                next_tick += self.period
                sleep_s = next_tick - time.monotonic()
                if sleep_s > 0:
                    await asyncio.sleep(sleep_s)
                else:
                    next_tick = time.monotonic()   # re-sync if we lagged
        finally:
            await self.provider.stop()

    # ── Run ───────────────────────────────────────────────────────────────

    async def run(self) -> None:
        mode = "mock" if isinstance(self.provider, MockProvider) else "elm"
        hz   = 1.0 / self.period
        print(f"[obd_service] mode={mode}  ws://{self.host}:{self.port}  hz={hz:.1f}")
        print(f"[obd_service] Send {{\"cmd\":\"set_mode\",\"mode\":\"elm\"}} to switch live")
        async with websockets.serve(self._client_handler, self.host, self.port):
            await self._broadcast_loop()

    def request_stop(self) -> None:
        self._stop.set()


# ── Entry point ───────────────────────────────────────────────────────────────

async def _main() -> None:
    ap = argparse.ArgumentParser(description="VEYA OBD WebSocket service")
    ap.add_argument("--mode",     choices=["mock", "elm"], default="mock",
                    help="Data source (default: mock)")
    ap.add_argument("--host",     default="127.0.0.1")
    ap.add_argument("--port",     type=int, default=8765)
    ap.add_argument("--hz",       type=float, default=0.0,
                    help="Broadcast rate in Hz (default: 10 for mock, 4 for elm)")
    ap.add_argument("--elm-port", default="/dev/ttyUSB0",
                    help="Serial port of ELM327 adapter")
    ap.add_argument("--elm-baud", type=int, default=38400,
                    help="Baud rate for ELM327")
    args = ap.parse_args()

    if args.mode == "elm":
        provider: TelemetryProvider = Elm327Provider(args.elm_port, args.elm_baud)
        hz = args.hz if args.hz > 0 else 4.0
    else:
        provider = MockProvider()
        hz = args.hz if args.hz > 0 else 10.0

    server = TelemetryServer(
        provider, args.host, args.port, hz,
        elm_port=args.elm_port, elm_baud=args.elm_baud,
    )

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, server.request_stop)
        except NotImplementedError:
            pass   # Windows fallback

    await server.run()


if __name__ == "__main__":
    try:
        asyncio.run(_main())
    except Exception as e:
        print(f"[obd_service] Fatal: {e}")
        raise
