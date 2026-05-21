"""
VEYA — Server API helper                              server_client.py
======================================================================

Stdlib-only HTTP client for the VEYA cloud/local server.
Reads base URL from ~/.veya/server_config.json  (report_url key).

Public API
----------
server_check()           GET  <base>/ver            → {'ok', 'error'}
lookup_dtc(code, kind)   GET  <base>/<kind>?dtc=<code>
                                                    → {'ok', 'text', 'error'}
request_report(payload)  POST <base>/report         → {'ok', 'report', 'error', 'message'}
"""
from __future__ import annotations

import json
import logging
import pathlib
import urllib.error
import urllib.request
from typing import Any, Dict

log = logging.getLogger(__name__)

_CONFIG_PATH = pathlib.Path.home() / ".veya" / "server_config.json"


# ── Config ────────────────────────────────────────────────────────────────────

def _read_base_url() -> str:
    """Return report_url from server_config.json, or '' if missing/unset."""
    try:
        if not _CONFIG_PATH.exists():
            return ""
        data = json.loads(_CONFIG_PATH.read_text())
        return str(data.get("report_url", "")).strip()
    except Exception:
        return ""


# ── Public functions ───────────────────────────────────────────────────────────

def server_check() -> Dict[str, Any]:
    """GET <base_url>/ver — returns {'ok': bool, 'error': str|None}"""
    base = _read_base_url()
    if not base:
        return {"ok": False, "error": "server_not_configured"}
    url = base.rstrip("/") + "/ver"
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            # Any 2xx is a success
            return {"ok": True, "error": None}
    except urllib.error.HTTPError as exc:
        error = _extract_error(exc)
        return {"ok": False, "error": error}
    except urllib.error.URLError:
        return {"ok": False, "error": "network_unreachable"}
    except TimeoutError:
        return {"ok": False, "error": "timeout"}


def lookup_dtc(code: str, kind: str) -> Dict[str, Any]:
    """GET <base_url>/<kind>?dtc=<code>

    kind is one of: signification, causes, symptomes, reparation
    Returns {'ok': bool, 'text': str|None, 'error': str|None}
    """
    base = _read_base_url()
    if not base:
        return {"ok": False, "text": None, "error": "server_not_configured"}
    url = base.rstrip("/") + "/" + kind.lstrip("/") + "?dtc=" + urllib.request.quote(code)
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            text = resp.read().decode("utf-8", errors="replace")
            return {"ok": True, "text": text, "error": None}
    except urllib.error.HTTPError as exc:
        error = _extract_error(exc)
        return {"ok": False, "text": None, "error": error}
    except urllib.error.URLError:
        return {"ok": False, "text": None, "error": "network_unreachable"}
    except TimeoutError:
        return {"ok": False, "text": None, "error": "timeout"}


def request_report(payload: Dict[str, Any]) -> Dict[str, Any]:
    """POST <base_url>/report with JSON payload
    Returns {'ok': bool, 'report': dict|None, 'error': str|None, 'message': str}
    """
    base = _read_base_url()
    if not base:
        return {"ok": False, "report": None, "error": "server_not_configured", "message": ""}
    url = base.rstrip("/") + "/report"
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    log.info("[server_client] POST /report payload: %s", json.dumps(payload, ensure_ascii=False))
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                report = json.loads(raw)
            except json.JSONDecodeError:
                return {"ok": False, "report": None, "error": "invalid_response", "message": ""}
            return {"ok": True, "report": report, "error": None, "message": ""}
    except urllib.error.HTTPError as exc:
        try:
            body_text = exc.read().decode("utf-8", errors="replace")
            log.warning("[server_client] POST /report failed: HTTP %d, body=%s", exc.code, body_text)
            data = json.loads(body_text)
            error_code = str(data.get("error") or data.get("detail") or exc.reason or f"HTTP {exc.code}")
            message    = str(data.get("message") or data.get("detail") or error_code)
        except Exception:
            error_code = exc.reason or f"HTTP {exc.code}"
            message    = error_code
        return {"ok": False, "report": None, "error": error_code, "message": message}
    except urllib.error.URLError:
        return {"ok": False, "report": None, "error": "network_unreachable", "message": ""}
    except TimeoutError:
        return {"ok": False, "report": None, "error": "timeout", "message": ""}


# ── Internal helpers ───────────────────────────────────────────────────────────

def _extract_error(exc: urllib.error.HTTPError) -> str:
    """Try to extract a message from the HTTP error response body (JSON),
    falling back to the HTTP reason string."""
    try:
        body = exc.read().decode("utf-8", errors="replace")
        data = json.loads(body)
        # Accept 'error', 'message', or 'detail' keys
        for key in ("error", "message", "detail"):
            if key in data and data[key]:
                return str(data[key])
    except Exception:
        pass
    return exc.reason or f"HTTP {exc.code}"
