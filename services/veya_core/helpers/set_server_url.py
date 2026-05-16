#!/usr/bin/env python3
"""CLI helper for managing ~/.veya/server_config.json.

Usage:
  set_server_url.py report <url>   – set the report server URL
  set_server_url.py live   <url>   – set the live-session server URL
  set_server_url.py show           – print current config
  set_server_url.py clear          – clear both URLs
"""
from __future__ import annotations

import json
import pathlib
import sys
from datetime import datetime, timezone

CONFIG_PATH = pathlib.Path.home() / ".veya" / "server_config.json"

DEFAULTS: dict = {
    "report_url":       "",
    "live_session_url": "",
    "last_updated":     "",
}


def _read() -> dict:
    cfg = dict(DEFAULTS)
    if CONFIG_PATH.exists():
        try:
            stored = json.loads(CONFIG_PATH.read_text())
            cfg.update({k: stored[k] for k in DEFAULTS if k in stored})
        except Exception as exc:
            print(f"Warning: could not parse config: {exc}", file=sys.stderr)
    return cfg


def _write(cfg: dict) -> None:
    cfg["last_updated"] = datetime.now(timezone.utc).isoformat()
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2))


def cmd_show() -> None:
    cfg = _read()
    print(f"Config file : {CONFIG_PATH}")
    print(f"report_url  : {cfg['report_url']  or '(not set)'}")
    print(f"live_url    : {cfg['live_session_url'] or '(not set)'}")
    print(f"last_updated: {cfg['last_updated'] or '(never)'}")


def cmd_set_report(url: str) -> None:
    cfg = _read()
    cfg["report_url"] = url
    _write(cfg)
    print(f"report_url set → {url}")


def cmd_set_live(url: str) -> None:
    cfg = _read()
    cfg["live_session_url"] = url
    _write(cfg)
    print(f"live_session_url set → {url}")


def cmd_clear() -> None:
    cfg = _read()
    cfg["report_url"]       = ""
    cfg["live_session_url"] = ""
    _write(cfg)
    print("Both URLs cleared.")


def main() -> None:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)

    verb = args[0]

    if verb == "show":
        cmd_show()
    elif verb == "report":
        if len(args) < 2:
            print("Error: 'report' requires a URL argument.", file=sys.stderr)
            sys.exit(1)
        cmd_set_report(args[1])
    elif verb == "live":
        if len(args) < 2:
            print("Error: 'live' requires a URL argument.", file=sys.stderr)
            sys.exit(1)
        cmd_set_live(args[1])
    elif verb == "clear":
        cmd_clear()
    else:
        print(f"Error: unknown command '{verb}'. Use: report | live | show | clear",
              file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
