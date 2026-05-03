# VEYA — Source-to-Core Wire Contract

> **Status:** Phase 2.0, schema version `1`
> **Audience:** ESP32 firmware authors, Python source authors, AI assistants, thesis readers
> **Authoritative source:** `services/veya_core/contract.py` — if this document and the code disagree, the code wins. File a fix.

---

## 1. Purpose

This document specifies the protocol spoken between a **data source** and the **VEYA core**.

A *source* is anything that produces vehicle telemetry: a mock simulator, an ELM327 USB bridge, a future ESP32 firmware over Bluetooth-SPP, or a future custom STM32 + MCP2515 CAN board. From the core's perspective they are interchangeable — they all speak the wire format defined here.

The contract has two distinct halves:

| Half | Where it lives | Audience |
| --- | --- | --- |
| **Source ↔ Core** (this doc) | `contract.py`, `tcp_server.py` | source firmware authors |
| **Core ↔ UI** (legacy) | `ws_server.py`, `core.py:_translate_telemetry` | QML provider only |

Do not confuse the two. The UI WebSocket schema is **frozen** for backwards compatibility with `VehicleDataProvider.qml`. The source-facing contract described here is the one to extend going forward.

---

## 2. Transport

| Property | Value |
| --- | --- |
| Transport | TCP |
| Direction | source connects to core (core is the listener) |
| Default core endpoint | `127.0.0.1:9000` (localhost only) |
| LAN endpoint | `0.0.0.0:9000` when launched with `--listen 0.0.0.0` |
| Encoding | UTF-8 |
| Framing | line-delimited JSON — exactly **one JSON object per line**, terminated by a single `\n` |
| Concurrency | **single source only** — the second concurrent connection receives one `mode_error` frame and is closed immediately |

There is no handshake byte sequence beyond TCP itself. The core accepts any compliant frame on any line. The first frame *should* be a `hello` (see §4.1) but the core will not disconnect a source that omits it; it will just log the source as anonymous.

### 2.1 Why line-delimited JSON, not WebSocket / MQTT / protobuf?

Picking the source-facing transport was a deliberate decision; the rationale is documented here so future contributors can challenge it on its own merits rather than re-deriving it.

- A source will eventually be an **ESP32 over Bluetooth-SPP** or a **microcontroller over UART**. Both expose a stream-of-bytes API; line-delimited JSON parses cleanly on either with no extra dependency.
- WebSocket adds an HTTP upgrade dance and a binary masking layer that buys nothing on a localhost (or a private serial) connection.
- protobuf adds a code-generation step and a schema-compiler dependency on the source side; for a project where one of the targets is a 240 MHz embedded chip with an undergrad firmware author, the readability of JSON is worth more than the ~3× wire-size penalty.
- MQTT requires a broker process and pub/sub semantics we do not need — telemetry is a single-publisher single-subscriber stream.

If/when the bandwidth or CPU cost of JSON becomes load-bearing on the ESP32 path, the right move is a CBOR variant of the same schema, not a new protocol.

---

## 3. Frame envelope

Every frame is a JSON object with at least:

```json
{ "schema": 1, "type": "<frame-type>" }
```

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `schema` | int | yes | Protocol version. **Must be `1`** for this revision. The core rejects any other value. |
| `type` | string | yes | One of the constants in §4. Unknown types are rejected. |

**Forward-compatibility rule:** unknown *fields* at the top level are permitted and ignored. A future revision may add fields without bumping `schema`. Unknown *frame types* are rejected — they indicate a schema mismatch, not a forward extension.

---

## 4. Frame types

There are eight frame types. Three flow from source to core, three from core to source, two are bidirectional.

| Constant (`contract.py`) | Wire `type` | Direction |
| --- | --- | --- |
| `FRAME_HELLO` | `hello` | source → core |
| `FRAME_TELEMETRY` | `telemetry` | source → core |
| `FRAME_DTC` | `dtc` | source → core |
| `FRAME_PID_RESPONSE` | `pid_response` | source → core |
| `FRAME_SET_MODE` | `set_mode` | core → source |
| `FRAME_QUERY_DTC` | `query_dtc` | core → source |
| `FRAME_QUERY_PID` | `query_pid` | core → source |
| `FRAME_MODE_ERROR` | `mode_error` | either |

### 4.1 `hello` — source identifies itself

Sent **once**, immediately after TCP connect, before any telemetry. Identifies the source so the core can log it and the Diagnostic page can later display the connected hardware.

```json
{ "schema": 1, "type": "hello",
  "source_id":   "elm327-001",
  "source_kind": "veya-elm327" }
```

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `source_id` | string | yes | Unique per device. For a single ELM327 setup, `"elm327-001"` is fine. |
| `source_kind` | string | yes | Free-form family identifier. Conventional values: `"veya-mock"`, `"veya-elm327"`, `"veya-esp32"`, `"veya-stm32-can"`. |

A source that omits `hello` will still work — the core treats it as anonymous and does not enforce ordering — but Phase 2.2's Diagnostic page expects this frame.

### 4.2 `telemetry` — periodic vehicle data

The bread and butter of the protocol. Sent at the source's chosen rate (typically 1–20 Hz). **Every data field is optional;** the core caches last-known values and forwards them to the UI.

```json
{ "schema": 1, "type": "telemetry",
  "ts":            1773381689.793,
  "rpm":           2400,
  "speed_kph":     87.3,
  "coolant_c":     91.2,
  "throttle_pct":  34.0,
  "engine_load":   45.1,
  "battery_v":     14.21,
  "fuel_level":    72.0,
  "intake_temp_c": 31.4 }
```

| Field | Type | Required | Range / unit |
| --- | --- | --- | --- |
| `ts` | number | yes | Unix epoch seconds (float OK). The source's clock; the core does not rewrite it. |
| `rpm` | int | optional | engine RPM, 0–~10000 |
| `speed_kph` | int / float | optional | km/h, 0–~300 |
| `coolant_c` | int / float | optional | °C, ~−40 – 130 |
| `throttle_pct` | int / float | optional | %, 0–100 |
| `engine_load` | int / float | optional | %, 0–100 |
| `battery_v` | int / float | optional | V, ~9–16 |
| `fuel_level` | int / float | optional | %, 0–100 |
| `intake_temp_c` | int / float | optional | °C, ~−40 – 90 |

**Omitting a field is fine and correct** if the source has nothing new to report — the core re-broadcasts the last known value. This is what makes the protocol cheap on a vehicle bus that ships some PIDs at 10 Hz and others at 1 Hz.

### 4.3 `dtc` — diagnostic trouble codes

Sent in response to `query_dtc`, or proactively when the source detects a fault.

```json
{ "schema": 1, "type": "dtc",
  "codes": [
    { "code": "P0300", "status": "active"  },
    { "code": "P0420", "status": "pending" }
  ] }
```

| Field | Type | Required |
| --- | --- | --- |
| `codes` | array | yes |
| `codes[].code` | string | yes — the OBD-II DTC, e.g. `"P0300"` |
| `codes[].status` | string | yes — `"active"`, `"pending"`, or `"stored"` |

An empty `codes: []` is a valid frame meaning *no faults*.

### 4.4 `set_mode` — core asks source to switch operating mode

```json
{ "schema": 1, "type": "set_mode", "mode": "drive" }
```

| Field | Type | Required |
| --- | --- | --- |
| `mode` | string | yes — one of `"drive"`, `"diagnostic"`, `"live_scan"`, `"idle"` |

The four modes are advisory hints to the source about what telemetry rate / which PIDs to query:

| Mode | Suggested behavior |
| --- | --- |
| `drive` | full telemetry stream at the source's nominal rate (default) |
| `diagnostic` | reduce telemetry to ~1 Hz so DTC queries / PID probes have bandwidth |
| `live_scan` | full telemetry — same as drive, distinct only so the Diagnostic page can label its UI |
| `idle` | engine-off / parked — source may slow to a trickle to save power |

A source that does not implement a mode should ignore the frame; the core will not enforce compliance.

### 4.5 `query_dtc` — core asks source to read DTCs

```json
{ "schema": 1, "type": "query_dtc" }
```

No payload. The source replies with one `dtc` frame.

### 4.6 `query_pid` / `pid_response` — single-PID probe (Phase 2.2+)

Reserved for the Diagnostic page's "live PID scan" feature. Not yet wired into the UI.

```json
{ "schema": 1, "type": "query_pid", "pid": "0105" }   // core → source

{ "schema": 1, "type": "pid_response",                 // source → core
  "pid":   "0105",
  "value": 91 }
```

`pid` is the OBD-II PID hex code (without the `0x` prefix). `value` is whatever the source decoded — the receiver is expected to know the PID's unit.

### 4.7 `mode_error` — failure / refusal

Either side may send this. The core sends it to the second concurrent source on rejection; a source may send it to surface a hardware fault to the user.

```json
{ "schema": 1, "type": "mode_error",
  "reason": "ELM327 on /dev/ttyUSB0 — vehicle not responding." }
```

| Field | Type | Required |
| --- | --- | --- |
| `reason` | string | yes — short human-readable cause |

The core will translate this into the UI's `mode_error` field on the next legacy frame.

---

## 5. Validation

`contract.validate_frame(frame)` is the single source of truth for what is and isn't a legal frame. It returns `(ok: bool, reason: str)`. The TCP server calls it on every received line and rejects invalid frames *without dropping the connection* — it sends a debug-only `{"type":"error","reason":"…"}` line back to the source and continues.

The validation rules summarised:

1. Frame must be a JSON object.
2. `schema` must equal `1`.
3. `type` must be a known constant (§4 table).
4. Per-type required fields must be present and the right type.
5. Unknown top-level fields are accepted silently.

---

## 6. Example session

```
source                                                            core (TCP :9000)
  │                                                                       │
  ├─ TCP connect ───────────────────────────────────────────────────────►│
  │                                                                       │
  ├─ {"schema":1,"type":"hello","source_id":"esp32-A4","source_kind":"veya-esp32"}\n
  │                                                                       │
  │                                          (core logs "source ready")   │
  │                                                                       │
  ├─ {"schema":1,"type":"telemetry","ts":…,"rpm":820,"speed_kph":0,…}\n  │
  ├─ {"schema":1,"type":"telemetry","ts":…,"rpm":2400,"speed_kph":34.1,…}\n
  │                                                          (10 Hz)      │
  │                                                                       │
  │◄─ {"schema":1,"type":"set_mode","mode":"diagnostic"}\n  ──────────────┤
  │   (source drops to 1 Hz)                                              │
  │                                                                       │
  │◄─ {"schema":1,"type":"query_dtc"}\n  ─────────────────────────────────┤
  │                                                                       │
  ├─ {"schema":1,"type":"dtc","codes":[{"code":"P0300","status":"active"}]}\n
  │                                                                       │
  │◄─ {"schema":1,"type":"set_mode","mode":"drive"}\n  ───────────────────┤
  │   (source resumes 10 Hz)                                              │
  │                                                                       │
  ├─ {"schema":1,"type":"telemetry",…}\n                                  │
  │   …                                                                   │
```

---

## 7. Implementation crib-sheet

### 7.1 Python source

```python
import json, socket, time
from services.veya_core import contract

s = socket.create_connection(("127.0.0.1", contract.DEFAULT_TCP_PORT))
def send(frame):
    s.sendall((json.dumps(frame) + "\n").encode())

send(contract.build_hello("my-source", "veya-custom"))
while True:
    send(contract.build_telemetry(rpm=820, speed_kph=0.0))
    time.sleep(0.1)
```

### 7.2 ESP32 / Arduino source (sketch)

```cpp
// Pseudocode — the ESP32 firmware is not yet written.
WiFiClient tcp;
tcp.connect("192.168.x.y", 9000);
tcp.print("{\"schema\":1,\"type\":\"hello\","
          "\"source_id\":\"esp32-A4\","
          "\"source_kind\":\"veya-esp32\"}\n");

while (true) {
    char buf[160];
    int n = snprintf(buf, sizeof(buf),
        "{\"schema\":1,\"type\":\"telemetry\","
        "\"ts\":%.3f,\"rpm\":%d,\"speed_kph\":%.1f}\n",
        epoch_seconds(), rpm, speed);
    tcp.write(buf, n);
    delay(100);
}
```

The full firmware will need to *also* read commands from `tcp` and react to `set_mode` / `query_dtc`.

---

## 8. What this contract is NOT

- **Not the UI WebSocket schema.** That format (the one with nested `warnings` and the `status: "mock"|"elm"` field) is the legacy UI contract documented in `CLAUDE.md` and emitted only by `ws_server.py`.
- **Not a protocol over CAN bus.** Sources that read CAN must translate it into the JSON frames defined here before sending to the core.
- **Not authenticated or encrypted.** Localhost-only by default. A LAN deployment (`--listen 0.0.0.0`) must rely on network isolation; do not expose port 9000 to the internet.

---

*End of CONTRACT.md*
