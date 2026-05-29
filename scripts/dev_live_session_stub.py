#!/usr/bin/env python3
"""
VEYA — Dev Live Session Stub Server           dev_live_session_stub.py
======================================================================
Minimal asyncio WebSocket server that stands in for the friend's Django
Channels server during offline testing of live_session.py.

Listens on ws://127.0.0.1:9999/ws/obd/

How to run end-to-end:
  Terminal A:  python scripts/dev_live_session_stub.py
  Terminal B:  python -m services.veya_core.live_session \
                   --url ws://127.0.0.1:9999/ws/obd/ [--verbose]

Commands (type in Terminal A, press Enter):
  dtc   — send "read DTC" to all connected clients
             (simulates browser button click relayed by his consumer)
  quit  — shut down cleanly

Expected behaviour:
  - Terminal A prints received telemetry frames (first 120 chars), ~5/s
  - After typing "dtc", Terminal B logs "← read DTC from remote", sends
    esp32_query_dtc to local core, then Terminal A prints dtc_response
"""
import asyncio
import json
import sys
import warnings as _warnings

_warnings.filterwarnings("ignore", category=DeprecationWarning, module="websockets")

try:
    import websockets
except ImportError:
    print("websockets not installed — run: pip install websockets", file=sys.stderr)
    sys.exit(1)

HOST = "127.0.0.1"
PORT = 9999
_clients: set = set()


async def handler(ws: "websockets.ServerConnection") -> None:
    path = getattr(getattr(ws, "request", None), "path", "?")
    peer = getattr(ws, "remote_address", "?")
    _clients.add(ws)
    print(f"[stub] + client connected  addr={peer}  path={path}")
    try:
        async for msg in ws:
            if isinstance(msg, bytes):
                msg = msg.decode("utf-8", errors="replace")
            preview = msg if len(msg) <= 120 else msg[:117] + "..."
            print(f"[stub] recv: {preview}")
    except websockets.ConnectionClosed:
        pass
    finally:
        _clients.discard(ws)
        print(f"[stub] - client disconnected  addr={peer}")


async def stdin_reader() -> None:
    loop = asyncio.get_running_loop()
    print("[stub] commands: dtc | quit")
    while True:
        line: str = await loop.run_in_executor(None, sys.stdin.readline)
        if not line:   # EOF (Ctrl+D)
            break
        cmd = line.strip().lower()
        if cmd == "quit":
            print("[stub] exiting")
            sys.exit(0)
        elif cmd == "dtc":
            if not _clients:
                print("[stub] no clients connected")
                continue
            print(f"[stub] → sending 'read DTC' to {len(_clients)} client(s)")
            for ws in list(_clients):
                try:
                    await ws.send("read DTC")
                except Exception as exc:
                    print(f"[stub] send error: {exc}")
        else:
            print(f"[stub] unknown command: {cmd!r}  (dtc | quit)")


async def main() -> None:
    print(f"[stub] listening on ws://{HOST}:{PORT}/ws/obd/")
    async with websockets.serve(handler, HOST, PORT):
        await stdin_reader()


if __name__ == "__main__":
    asyncio.run(main())
