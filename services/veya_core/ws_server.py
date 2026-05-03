"""
VEYA — UI-facing WebSocket Server                       ws_server.py
=====================================================================

WebSocket server consumed by VehicleDataProvider.qml. The wire format
is the LEGACY UI contract — preserved bit-for-bit so the QML provider
needs no changes:

    {
      "schema":        1,
      "ts":            1773381689.793,
      "status":        "mock" | "elm",
      "rpm":           int,
      "speed_kph":     float,
      "coolant_c":     float,
      "throttle_pct":  float,
      "engine_load":   float,
      "battery_v":     float,
      "fuel_level":    float,
      "intake_temp_c": float,
      "warnings": {
        "coolant_high": bool,
        "overspeed":    bool,
        "low_fuel":     bool,
        "low_battery":  bool
      },
      "mode_error":    str   (optional, only when present)
    }

Incoming UI commands:
    {"cmd": "set_mode", "mode": "mock"|"elm"}

Note: the new source-facing protocol (contract.py) is unrelated to this
file. Translation happens in core.py.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
import warnings as _warnings
from typing import Any, Awaitable, Callable, Dict, Optional, Set


# Silence the websockets 16.0 deprecation warnings that otherwise flood logs.
_warnings.filterwarnings("ignore", category=DeprecationWarning, module="websockets")

import websockets


log = logging.getLogger(__name__)


UiCommandCallback = Callable[[Dict[str, Any]], Awaitable[None]]


# UI-side throttle: never broadcast faster than this many frames per second.
# Matches the 50 ms / 20 Hz cap that VehicleDataProvider.qml itself applies.
UI_BROADCAST_HARD_HZ = 20.0
_UI_MIN_PERIOD = 1.0 / UI_BROADCAST_HARD_HZ


class UiWebSocketServer:
    """
    WebSocket server for the QML UI.

    Construction:
        UiWebSocketServer(host, port, on_ui_command)

    The `on_ui_command` coroutine is awaited for every command frame
    received from a UI client (currently only `set_mode`).
    """

    def __init__(
        self,
        host: str,
        port: int,
        on_ui_command: UiCommandCallback,
    ) -> None:
        self.host = host
        self.port = port
        self._on_ui_command = on_ui_command

        self._server: Optional[Any] = None
        self._clients: Set[Any] = set()
        self._last_broadcast_ts: float = 0.0

    # ── Lifecycle ────────────────────────────────────────────────────────────

    async def start(self) -> None:
        self._server = await websockets.serve(self._handle_client, self.host, self.port)
        log.info("[ws] listening on ws://%s:%d", self.host, self.port)

    async def stop(self) -> None:
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None
        for ws in list(self._clients):
            try:
                await ws.close()
            except Exception:
                pass
        self._clients.clear()
        log.info("[ws] stopped")

    @property
    def client_count(self) -> int:
        return len(self._clients)

    # ── Broadcast ────────────────────────────────────────────────────────────

    async def broadcast(self, frame: Dict[str, Any]) -> None:
        """
        Broadcast a UI-format frame to every connected client. Drops the
        frame if the previous broadcast was less than 50 ms ago (20 Hz cap).
        """
        now = time.monotonic()
        if now - self._last_broadcast_ts < _UI_MIN_PERIOD:
            return
        self._last_broadcast_ts = now

        if not self._clients:
            return

        payload = json.dumps(frame, separators=(",", ":"))
        dead = []
        for ws in list(self._clients):
            try:
                await ws.send(payload)
            except websockets.ConnectionClosed:
                dead.append(ws)
            except Exception:
                log.exception("[ws] send failed")
                dead.append(ws)
        for ws in dead:
            self._clients.discard(ws)

    # ── Per-client handler ───────────────────────────────────────────────────

    async def _handle_client(self, ws: Any) -> None:
        peer = getattr(ws, "remote_address", None)
        self._clients.add(ws)
        log.info("[ws] + UI client %s  (%d connected)", peer, len(self._clients))
        try:
            async for raw in ws:
                try:
                    obj = json.loads(raw)
                except (json.JSONDecodeError, TypeError):
                    continue
                if not isinstance(obj, dict):
                    continue
                if obj.get("cmd") == "set_mode":
                    mode = obj.get("mode")
                    if mode not in ("mock", "elm"):
                        log.warning("[ws] ignoring set_mode with bad mode=%r", mode)
                        continue
                    log.info("[ws] ← set_mode=%s from %s", mode, peer)
                    try:
                        await self._on_ui_command({"cmd": "set_mode", "mode": mode})
                    except Exception:
                        log.exception("[ws] on_ui_command callback raised")
        except websockets.ConnectionClosed:
            pass
        finally:
            self._clients.discard(ws)
            log.info("[ws] - UI client %s  (%d connected)", peer, len(self._clients))
