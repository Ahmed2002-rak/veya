#!/usr/bin/env python3
import argparse
import asyncio
import json
import math
import signal
import time
from dataclasses import dataclass
from typing import Dict, Any, Set

import websockets
from websockets.server import WebSocketServerProtocol


# ----------------------------
# Telemetry schema (schéma)
# ----------------------------
SCHEMA_VERSION = 1


@dataclass
class Telemetry:
    ts: float
    status: str  # "mock" or "elm"
    rpm: int
    speed_kph: float
    coolant_c: float
    throttle_pct: float
    warnings: Dict[str, bool]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "schema": SCHEMA_VERSION,
            "ts": self.ts,
            "status": self.status,
            "rpm": int(self.rpm),
            "speed_kph": float(self.speed_kph),
            "coolant_c": float(self.coolant_c),
            "throttle_pct": float(self.throttle_pct),
            "warnings": self.warnings,
        }


# ----------------------------
# Providers (abstraction)
# ----------------------------
class TelemetryProvider:
    async def start(self) -> None:
        """Optional init step."""
        return

    async def read(self) -> Telemetry:
        """Return latest telemetry sample."""
        raise NotImplementedError

    async def stop(self) -> None:
        """Optional cleanup step."""
        return


class MockProvider(TelemetryProvider):
    def __init__(self) -> None:
        self._t0 = time.time()

    async def read(self) -> Telemetry:
        t = time.time() - self._t0

        # Smooth signals (signaux lisses)
        rpm = 900 + 1700 * (0.5 + 0.5 * math.sin(t * 0.9))
        speed = 10 + 80 * (0.5 + 0.5 * math.sin(t * 0.25 + 1.2))
        coolant = 75 + 18 * (0.5 + 0.5 * math.sin(t * 0.05))
        throttle = 5 + 55 * (0.5 + 0.5 * math.sin(t * 0.6 + 0.4))

        # Example warnings (alertes)
        warnings = {
            "coolant_high": coolant > 95.0,
            "overspeed": speed > 120.0,
        }

        return Telemetry(
            ts=time.time(),
            status="mock",
            rpm=int(rpm),
            speed_kph=round(speed, 1),
            coolant_c=round(coolant, 1),
            throttle_pct=round(throttle, 1),
            warnings=warnings,
        )


class Elm327Provider(TelemetryProvider):
    """
    Placeholder for real ELM327 mode.
    Later you will implement:
      - open serial/Bluetooth
      - send OBD-II PIDs
      - parse responses
      - map to Telemetry()
    """
    def __init__(self, port: str, baud: int) -> None:
        self.port = port
        self.baud = baud

    async def start(self) -> None:
        # Not implemented yet
        print(f"[ELM] TODO: connect to ELM327 on {self.port} @ {self.baud}")
        print("[ELM] For now, exiting to avoid fake data.")
        raise RuntimeError("ELM327 mode not implemented yet")

    async def read(self) -> Telemetry:
        raise RuntimeError("ELM327 mode not implemented yet")


# ----------------------------
# WebSocket server (broadcast)
# ----------------------------
class TelemetryServer:
    def __init__(self, provider: TelemetryProvider, host: str, port: int, hz: float) -> None:
        self.provider = provider
        self.host = host
        self.port = port
        self.period = 1.0 / max(1.0, hz)
        self.clients: Set[WebSocketServerProtocol] = set()
        self._stop = asyncio.Event()

    async def client_handler(self, ws: WebSocketServerProtocol) -> None:
        self.clients.add(ws)
        try:
            # Keep connection alive, ignore incoming messages
            async for _ in ws:
                pass
        except websockets.ConnectionClosed:
            pass
        finally:
            self.clients.discard(ws)

    async def broadcast_loop(self) -> None:
        await self.provider.start()
        try:
            next_tick = time.monotonic()
            while not self._stop.is_set():
                sample = await self.provider.read()
                payload = json.dumps(sample.to_dict(), separators=(",", ":"))

                if self.clients:
                    dead = []
                    for ws in list(self.clients):
                        try:
                            await ws.send(payload)
                        except websockets.ConnectionClosed:
                            dead.append(ws)
                    for ws in dead:
                        self.clients.discard(ws)

                next_tick += self.period
                sleep_s = next_tick - time.monotonic()
                if sleep_s > 0:
                    await asyncio.sleep(sleep_s)
                else:
                    # If lagging, resync (avoid drift)
                    next_tick = time.monotonic()
        finally:
            await self.provider.stop()

    async def run(self) -> None:
        print(f"VEYA obd_service running on ws://{self.host}:{self.port} (period={self.period:.3f}s)")
        async with websockets.serve(self.client_handler, self.host, self.port):
            await self.broadcast_loop()

    def request_stop(self) -> None:
        self._stop.set()


# ----------------------------
# Main
# ----------------------------
async def amain() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["mock", "elm"], default="mock")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--hz", type=float, default=5.0)
    ap.add_argument("--elm-port", default="/dev/ttyUSB0")
    ap.add_argument("--elm-baud", type=int, default=38400)
    args = ap.parse_args()

    if args.mode == "mock":
        provider = MockProvider()
    else:
        provider = Elm327Provider(args.elm_port, args.elm_baud)

    server = TelemetryServer(provider, args.host, args.port, args.hz)

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, server.request_stop)
        except NotImplementedError:
            pass

    await server.run()


if __name__ == "__main__":
    try:
        asyncio.run(amain())
    except Exception as e:
        print(f"[obd_service] Fatal: {e}")
        raise
