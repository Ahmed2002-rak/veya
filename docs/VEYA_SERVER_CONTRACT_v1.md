# VEYA Server Contract v1

> Placeholder — the user will replace this content with the actual server contract document.

This file documents the HTTP API contract between the VEYA dashboard and the remote diagnostic server.

## Endpoints

- `GET /ver` — health check
- `GET /<kind>?dtc=<code>` — DTC lookup (kind: signification, causes, symptomes, reparation)
- `POST /report` — generate diagnostic report

## Status

Contract document pending — see the server team for the full specification.
