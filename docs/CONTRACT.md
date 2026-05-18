# VEYA — Source-to-Core Wire Contract

> **Status:** Phase 3.0e, schema version `1`
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

| Constant (`contract.py`) | Wire `type` | Direction | Notes |
|---|---|---|---|
| `FRAME_HELLO` | `hello` | source → core | Once on connect |
| `FRAME_TELEMETRY` | `telemetry` | source → core | Continuous, 5–10 Hz |
| `FRAME_DTC` | `dtc` | source → core | Reply to query_dtc OR unsolicited |
| `FRAME_CLEAR_DTC_RESULT` | `clear_dtc_result` | source → core | Reply to clear_dtc (NEW) |
| `FRAME_MILEAGE_RESPONSE` | `mileage_response` | source → core | Reply to query_mileage (NEW) |
| `FRAME_PID_RESPONSE` | `pid_response` | source → core | RESERVED — not used in current UI |
| `FRAME_QUERY_DTC` | `query_dtc` | core → source | Pi requests DTC scan |
| `FRAME_CLEAR_DTC` | `clear_dtc` | core → source | Pi requests DTC wipe (NEW) |
| `FRAME_QUERY_MILEAGE` | `query_mileage` | core → source | Pi requests odometer (NEW) |
| `FRAME_QUERY_PID` | `query_pid` | core → source | RESERVED — not used in current UI |
| `FRAME_MODE_ERROR` | `mode_error` | either | Failure surface |

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

### 4.4 `set_mode` — DEPRECATED

**DEPRECATED — kept for backward compatibility.**

The `set_mode` verb was part of the original Phase 2.0 contract. After hardware verification in Phase 3.0c, the ESP32 design was simplified: the firmware streams telemetry continuously at 5–10 Hz with no mode switching. The Pi sets the user-facing context (Drive screen, Live Session, Dev) on its own side; the ESP32 doesn't need to know.

The `set_mode` handler remains in `ws_server.py` to preserve backward compatibility with `VehicleDataProvider.qml`'s TEST/REAL toggle (which sends `{"cmd":"set_mode","mode":"mock"|"elm"}`). This is a UI-layer command, NOT a source-layer command, despite the historical naming overlap.

Future contract revisions may remove the source-layer `set_mode` entirely. New firmware should NOT implement it.

### 4.5 `clear_dtc` (Pi → ESP32) — Phase 3.0e

```json
{ "schema": 1, "type": "clear_dtc" }
```

No payload. The ESP32 should issue OBD-II Mode 04 to wipe stored codes and Freeze Frame data, then send `clear_dtc_result`.

### 4.6 `clear_dtc_result` (ESP32 → Pi) — Phase 3.0e

```json
{ "schema": 1, "type": "clear_dtc_result", "ok": true, "cleared_count": 3 }
```

On failure:
```json
{ "schema": 1, "type": "clear_dtc_result", "ok": false, "error": "ECU rejected Mode 04 (engine running)" }
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `ok` | bool | yes | true if Mode 04 succeeded |
| `cleared_count` | int | optional | how many codes were removed (if ECU reports it) |
| `error` | string | optional | only when `ok: false` — short human-readable reason |

### 4.7 `query_mileage` (Pi → ESP32) — Phase 3.0e

```json
{ "schema": 1, "type": "query_mileage" }
```

No payload. The ESP32 should read OBD-II Mode 01 PID `0xA6` (or fall back to manufacturer-specific PID) and send `mileage_response`.

### 4.8 `mileage_response` (ESP32 → Pi) — Phase 3.0e

```json
{ "schema": 1, "type": "mileage_response", "km": 142385, "source_pid": "A6" }
```

On failure:
```json
{ "schema": 1, "type": "mileage_response", "ok": false, "error": "PID A6 not supported by ECU" }
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `km` | int | yes (on success) | total odometer reading in kilometers |
| `source_pid` | string | optional | which OBD-II PID was used (debug aid) |
| `ok` | bool | optional | implicit true if `km` present; explicit false on failure |
| `error` | string | optional | only when read fails |

### 4.9 `query_dtc` — core asks source to read DTCs

```json
{ "schema": 1, "type": "query_dtc" }
```

No payload. The source replies with one `dtc` frame.

### 4.10 `query_pid` / `pid_response` — single-PID probe (RESERVED)

Reserved for the Diagnostic page's "live PID scan" feature. Not yet wired into the UI.

```json
{ "schema": 1, "type": "query_pid", "pid": "0105" }   // core → source

{ "schema": 1, "type": "pid_response",                 // source → core
  "pid":   "0105",
  "value": 91 }
```

`pid` is the OBD-II PID hex code (without the `0x` prefix). `value` is whatever the source decoded — the receiver is expected to know the PID's unit.

### 4.11 `mode_error` — failure / refusal

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

The full firmware will need to *also* read commands from `tcp` and react to `query_dtc` / `clear_dtc` / `query_mileage` (see §10). The `set_mode` command is deprecated — new firmware should NOT implement it.

---

## 8. What this contract is NOT

- **Not the UI WebSocket schema.** That format (the one with nested `warnings` and the `status: "mock"|"elm"` field) is the legacy UI contract documented in `CLAUDE.md` and emitted only by `ws_server.py`.
- **Not a protocol over CAN bus.** Sources that read CAN must translate it into the JSON frames defined here before sending to the core.
- **Not authenticated or encrypted.** Localhost-only by default. A LAN deployment (`--listen 0.0.0.0`) must rely on network isolation; do not expose port 9000 to the internet.

---

## Bluetooth Transport

### Protocol
- Bluetooth-Classic SPP (Serial Port Profile) via RFCOMM
- Default RFCOMM channel: 1
- The ESP32 advertises a BT-Classic name (prefix "VEYA-OBD-" recommended for easy filtering in BluetoothManager scans, but any name works)

### Pairing Flow
1. ESP32 starts in pairable/discoverable mode (Arduino BluetoothSerial does this by default)
2. The Pi requires `bt-agent --capability=NoInputNoOutput` running as a systemd service (see `scripts/setup_bluetooth.sh`). Without it, bluez refuses pairing requests because there is no D-Bus agent to confirm them.
3. Pi's BluetoothManager UI: user taps Refresh → `helpers/bluetooth.py` runs `hcitool scan` for a raw BR/EDR inquiry (bluez filtered scan misses BT-Classic devices) → ESP32 appears in Available Devices
4. User taps Pair → ws_server invokes `bluetooth.pair` (bluetoothctl pair + trust + connect, with scan_bredr mode enabled during the pair window)
5. On successful pair → ws_server writes MAC to `~/.veya/bt_config.json`
6. ws_server spawns `bt_bridge.py` as a detached subprocess via `subprocess.Popen`
7. `bt_bridge.py` opens RFCOMM socket to ESP32 MAC, channel 1; writes `/tmp/veya_bt_bridge_status.txt` as a heartbeat
8. ESP32 sends hello frame upon receiving SPP client → bridge forwards to TCP :9000
9. ESP32 sends telemetry frames at its own rate → bridge forwards each as a line-delimited JSON frame

### Required ESP32 Behaviour
- Send EXACTLY ONE hello frame within 500 ms of detecting a connected SPP client:
  `{"schema":1,"type":"hello","source_id":"<id>","source_kind":"veya-esp32","firmware":"<version>"}`
- Then send telemetry frames at any rate up to 20 Hz, using the telemetry schema defined in §4.2.
- All frames are line-delimited JSON — newline terminator required.
- If the SPP client disconnects, return to listening mode. Re-send hello on next connect.

### Pi-side Components

| Component | Role |
| --- | --- |
| `services/veya_core/helpers/bluetooth.py` | scan (via `hcitool scan` for BR/EDR inquiry), pair (via `bluetoothctl` with `scan_bredr` + scan-during-pair), unpair, `is_device_in_range` |
| `services/veya_core/bt_bridge.py` | opens RFCOMM socket using Python stdlib `AF_BLUETOOTH` + `BTPROTO_RFCOMM` (no pybluez), forwards bytes bidirectionally to TCP :9000, writes status heartbeat to `/tmp/veya_bt_bridge_status.txt` |
| `services/veya_core/ws_server.py` | WS command handlers for `bt_scan`, `bt_status`, `bt_pair`, `bt_unpair`, `bt_disconnect`, `bt_bridge_status`, `bt_pairing_mode`; spawns `bt_bridge` after successful pair; writes `~/.veya/bt_config.json` |
| `scripts/setup_bluetooth.sh` | First-time Pi setup: installs `bluez` + `bluez-tools`, registers `bt-agent` systemd service, adds `pfe` user to `bluetooth` group |

### Reference Implementation
See `firmware/esp32/veya_esp32_sample.ino` — a minimal sketch that proves the pipeline end-to-end.
Replace with real OBD-reading code by hooking into `setup()` / `loop()` as commented in the sketch.

---

## Pi ↔ Server Transport

**RESERVED — Phase 3.2. This contract is not yet implemented.**

The Pi ↔ Server protocol will define:

- **Get Report:** POST to `<server_url>/report` with session data; expects a diagnostic report response.
- **Live Session:** WebSocket to `<server_url>/live-session` for real-time expert connection.
- Authentication mechanism (token-based, TBD).
- What payload structure the server expects.
- What response structure the Pi expects.

For now, server URLs are configurable via `python3 services/veya_core/helpers/set_server_url.py report <url>` and live in `~/.veya/server_config.json`. The dashboard's `ReportScreen` and `LiveSessionScreen` read this config but the actual POST/WS calls are not yet implemented.

When this section is filled in, it will follow the same pattern as the Bluetooth Transport section above: protocol description, frame formats, lifecycle.

---

## 10. User action → Command sequence — Phase 3.0e

| User action on Pi dashboard | Pi sends to ESP32 | ESP32 reply |
|---|---|---|
| BT pair completes | — | `hello` on SPP connect |
| Any time after hello | — | continuous `telemetry` at 5–10 Hz |
| User enters Drive | — | (already streaming) |
| User taps "Get Report" | `query_dtc` | `dtc` once |
| User taps "Start Live Session" | `query_dtc` | `dtc` once |
| Expert (via server) clicks "Clear DTCs" | `clear_dtc` | `clear_dtc_result` |
| Expert requests new DTC scan | `query_dtc` | `dtc` |
| User enters DevDiagnostic (5-tap gesture) | — | (already streaming) |
| User taps "Read DTCs" in Dev | `query_dtc` | `dtc` |
| User taps "Clear DTCs" in Dev | `clear_dtc` | `clear_dtc_result` |
| User taps "Read Mileage" in Dev | `query_mileage` | `mileage_response` |

---

## Recent additions

- **Phase 3.0c** added the Bluetooth Transport section above. The wire frame format (line-delimited JSON, schema `1`) is unchanged — only the physical transport from source to core changed (BT-Classic SPP relayed by `bt_bridge.py` instead of direct TCP).
- **Phase 3.0e** locked the ESP32 command protocol. Four new frame types added: `clear_dtc` (Pi→ESP32), `clear_dtc_result` (ESP32→Pi), `query_mileage` (Pi→ESP32), `mileage_response` (ESP32→Pi). The `set_mode` source-layer verb is deprecated — ESP32 streams telemetry continuously with no mode switching. Three new UI WS commands added (`esp32_query_dtc`, `esp32_clear_dtc`, `esp32_query_mileage`) that route Pi-side button presses through core.py to the ESP32 over TCP/BT.
- The Pi ↔ UI WebSocket layer added several new command verbs (`save_profile`, `load_profile`, `wifi_*`, `bt_*`, `bt_pairing_mode`) but these are orthogonal to the source contract — they live on the UI WS layer, not the source TCP layer.

---

*End of CONTRACT.md*
