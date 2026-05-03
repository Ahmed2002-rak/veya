"""
VEYA — Source-to-Core Wire Contract                       contract.py
=====================================================================

This module defines the wire contract between data sources (ESP32, mock,
ELM327, etc.) and the VEYA core service. It is the source of truth — see
docs/CONTRACT.md for the human-readable spec.

Transport: TCP, line-delimited JSON (UTF-8). Each frame is one JSON
object terminated by a single newline character "\\n".

This contract is SOURCE-FACING. It is distinct from the UI-facing JSON
emitted by ws_server.py (which preserves the legacy obd_service.py
format for VehicleDataProvider.qml). Do not mix them.
"""

from __future__ import annotations

import time
from typing import Any, Dict, Iterable, List, Optional, Tuple


# ── Protocol version & default ports ─────────────────────────────────────────

SCHEMA_VERSION   = 1
DEFAULT_TCP_PORT = 9000   # source ↔ core
DEFAULT_WS_PORT  = 8765   # core ↔ UI (must match VehicleDataProvider.qml)


# ── Frame type constants ─────────────────────────────────────────────────────

FRAME_HELLO         = "hello"           # source → core
FRAME_TELEMETRY     = "telemetry"       # source → core
FRAME_DTC           = "dtc"             # source → core
FRAME_SET_MODE      = "set_mode"        # core → source
FRAME_QUERY_DTC     = "query_dtc"       # core → source
FRAME_QUERY_PID     = "query_pid"       # core → source
FRAME_PID_RESPONSE  = "pid_response"    # source → core
FRAME_MODE_ERROR    = "mode_error"      # any direction


# ── Operating modes a source may be told to enter ────────────────────────────

MODE_DRIVE      = "drive"
MODE_DIAGNOSTIC = "diagnostic"
MODE_LIVE_SCAN  = "live_scan"
MODE_IDLE       = "idle"

VALID_MODES = (MODE_DRIVE, MODE_DIAGNOSTIC, MODE_LIVE_SCAN, MODE_IDLE)


# ── Telemetry field schema ───────────────────────────────────────────────────
#
# Every telemetry data field is OPTIONAL. The core caches last-known values.
# Each entry maps field name → accepted Python types.

_TELEMETRY_FIELDS: Dict[str, Tuple[type, ...]] = {
    "rpm":           (int,),
    "speed_kph":     (int, float),
    "coolant_c":     (int, float),
    "throttle_pct":  (int, float),
    "engine_load":   (int, float),
    "battery_v":     (int, float),
    "fuel_level":    (int, float),
    "intake_temp_c": (int, float),
}

VALID_FRAME_TYPES = (
    FRAME_HELLO, FRAME_TELEMETRY, FRAME_DTC,
    FRAME_SET_MODE, FRAME_QUERY_DTC, FRAME_QUERY_PID,
    FRAME_PID_RESPONSE, FRAME_MODE_ERROR,
)


# ── Validation ────────────────────────────────────────────────────────────────

def validate_frame(frame: Any) -> Tuple[bool, str]:
    """
    Validate a frame against the contract.

    Returns (True, "") if valid, otherwise (False, "human-readable reason").

    Forward-compatibility rules:
      • Unknown fields at the top level are PERMITTED and ignored.
      • Unknown frame types are REJECTED (a peer sending an unknown
        type indicates a schema mismatch, not a forward extension).
      • Unknown values for `mode` are REJECTED for the same reason.
    """
    if not isinstance(frame, dict):
        return False, "frame must be a JSON object"

    if frame.get("schema") != SCHEMA_VERSION:
        return False, f"schema must be {SCHEMA_VERSION} (got {frame.get('schema')!r})"

    ftype = frame.get("type")
    if not isinstance(ftype, str):
        return False, "frame must have a string `type` field"
    if ftype not in VALID_FRAME_TYPES:
        return False, f"unknown frame type: {ftype!r}"

    if ftype == FRAME_HELLO:
        if not isinstance(frame.get("source_id"), str):
            return False, "hello frame requires string `source_id`"
        if not isinstance(frame.get("source_kind"), str):
            return False, "hello frame requires string `source_kind`"

    elif ftype == FRAME_TELEMETRY:
        ts = frame.get("ts")
        if not isinstance(ts, (int, float)):
            return False, "telemetry frame requires numeric `ts`"
        for field, types in _TELEMETRY_FIELDS.items():
            if field in frame and not isinstance(frame[field], types):
                allowed = "/".join(t.__name__ for t in types)
                return False, f"telemetry field {field!r} must be {allowed}"

    elif ftype == FRAME_DTC:
        codes = frame.get("codes")
        if not isinstance(codes, list):
            return False, "dtc frame requires `codes` list"
        for i, c in enumerate(codes):
            if not isinstance(c, dict):
                return False, f"codes[{i}] must be an object"
            if not isinstance(c.get("code"), str):
                return False, f"codes[{i}].code must be a string"
            if not isinstance(c.get("status"), str):
                return False, f"codes[{i}].status must be a string"

    elif ftype == FRAME_SET_MODE:
        mode = frame.get("mode")
        if mode not in VALID_MODES:
            return False, f"set_mode requires one of {VALID_MODES}"

    elif ftype == FRAME_QUERY_PID:
        if not isinstance(frame.get("pid"), str):
            return False, "query_pid requires string `pid`"

    elif ftype == FRAME_PID_RESPONSE:
        if not isinstance(frame.get("pid"), str):
            return False, "pid_response requires string `pid`"
        if "value" not in frame:
            return False, "pid_response requires `value`"

    elif ftype == FRAME_MODE_ERROR:
        if not isinstance(frame.get("reason"), str):
            return False, "mode_error requires string `reason`"

    # FRAME_QUERY_DTC has no required payload beyond schema/type.
    return True, ""


# ── Frame builder helpers ────────────────────────────────────────────────────

def _base(ftype: str) -> Dict[str, Any]:
    return {"schema": SCHEMA_VERSION, "type": ftype}


def build_hello(source_id: str, source_kind: str, **extra: Any) -> Dict[str, Any]:
    f = _base(FRAME_HELLO)
    f["source_id"]   = source_id
    f["source_kind"] = source_kind
    f.update(extra)
    return f


def build_telemetry(
    ts:            Optional[float] = None,
    rpm:           Optional[int]   = None,
    speed_kph:     Optional[float] = None,
    coolant_c:     Optional[float] = None,
    throttle_pct:  Optional[float] = None,
    engine_load:   Optional[float] = None,
    battery_v:     Optional[float] = None,
    fuel_level:    Optional[float] = None,
    intake_temp_c: Optional[float] = None,
    **extra: Any,
) -> Dict[str, Any]:
    """Build a telemetry frame. Any field left as None is omitted."""
    f = _base(FRAME_TELEMETRY)
    f["ts"] = float(ts) if ts is not None else time.time()
    locals_map = {
        "rpm":           rpm,
        "speed_kph":     speed_kph,
        "coolant_c":     coolant_c,
        "throttle_pct":  throttle_pct,
        "engine_load":   engine_load,
        "battery_v":     battery_v,
        "fuel_level":    fuel_level,
        "intake_temp_c": intake_temp_c,
    }
    for name, value in locals_map.items():
        if value is not None:
            f[name] = value
    f.update(extra)
    return f


def build_dtc(codes: Iterable[Dict[str, str]], **extra: Any) -> Dict[str, Any]:
    """codes: iterable of {"code": "P0300", "status": "active"|"pending"|"stored"}"""
    f = _base(FRAME_DTC)
    f["codes"] = list(codes)
    f.update(extra)
    return f


def build_set_mode(mode: str, **extra: Any) -> Dict[str, Any]:
    f = _base(FRAME_SET_MODE)
    f["mode"] = mode
    f.update(extra)
    return f


def build_query_dtc(**extra: Any) -> Dict[str, Any]:
    f = _base(FRAME_QUERY_DTC)
    f.update(extra)
    return f


def build_query_pid(pid: str, **extra: Any) -> Dict[str, Any]:
    f = _base(FRAME_QUERY_PID)
    f["pid"] = pid
    f.update(extra)
    return f


def build_pid_response(pid: str, value: Any, **extra: Any) -> Dict[str, Any]:
    f = _base(FRAME_PID_RESPONSE)
    f["pid"]   = pid
    f["value"] = value
    f.update(extra)
    return f


def build_mode_error(reason: str, **extra: Any) -> Dict[str, Any]:
    f = _base(FRAME_MODE_ERROR)
    f["reason"] = reason
    f.update(extra)
    return f


# ── Field name list, exposed for tests / introspection ────────────────────────

TELEMETRY_FIELD_NAMES: List[str] = list(_TELEMETRY_FIELDS.keys())
