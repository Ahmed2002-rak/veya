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
    {"cmd": "set_mode",    "mode": "mock"|"elm"}   ← UI-layer toggle; NOT a source-layer set_mode
    {"cmd": "wifi_scan"}
    {"cmd": "wifi_status"}
    {"cmd": "wifi_connect",    "ssid": "...", "password": "..."}
    {"cmd": "wifi_disconnect"}
    {"cmd": "load_server_config"}
    {"cmd": "save_server_config", "data": {...}}
    {"cmd": "bt_scan"}
    {"cmd": "bt_status"}
    {"cmd": "bt_pair",        "mac": "AA:BB:CC:DD:EE:FF"}
    {"cmd": "bt_unpair",      "mac": "AA:BB:CC:DD:EE:FF"}
    {"cmd": "bt_disconnect"}
    {"cmd": "bt_bridge_status"}
    {"cmd": "bt_pairing_mode", "enabled": true|false}
    {"cmd": "esp32_query_dtc"}      ← Phase 3.0e: routes query_dtc to ESP32 via TCP
    {"cmd": "esp32_clear_dtc"}      ← Phase 3.0e: routes clear_dtc to ESP32 via TCP
    {"cmd": "esp32_query_mileage"}  ← Phase 3.0e: routes query_mileage to ESP32 via TCP
    {"cmd": "load_sample_report"}   ← Phase 3.0g: injects hardcoded demo report_result

Note: the new source-facing protocol (contract.py) is unrelated to this
file. Translation happens in core.py.
"""

from __future__ import annotations

import asyncio
import json
import logging
import pathlib
import signal
import subprocess
import sys
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

# BT bridge config and subprocess state (module-level so all handler calls share it)
_BT_CONFIG_PATH  = pathlib.Path.home() / ".veya" / "bt_config.json"
_BT_STATUS_FILE  = pathlib.Path("/tmp/veya_bt_bridge_status.txt")
_bt_bridge_proc: Optional[subprocess.Popen] = None  # live bridge process


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

    async def broadcast_event(self, frame: Dict[str, Any]) -> None:
        """
        Broadcast a non-telemetry event frame (dtc, clear_dtc_result, mileage_response)
        to every connected UI client. No rate limiting — these are infrequent, one-shot
        responses, not continuous telemetry.
        """
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
                log.exception("[ws] broadcast_event send failed")
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
                    # UI-layer TEST/REAL toggle — "mock"|"elm" selects the Pi-side mode.
                    # This is NOT the source-layer set_mode verb (deprecated in Phase 3.0e).
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
                # ── Bluetooth commands (Phase 3.0b) ───────────────────────────
                elif obj.get("cmd") == "bt_scan":
                    asyncio.create_task(self._handle_bt_scan(ws))
                elif obj.get("cmd") == "bt_status":
                    asyncio.create_task(self._handle_bt_status(ws))
                elif obj.get("cmd") == "bt_pair":
                    mac = obj.get("mac", "")
                    asyncio.create_task(self._handle_bt_pair(ws, mac))
                elif obj.get("cmd") == "bt_unpair":
                    mac = obj.get("mac", "")
                    asyncio.create_task(self._handle_bt_unpair(ws, mac))
                elif obj.get("cmd") == "bt_disconnect":
                    asyncio.create_task(self._handle_bt_disconnect(ws))
                elif obj.get("cmd") == "bt_bridge_status":
                    asyncio.create_task(self._handle_bt_bridge_status(ws))
                elif obj.get("cmd") == "bt_pairing_mode":
                    enabled = bool(obj.get("enabled", False))
                    asyncio.create_task(self._handle_bt_pairing_mode(ws, enabled))
                # ── ESP32 command routing (Phase 3.0e) ───────────────────────
                elif obj.get("cmd") == "esp32_query_dtc":
                    log.info("[ws] ← esp32_query_dtc from %s", peer)
                    try:
                        await self._on_ui_command({"cmd": "esp32_query_dtc"})
                    except Exception:
                        log.exception("[ws] on_ui_command callback raised")
                elif obj.get("cmd") == "esp32_clear_dtc":
                    log.info("[ws] ← esp32_clear_dtc from %s", peer)
                    try:
                        await self._on_ui_command({"cmd": "esp32_clear_dtc"})
                    except Exception:
                        log.exception("[ws] on_ui_command callback raised")
                elif obj.get("cmd") == "esp32_query_mileage":
                    log.info("[ws] ← esp32_query_mileage from %s", peer)
                    try:
                        await self._on_ui_command({"cmd": "esp32_query_mileage"})
                    except Exception:
                        log.exception("[ws] on_ui_command callback raised")
                # ── Server API commands (Phase 3.1) ──────────────────────────────
                elif obj.get("cmd") == "server_check":
                    asyncio.create_task(self._handle_server_check())
                elif obj.get("cmd") == "server_lookup_dtc":
                    code = obj.get("code", "")
                    kind = obj.get("kind", "signification")
                    asyncio.create_task(self._handle_server_lookup_dtc(code, kind))
                elif obj.get("cmd") == "server_request_report":
                    payload = obj.get("payload", {})
                    asyncio.create_task(self._handle_server_request_report(payload))
                elif obj.get("cmd") == "load_sample_report":
                    log.info("[ws] ← load_sample_report from %s", peer)
                    asyncio.create_task(self._handle_load_sample_report())
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

    # ── Bluetooth commands (Phase 3.0b) ──────────────────────────────────────
    # Each runs bluetooth.py helper in a thread pool so subprocess calls don't
    # block the asyncio event loop. Same pattern as wifi_* handlers above.

    async def _handle_bt_scan(self, ws: Any) -> None:
        loop = asyncio.get_running_loop()
        try:
            from services.veya_core.helpers import bluetooth as _bt
            result = await asyncio.wait_for(
                loop.run_in_executor(None, _bt.scan),
                timeout=20.0,
            )
            await ws.send(json.dumps({
                "type":    "bt_scan_result",
                "devices": result.get("devices", []),
                "error":   result.get("error", ""),
            }))
            log.info("[ws] bt_scan → %d devices", len(result.get("devices", [])))
        except asyncio.TimeoutError:
            log.warning("[ws] bt_scan timed out")
            await self._ws_send_safe(ws, {"type": "bt_scan_result", "devices": [],
                                          "error": "scan timed out"})
        except Exception as exc:
            log.error("[ws] bt_scan failed: %s", exc)
            await self._ws_send_safe(ws, {"type": "bt_scan_result", "devices": [],
                                          "error": str(exc)})

    async def _handle_bt_status(self, ws: Any) -> None:
        loop = asyncio.get_running_loop()
        try:
            from services.veya_core.helpers import bluetooth as _bt
            result = await asyncio.wait_for(
                loop.run_in_executor(None, _bt.status),
                timeout=10.0,
            )
            await ws.send(json.dumps({
                "type":            "bt_status",
                "paired":          result.get("paired", []),
                "connected":       result.get("connected", []),
                "adapter_powered": result.get("adapter_powered", False),
                "error":           result.get("error", ""),
            }))
            log.info("[ws] bt_status → paired=%d connected=%d",
                     len(result.get("paired", [])), len(result.get("connected", [])))
        except asyncio.TimeoutError:
            log.warning("[ws] bt_status timed out")
            await self._ws_send_safe(ws, {"type": "bt_status", "paired": [], "connected": [],
                                          "adapter_powered": False, "error": "status timed out"})
        except Exception as exc:
            log.error("[ws] bt_status failed: %s", exc)
            await self._ws_send_safe(ws, {"type": "bt_status", "paired": [], "connected": [],
                                          "adapter_powered": False, "error": str(exc)})

    async def _handle_bt_pair(self, ws: Any, mac: str) -> None:
        if not mac:
            await self._ws_send_safe(ws, {"type": "bt_pair_result", "ok": False,
                                          "error": "no MAC provided"})
            return
        loop = asyncio.get_running_loop()
        import functools
        try:
            from services.veya_core.helpers import bluetooth as _bt
            result = await asyncio.wait_for(
                loop.run_in_executor(None, functools.partial(_bt.pair, mac)),
                timeout=40.0,
            )
            ok = result.get("ok", False)
            bridge_started = False
            if ok:
                self._bt_write_config(mac)
                self._bt_start_bridge()
                bridge_started = (_bt_bridge_proc is not None and _bt_bridge_proc.poll() is None)
            await ws.send(json.dumps({
                "type":           "bt_pair_result",
                "ok":             ok,
                "bridge_started": bridge_started,
                "error":          result.get("error", ""),
            }))
            log.info("[ws] bt_pair mac=%r ok=%s bridge_started=%s", mac, ok, bridge_started)
        except asyncio.TimeoutError:
            log.warning("[ws] bt_pair timed out mac=%r", mac)
            await self._ws_send_safe(ws, {"type": "bt_pair_result", "ok": False,
                                          "error": "pair timed out"})
        except Exception as exc:
            log.error("[ws] bt_pair failed mac=%r: %s", mac, exc)
            await self._ws_send_safe(ws, {"type": "bt_pair_result", "ok": False,
                                          "error": str(exc)})

    async def _handle_bt_unpair(self, ws: Any, mac: str) -> None:
        if not mac:
            await self._ws_send_safe(ws, {"type": "bt_unpair_result", "ok": False,
                                          "error": "no MAC provided"})
            return
        loop = asyncio.get_running_loop()
        import functools
        try:
            from services.veya_core.helpers import bluetooth as _bt
            self._bt_stop_bridge()
            result = await asyncio.wait_for(
                loop.run_in_executor(None, functools.partial(_bt.unpair, mac)),
                timeout=15.0,
            )
            if result.get("ok", False):
                self._bt_clear_config()
            await ws.send(json.dumps({
                "type":  "bt_unpair_result",
                "ok":    result.get("ok", False),
                "error": result.get("error", ""),
            }))
            log.info("[ws] bt_unpair mac=%r ok=%s", mac, result.get("ok"))
        except asyncio.TimeoutError:
            log.warning("[ws] bt_unpair timed out mac=%r", mac)
            await self._ws_send_safe(ws, {"type": "bt_unpair_result", "ok": False,
                                          "error": "unpair timed out"})
        except Exception as exc:
            log.error("[ws] bt_unpair failed mac=%r: %s", mac, exc)
            await self._ws_send_safe(ws, {"type": "bt_unpair_result", "ok": False,
                                          "error": str(exc)})

    async def _handle_bt_disconnect(self, ws: Any) -> None:
        self._bt_stop_bridge()
        await self._ws_send_safe(ws, {"type": "bt_disconnect_result", "ok": True, "error": ""})
        log.info("[ws] bt_disconnect — bridge stopped")

    async def _handle_bt_bridge_status(self, ws: Any) -> None:
        global _bt_bridge_proc
        running = False
        pid = 0
        if _bt_bridge_proc is not None:
            ret = _bt_bridge_proc.poll()
            if ret is None:
                running = True
                pid = _bt_bridge_proc.pid
            else:
                _bt_bridge_proc = None

        esp32_connected = self._bt_read_esp32_connected()
        await self._ws_send_safe(ws, {
            "type":            "bt_bridge_status",
            "running":         running,
            "pid":             pid,
            "esp32_connected": esp32_connected,
            "error":           "",
        })
        log.info("[ws] bt_bridge_status running=%s pid=%d esp32_connected=%s",
                 running, pid, esp32_connected)

    async def _handle_bt_pairing_mode(self, ws: Any, enabled: bool) -> None:
        state = "on" if enabled else "off"
        errors: list[str] = []
        for subcmd in ("pairable", "discoverable"):
            try:
                res = subprocess.run(
                    ["bluetoothctl", subcmd, state],
                    capture_output=True, text=True, timeout=3,
                )
                if res.returncode != 0:
                    errors.append(f"{subcmd}: {res.stderr.strip()}")
            except subprocess.TimeoutExpired:
                errors.append(f"{subcmd}: timed out")
            except Exception as exc:
                errors.append(f"{subcmd}: {exc}")
        ok = not errors
        await self._ws_send_safe(ws, {
            "type":  "bt_pairing_mode_result",
            "ok":    ok,
            "error": "; ".join(errors),
        })
        log.info("[ws] bt_pairing_mode enabled=%s ok=%s", enabled, ok)

    # ── BT config / bridge subprocess helpers ─────────────────────────────────

    def _bt_read_esp32_connected(self) -> bool:
        """Return True if the status file exists, contains 'connected', and was
        touched within the last 5 seconds (bridge is actively forwarding data)."""
        try:
            if not _BT_STATUS_FILE.exists():
                return False
            content = _BT_STATUS_FILE.read_text().strip()
            if content != "connected":
                return False
            mtime = _BT_STATUS_FILE.stat().st_mtime
            return (time.time() - mtime) <= 5.0
        except Exception:
            return False

    def _bt_write_config(self, mac: str) -> None:
        import datetime
        _BT_CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        existing: Dict[str, Any] = {}
        if _BT_CONFIG_PATH.exists():
            try:
                existing = json.loads(_BT_CONFIG_PATH.read_text())
            except Exception:
                pass
        existing["esp32_mac"]      = mac.upper()
        existing["rfcomm_channel"] = existing.get("rfcomm_channel", 1)
        existing["last_paired"]    = datetime.datetime.utcnow().isoformat() + "Z"
        _BT_CONFIG_PATH.write_text(json.dumps(existing, indent=2))
        log.info("[ws] bt_config written: mac=%s → %s", mac, _BT_CONFIG_PATH)

    def _bt_clear_config(self) -> None:
        if _BT_CONFIG_PATH.exists():
            try:
                cfg = json.loads(_BT_CONFIG_PATH.read_text())
                cfg["esp32_mac"] = ""
                _BT_CONFIG_PATH.write_text(json.dumps(cfg, indent=2))
                log.info("[ws] bt_config cleared")
            except Exception as exc:
                log.warning("[ws] bt_clear_config failed: %s", exc)

    def _bt_start_bridge(self) -> None:
        global _bt_bridge_proc
        self._bt_stop_bridge()
        log_path = pathlib.Path.home() / "veya" / "logs" / "bt_bridge.log"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_fh = open(log_path, "a")
        try:
            _bt_bridge_proc = subprocess.Popen(
                [sys.executable, "-m", "services.veya_core.bt_bridge"],
                stdout=log_fh,
                stderr=log_fh,
                start_new_session=True,
            )
            log.info("[ws] bt_bridge started pid=%d", _bt_bridge_proc.pid)
        except Exception as exc:
            log.error("[ws] bt_bridge start failed: %s", exc)
            _bt_bridge_proc = None

    def _bt_stop_bridge(self) -> None:
        global _bt_bridge_proc
        if _bt_bridge_proc is not None:
            if _bt_bridge_proc.poll() is None:
                try:
                    _bt_bridge_proc.send_signal(signal.SIGTERM)
                    _bt_bridge_proc.wait(timeout=3)
                except Exception as exc:
                    log.warning("[ws] bt_bridge stop: %s", exc)
                    try:
                        _bt_bridge_proc.kill()
                    except Exception:
                        pass
                log.info("[ws] bt_bridge stopped")
            _bt_bridge_proc = None

    # ── Server API handlers (Phase 3.1) ──────────────────────────────────────

    async def _handle_server_check(self) -> None:
        loop = asyncio.get_running_loop()
        try:
            from services.veya_core.helpers import server_client as _sc
            result = await asyncio.wait_for(
                loop.run_in_executor(None, _sc.server_check),
                timeout=10.0,
            )
            await self.broadcast_event({
                "type":  "server_check_result",
                "ok":    result.get("ok", False),
                "error": result.get("error", ""),
            })
            log.info("[ws] server_check ok=%s", result.get("ok"))
        except asyncio.TimeoutError:
            await self.broadcast_event({"type": "server_check_result", "ok": False,
                                        "error": "timeout"})
        except Exception as exc:
            log.error("[ws] server_check failed: %s", exc)
            await self.broadcast_event({"type": "server_check_result", "ok": False,
                                        "error": str(exc)})

    async def _handle_server_lookup_dtc(self, code: str, kind: str) -> None:
        import functools
        loop = asyncio.get_running_loop()
        try:
            from services.veya_core.helpers import server_client as _sc
            result = await asyncio.wait_for(
                loop.run_in_executor(None, functools.partial(_sc.lookup_dtc, code, kind)),
                timeout=10.0,
            )
            await self.broadcast_event({
                "type":  "dtc_lookup_result",
                "code":  code,
                "kind":  kind,
                "text":  result.get("text", ""),
                "error": result.get("error", ""),
            })
            log.info("[ws] server_lookup_dtc code=%r kind=%r ok=%s", code, kind, result.get("ok"))
        except asyncio.TimeoutError:
            await self.broadcast_event({"type": "dtc_lookup_result", "code": code, "kind": kind,
                                        "text": "", "error": "timeout"})
        except Exception as exc:
            log.error("[ws] server_lookup_dtc failed: %s", exc)
            await self.broadcast_event({"type": "dtc_lookup_result", "code": code, "kind": kind,
                                        "text": "", "error": str(exc)})

    async def _handle_server_request_report(self, payload: dict) -> None:
        import functools
        loop = asyncio.get_running_loop()
        log.info("[ws] server_request_report payload from UI: %s",
                 json.dumps(payload, ensure_ascii=False))
        try:
            from services.veya_core.helpers import server_client as _sc
            result = await asyncio.wait_for(
                loop.run_in_executor(None, functools.partial(_sc.request_report, payload)),
                timeout=35.0,
            )
            log.info("[ws] server_request_report result: ok=%s error=%r message=%r",
                     result.get("ok"), result.get("error"), result.get("message"))
            await self.broadcast_event({
                "type":    "report_result",
                "ok":      result.get("ok", False),
                "report":  result.get("report"),
                "error":   result.get("error", ""),
                "message": result.get("message", ""),
            })
        except asyncio.TimeoutError:
            await self.broadcast_event({"type": "report_result", "ok": False, "report": None,
                                        "error": "timeout", "message": ""})
        except Exception as exc:
            log.error("[ws] server_request_report failed: %s", exc)
            await self.broadcast_event({"type": "report_result", "ok": False, "report": None,
                                        "error": str(exc), "message": ""})

    async def _handle_load_sample_report(self) -> None:
        try:
            from services.veya_core.helpers.sample_report import get_sample_report
            report = get_sample_report()
            await self.broadcast_event({
                "type":    "report_result",
                "ok":      True,
                "report":  report,
                "error":   None,
                "message": None,
            })
            log.info("[ws] load_sample_report → broadcasted report_id=%s", report.get("report_id"))
        except Exception as exc:
            log.error("[ws] load_sample_report failed: %s", exc)
            await self.broadcast_event({"type": "report_result", "ok": False, "report": None,
                                        "error": str(exc), "message": ""})

    # ── Utility ───────────────────────────────────────────────────────────────

    async def _ws_send_safe(self, ws: Any, obj: Dict[str, Any]) -> None:
        try:
            await ws.send(json.dumps(obj))
        except Exception:
            pass
