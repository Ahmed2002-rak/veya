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
    {"cmd": "set_mode",    "mode": "mock"|"elm"}
    {"cmd": "wifi_scan"}
    {"cmd": "wifi_status"}
    {"cmd": "wifi_connect",    "ssid": "...", "password": "..."}
    {"cmd": "wifi_disconnect"}
    {"cmd": "load_server_config"}
    {"cmd": "save_server_config", "data": {...}}

Note: the new source-facing protocol (contract.py) is unrelated to this
file. Translation happens in core.py.
"""

from __future__ import annotations

import asyncio
import json
import logging
import pathlib
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
                elif obj.get("cmd") == "save_profile":
                    # New in Phase 2.2b — not part of the telemetry schema freeze;
                    # handled here rather than routing through core (pure file I/O).
                    data = obj.get("data", {})
                    if isinstance(data, dict):
                        await self._handle_save_profile(ws, data)
                elif obj.get("cmd") == "load_profile":
                    await self._handle_load_profile(ws)
                # ── Wi-Fi commands (Phase 3.0a) ───────────────────────────────
                elif obj.get("cmd") == "wifi_scan":
                    asyncio.create_task(self._handle_wifi_scan(ws))
                elif obj.get("cmd") == "wifi_status":
                    asyncio.create_task(self._handle_wifi_status(ws))
                elif obj.get("cmd") == "wifi_connect":
                    ssid     = obj.get("ssid", "")
                    password = obj.get("password", "")
                    asyncio.create_task(self._handle_wifi_connect(ws, ssid, password))
                elif obj.get("cmd") == "wifi_disconnect":
                    asyncio.create_task(self._handle_wifi_disconnect(ws))
                # ── Server-URL config commands (Phase 3.0a) ───────────────────
                elif obj.get("cmd") == "load_server_config":
                    await self._handle_load_server_config(ws)
                elif obj.get("cmd") == "save_server_config":
                    data = obj.get("data", {})
                    if isinstance(data, dict):
                        await self._handle_save_server_config(ws, data)
        except websockets.ConnectionClosed:
            pass
        finally:
            self._clients.discard(ws)
            log.info("[ws] - UI client %s  (%d connected)", peer, len(self._clients))

    # ── Profile persistence (Phase 2.2b) ─────────────────────────────────────
    # These commands are orthogonal to telemetry; adding them does NOT violate
    # the telemetry-schema freeze (see docs/MEMORY.md §3.1).

    async def _handle_save_profile(self, ws: Any, data: Dict[str, Any]) -> None:
        profile_dir = pathlib.Path.home() / ".veya"
        try:
            profile_dir.mkdir(parents=True, exist_ok=True)
            profile_path = profile_dir / "user_profile.json"
            profile_path.write_text(json.dumps(data, indent=2))
            await ws.send(json.dumps({"type": "profile_saved", "ok": True}))
            log.info("[ws] profile saved → %s", profile_path)
        except Exception as exc:
            log.error("[ws] save_profile failed: %s", exc)
            try:
                await ws.send(json.dumps({"type": "profile_saved", "ok": False,
                                          "error": str(exc)}))
            except Exception:
                pass

    async def _handle_load_profile(self, ws: Any) -> None:
        profile_path = pathlib.Path.home() / ".veya" / "user_profile.json"
        try:
            if profile_path.exists():
                data = json.loads(profile_path.read_text())
            else:
                data = {}
            await ws.send(json.dumps({"type": "profile_data", "data": data}))
            log.info("[ws] profile loaded ← %s", profile_path)
        except Exception as exc:
            log.error("[ws] load_profile failed: %s", exc)
            try:
                await ws.send(json.dumps({"type": "profile_data", "data": {},
                                          "error": str(exc)}))
            except Exception:
                pass

    # ── Wi-Fi commands (Phase 3.0a) ───────────────────────────────────────────
    # Each runs wifi.py helper functions in a thread pool so subprocess calls
    # don't block the asyncio event loop.

    async def _handle_wifi_scan(self, ws: Any) -> None:
        loop = asyncio.get_running_loop()
        try:
            from services.veya_core.helpers import wifi as _wifi
            result = await asyncio.wait_for(
                loop.run_in_executor(None, _wifi.scan),
                timeout=15.0,
            )
            networks = result.get("networks", [])
            error    = result.get("error", "")
            await ws.send(json.dumps({
                "type": "wifi_scan_result",
                "networks": networks,
                "error": error,
            }))
            log.info("[ws] wifi_scan → %d networks", len(networks))
        except asyncio.TimeoutError:
            log.warning("[ws] wifi_scan timed out")
            await self._ws_send_safe(ws, {"type": "wifi_scan_result", "networks": [],
                                          "error": "scan timed out"})
        except Exception as exc:
            log.error("[ws] wifi_scan failed: %s", exc)
            await self._ws_send_safe(ws, {"type": "wifi_scan_result", "networks": [],
                                          "error": str(exc)})

    async def _handle_wifi_status(self, ws: Any) -> None:
        loop = asyncio.get_running_loop()
        try:
            from services.veya_core.helpers import wifi as _wifi
            result = await asyncio.wait_for(
                loop.run_in_executor(None, _wifi.status),
                timeout=5.0,
            )
            await ws.send(json.dumps({
                "type":      "wifi_status",
                "connected": result.get("connected", False),
                "ssid":      result.get("ssid", ""),
                "device":    result.get("device", "wlan0"),
                "error":     result.get("error", ""),
            }))
            log.info("[ws] wifi_status → connected=%s ssid=%r",
                     result.get("connected"), result.get("ssid"))
        except asyncio.TimeoutError:
            log.warning("[ws] wifi_status timed out")
            await self._ws_send_safe(ws, {"type": "wifi_status", "connected": False,
                                          "ssid": "", "device": "wlan0",
                                          "error": "status timed out"})
        except Exception as exc:
            log.error("[ws] wifi_status failed: %s", exc)
            await self._ws_send_safe(ws, {"type": "wifi_status", "connected": False,
                                          "ssid": "", "device": "wlan0",
                                          "error": str(exc)})

    async def _handle_wifi_connect(self, ws: Any, ssid: str, password: str) -> None:
        loop = asyncio.get_running_loop()
        import functools
        try:
            from services.veya_core.helpers import wifi as _wifi
            result = await asyncio.wait_for(
                loop.run_in_executor(None, functools.partial(_wifi.connect, ssid, password)),
                timeout=30.0,
            )
            await ws.send(json.dumps({
                "type":  "wifi_connect_result",
                "ok":    result.get("ok", False),
                "error": result.get("error", ""),
            }))
            log.info("[ws] wifi_connect ssid=%r ok=%s", ssid, result.get("ok"))
        except asyncio.TimeoutError:
            log.warning("[ws] wifi_connect timed out ssid=%r", ssid)
            await self._ws_send_safe(ws, {"type": "wifi_connect_result", "ok": False,
                                          "error": "connection timed out"})
        except Exception as exc:
            log.error("[ws] wifi_connect failed ssid=%r: %s", ssid, exc)
            await self._ws_send_safe(ws, {"type": "wifi_connect_result", "ok": False,
                                          "error": str(exc)})

    async def _handle_wifi_disconnect(self, ws: Any) -> None:
        loop = asyncio.get_running_loop()
        try:
            from services.veya_core.helpers import wifi as _wifi
            result = await asyncio.wait_for(
                loop.run_in_executor(None, _wifi.disconnect),
                timeout=5.0,
            )
            await ws.send(json.dumps({
                "type":  "wifi_disconnect_result",
                "ok":    result.get("ok", False),
                "error": result.get("error", ""),
            }))
            log.info("[ws] wifi_disconnect ok=%s", result.get("ok"))
        except asyncio.TimeoutError:
            log.warning("[ws] wifi_disconnect timed out")
            await self._ws_send_safe(ws, {"type": "wifi_disconnect_result", "ok": False,
                                          "error": "disconnect timed out"})
        except Exception as exc:
            log.error("[ws] wifi_disconnect failed: %s", exc)
            await self._ws_send_safe(ws, {"type": "wifi_disconnect_result", "ok": False,
                                          "error": str(exc)})

    # ── Server URL config (Phase 3.0a) ────────────────────────────────────────

    _SERVER_CONFIG_PATH = pathlib.Path.home() / ".veya" / "server_config.json"
    _SERVER_CONFIG_DEFAULTS: Dict[str, Any] = {
        "report_url":       "",
        "live_session_url": "",
        "last_updated":     "",
    }

    def _read_server_config(self) -> Dict[str, Any]:
        cfg = dict(self._SERVER_CONFIG_DEFAULTS)
        if self._SERVER_CONFIG_PATH.exists():
            try:
                stored = json.loads(self._SERVER_CONFIG_PATH.read_text())
                cfg.update({k: stored[k] for k in self._SERVER_CONFIG_DEFAULTS if k in stored})
            except Exception:
                pass
        return cfg

    async def _handle_load_server_config(self, ws: Any) -> None:
        try:
            cfg = self._read_server_config()
            await ws.send(json.dumps({"type": "server_config", "data": cfg}))
            log.info("[ws] server_config loaded")
        except Exception as exc:
            log.error("[ws] load_server_config failed: %s", exc)
            await self._ws_send_safe(ws, {"type": "server_config", "data": {},
                                          "error": str(exc)})

    async def _handle_save_server_config(self, ws: Any, data: Dict[str, Any]) -> None:
        try:
            cfg = self._read_server_config()
            for k in self._SERVER_CONFIG_DEFAULTS:
                if k in data:
                    cfg[k] = data[k]
            self._SERVER_CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
            self._SERVER_CONFIG_PATH.write_text(json.dumps(cfg, indent=2))
            await ws.send(json.dumps({"type": "server_config_saved", "ok": True}))
            log.info("[ws] server_config saved → %s", self._SERVER_CONFIG_PATH)
        except Exception as exc:
            log.error("[ws] save_server_config failed: %s", exc)
            await self._ws_send_safe(ws, {"type": "server_config_saved", "ok": False,
                                          "error": str(exc)})

    # ── Utility ───────────────────────────────────────────────────────────────

    async def _ws_send_safe(self, ws: Any, obj: Dict[str, Any]) -> None:
        try:
            await ws.send(json.dumps(obj))
        except Exception:
            pass
