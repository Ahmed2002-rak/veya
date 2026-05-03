"""
VEYA — TCP Source Server                                tcp_server.py
=====================================================================

Listens for ONE data source connection (mock subprocess, ELM327 bridge,
ESP32-via-Bluetooth bridge, …) on a TCP socket. Reads newline-delimited
JSON frames, validates them via the contract, and forwards each valid
frame to a callback.

Concurrent sources are rejected: the second connection receives a
`mode_error` frame and is closed immediately. Multi-source aggregation
is intentionally out of scope for Phase 2.0.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Awaitable, Callable, Dict, Optional

from . import contract


log = logging.getLogger(__name__)

FrameCallback = Callable[[Dict[str, Any]], Awaitable[None]]


class TcpSourceServer:
    """
    Single-source asyncio TCP server.

    Construction:
        TcpSourceServer(host, port, on_frame)

    The `on_frame` coroutine is awaited for every valid frame received
    from the connected source.
    """

    def __init__(
        self,
        host: str,
        port: int,
        on_frame: FrameCallback,
    ) -> None:
        self.host = host
        self.port = port
        self._on_frame = on_frame

        self._server: Optional[asyncio.base_events.Server] = None
        self._writer: Optional[asyncio.StreamWriter] = None
        self._peer:   Optional[str] = None
        self._source_id:   Optional[str] = None
        self._source_kind: Optional[str] = None
        self._lock = asyncio.Lock()

    # ── Connection state ─────────────────────────────────────────────────────

    @property
    def connected(self) -> bool:
        return self._writer is not None

    @property
    def source_id(self) -> Optional[str]:
        return self._source_id

    @property
    def source_kind(self) -> Optional[str]:
        return self._source_kind

    # ── Lifecycle ────────────────────────────────────────────────────────────

    async def start(self) -> None:
        self._server = await asyncio.start_server(
            self._handle_client, self.host, self.port
        )
        log.info("[tcp] listening on %s:%d", self.host, self.port)

    async def stop(self) -> None:
        if self._writer is not None:
            try:
                self._writer.close()
                await self._writer.wait_closed()
            except Exception:
                pass
            self._writer = None
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None
        log.info("[tcp] stopped")

    # ── Outbound: send a frame to the connected source ───────────────────────

    async def send_to_source(self, frame: Dict[str, Any]) -> bool:
        """
        Send a frame (e.g. set_mode, query_dtc) to the connected source.
        Returns True on success, False if no source is connected or the
        write failed.
        """
        async with self._lock:
            writer = self._writer
            if writer is None:
                log.warning("[tcp] send_to_source: no source connected (frame=%s)",
                            frame.get("type"))
                return False
            try:
                payload = (json.dumps(frame, separators=(",", ":")) + "\n").encode("utf-8")
                writer.write(payload)
                await writer.drain()
                return True
            except (ConnectionError, OSError) as exc:
                log.warning("[tcp] send_to_source failed: %s", exc)
                return False

    # ── Per-connection handler ───────────────────────────────────────────────

    async def _handle_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        peer = writer.get_extra_info("peername")
        peer_str = f"{peer[0]}:{peer[1]}" if peer else "?"

        # Reject concurrent sources
        if self._writer is not None:
            log.warning("[tcp] reject second source from %s (already have %s)",
                        peer_str, self._peer)
            try:
                err = contract.build_mode_error(
                    "another source is already connected"
                )
                writer.write((json.dumps(err) + "\n").encode("utf-8"))
                await writer.drain()
            except Exception:
                pass
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
            return

        self._writer = writer
        self._peer   = peer_str
        log.info("[tcp] + source connected from %s", peer_str)

        try:
            while True:
                line = await reader.readline()
                if not line:
                    break  # EOF
                line = line.strip()
                if not line:
                    continue

                try:
                    frame = json.loads(line)
                except json.JSONDecodeError as exc:
                    await self._send_error(writer, f"invalid JSON: {exc}")
                    continue

                ok, err = contract.validate_frame(frame)
                if not ok:
                    log.warning("[tcp] reject frame from %s: %s", peer_str, err)
                    await self._send_error(writer, err)
                    continue

                ftype = frame["type"]
                if ftype == contract.FRAME_HELLO:
                    self._source_id   = frame.get("source_id")
                    self._source_kind = frame.get("source_kind")
                    log.info("[tcp] hello: source_id=%s source_kind=%s",
                             self._source_id, self._source_kind)

                # Forward every valid frame (including hello) to the core.
                try:
                    await self._on_frame(frame)
                except Exception:
                    log.exception("[tcp] on_frame callback raised")

        except (ConnectionError, OSError) as exc:
            log.info("[tcp] connection error from %s: %s", peer_str, exc)
        except asyncio.CancelledError:
            raise
        finally:
            log.info("[tcp] - source disconnected (%s)", peer_str)
            self._writer = None
            self._peer   = None
            self._source_id   = None
            self._source_kind = None
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    @staticmethod
    async def _send_error(writer: asyncio.StreamWriter, reason: str) -> None:
        """
        Send an error frame to the source without disconnecting.
        Uses a minimal {"type":"error","reason":...} envelope (NOT
        validated by contract.validate_frame — this is debug-only).
        """
        try:
            err = {"schema": contract.SCHEMA_VERSION, "type": "error", "reason": reason}
            writer.write((json.dumps(err) + "\n").encode("utf-8"))
            await writer.drain()
        except Exception:
            pass
