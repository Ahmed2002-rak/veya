# VEYA — System Architecture

> **Status:** Phase 3.0c (May 2026)
> **Audience:** anyone touching the Python or QML stack
> **Companion docs:** [`CONTRACT.md`](./CONTRACT.md) (wire protocol), [`MEMORY.md`](./MEMORY.md) (project state & decisions), [`../CLAUDE.md`](../CLAUDE.md) (Claude Code instructions)

---

## 1. The big picture

VEYA splits cleanly into **three processes plus an optional Bluetooth bridge process (`bt_bridge.py`) when an ESP32 source is paired** that talk over **two well-defined wires**:

```
┌──────────────────────────┐                          ┌──────────────────────────┐
│   data source process    │      TCP, JSON-lines     │   veya_core (Python)     │
│  mock_source.py          │ ───────────────────────► │   asyncio orchestrator   │
│  elm327_source.py        │       :9000              │                          │
│  bt_bridge.py            │                          │   ┌──────────────────┐   │
│  (future) STM32+CAN      │                          │   │ TcpSourceServer  │   │
└──────────────────────────┘                          │   └────────┬─────────┘   │
                                                      │            │             │
        ▲                                             │   ┌────────▼─────────┐   │
        │  BT-Classic SPP / RFCOMM                   │   │ translate +      │   │
┌───────┴──────────────────┐                          │   │ cache + warnings │   │
│   ESP32 (firmware)       │                          │   └────────┬─────────┘   │
│  firmware/esp32/         │                          │            │             │
│  veya_esp32_sample.ino   │                          │   ┌────────▼─────────┐   │
└──────────────────────────┘                          │   │ UiWebSocketServer│   │
                                                      │   └────────┬─────────┘   │
                                                      └────────────┼─────────────┘
                                                                   │
                                                                   │ WebSocket, legacy JSON
                                                                   │ :8765
                                                                   ▼
                                                      ┌──────────────────────────┐
                                                      │   veya_ui (Qt6 / QML)    │
                                                      │   Main → StackView       │
                                                      │   Home / Drive / Diag    │
                                                      │   VehicleDataProvider    │
                                                      └──────────────────────────┘
```

**The two wires.** §4 of [`CONTRACT.md`](./CONTRACT.md) defines the **source ↔ core** TCP protocol; the **core ↔ UI** WebSocket protocol is the legacy one that `VehicleDataProvider.qml` already consumes (described in `CLAUDE.md`).

**The processes.** Each can be started, stopped, and tested independently:

| Process | Module | Role |
| --- | --- | --- |
| Source | `services.veya_core.sources.mock_source` (or any other source) | produces telemetry |
| Core | `services.veya_core.core` | translates, caches, broadcasts |
| UI | `ui/build/veya_ui` | renders |
| BT Bridge (optional) | `services.veya_core.bt_bridge` | relays ESP32 RFCOMM frames to TCP :9000; spawned by ws_server.py on successful pair |

---

## 2. Why this shape — Phase 1 → Phase 2.0

### 2.1 Phase 1 (the legacy `obd_service.py`)

```
┌────────────────────────────┐    WebSocket    ┌────────────────┐
│   obd_service.py           │ :8765           │  veya_ui (QML) │
│   ─ MockProvider           │ ───────────────►│                │
│   ─ Elm327Provider         │                 │                │
│   ─ TelemetryServer        │                 │                │
└────────────────────────────┘                 └────────────────┘
```

Single process, single file (≈700 lines), single wire. Worked, but had three growing pains:

1. **No clean place for the ESP32 firmware to plug in.** The "source" was a Python class inside the same process as the WebSocket server. A microcontroller cannot become a `MockProvider` subclass.
2. **Mode switching had to live in the same process as the data producer.** Hot-swapping `MockProvider` ↔ `Elm327Provider` worked but couples concerns that should be independent: orchestration is not the same job as reading PIDs.
3. **Hard to test in isolation.** You could not point a new source at the existing UI without rewriting the wire format, and you could not point the existing UI at a new core without rewriting it too.

### 2.2 Phase 2.0 (this refactor)

The fix is to introduce a **second wire** — between source and core — and let the source live in its own process:

```
source (any process) ──TCP/JSON──► core (Python) ──WebSocket──► UI (Qt)
```

Three concrete benefits:

- **The source is replaceable without touching the UI.** Mock today, ESP32 tomorrow, STM32-CAN next year — they all speak the same TCP frame format.
- **The UI is unchanged.** `VehicleDataProvider.qml` still receives the exact same legacy JSON it always did. The whole refactor is invisible from QML's side.
- **Each component is testable alone.** `nc 127.0.0.1 9000` lets you hand-craft frames into the core. `wscat -c ws://127.0.0.1:8765` lets you observe the UI side. The mock source can be pointed at *any* TCP listener.

Phase 2.0 was deliberately **non-functional from the user's point of view**: the kiosk still boots into the same Drive screen with the same data. The change is purely structural — paying down the architectural debt before Phase 2.1 (DB) and Phase 2.2 (Diagnostic page real DTCs) start needing it.

---

## 3. Layer-by-layer

### 3.1 Layer A — boot (`start_veya.sh`)

Pure bash. On RPi5 boot, `~/.bash_profile` runs this script. It:

1. Parses CLI flags (`--mode`, `--listen`, `--tcp-port`, `--ws-port`, `--hz`).
2. Maps the legacy alias `--mode elm` → `--mode real` for back-compat.
3. Logs to `/home/pfe/veya/logs/kiosk.log`.
4. Kills any process holding port `WS_PORT` (default 8765).
5. Activates `.venv` and launches `python -m services.veya_core.core …`.
6. Polls `127.0.0.1:WS_PORT` for up to 6 s waiting for the WebSocket to open.
7. Launches `ui/build/veya_ui` in the foreground.
8. Kills the core when the UI exits.

The script no longer knows anything about ELM327 specifics — `--elm-port` and `--elm-baud` are silently accepted and ignored for back-compat. The ELM327 source is launched manually (or, eventually, by an `--auto-elm` flag that spawns `elm327_source.py`).

### 3.2 Layer B — core (`services/veya_core/`)

Five Python files, one job each:

| File | LoC | Responsibility |
| --- | --- | --- |
| `contract.py`   | ~250 | wire schema, validators, frame builders |
| `tcp_server.py` | ~210 | accept ONE source, parse line-JSON, forward valid frames |
| `ws_server.py`  | ~170 | speak the legacy JSON to the QML UI, hard-cap 20 Hz |
| `core.py`       | ~415 | orchestrate everything: state machine, mode switching, mock subprocess |
| `__init__.py`   | 0    | package marker |

`core.py` runs the asyncio event loop that owns both servers. The key state machine is:

```
   ┌─────────────┐  set_mode=elm           ┌────────────────────┐
   │             │ ──────────────────────► │                    │
   │   STATE_    │                         │ STATE_REAL_WAITING │
   │   MOCK      │ ◄────────────────────── │  (no source yet)   │
   │             │  set_mode=mock          │                    │
   └──────┬──────┘                         └─────────┬──────────┘
          │                                          │
          │ on start (mode=mock)                     │ source `hello` arrives
          │ → spawn mock_source subprocess           │ → STATE_REAL_CONNECTED
          │                                          │
          ▼                                          ▼
   spawns mock_source.py            ┌──────────────────────────┐
   as a child process               │  STATE_REAL_CONNECTED    │
                                    │  (telemetry flowing)     │
                                    └──────────────────────────┘
```

Three implementation details worth knowing:

- **Single source enforced.** `TcpSourceServer` rejects the second concurrent connection with a `mode_error` frame. Multi-source aggregation is intentionally out of scope.
- **Last-known cache.** The core keeps a per-field cache. If a source sends `telemetry` with only `rpm`, the UI receives the *last known* `speed_kph`/`coolant_c`/etc. This means the UI never has to render `null`.
- **Status-only broadcast.** When the user toggles TEST/REAL on Home, the UI needs the status badge to flip *immediately* — it should not have to wait for the next 100 ms telemetry tick. `core._broadcast_status_only()` resets the 20 Hz throttle gate and emits a frame using cached telemetry but the new `status` value, giving an instant visual confirmation.

### 3.3 Layer C — sources (`services/veya_core/sources/`)

Each source is a **standalone TCP-client script** importing only `services.veya_core.contract`. They share no state with the core process.

**Bluetooth-SPP source lifecycle:** The ESP32 boots and waits for an RFCOMM client. The user taps Pair in BluetoothManager → `ws_server.py` calls `bluetoothctl pair` then spawns `bt_bridge.py` as a detached subprocess. `bt_bridge.py` opens an RFCOMM socket to the ESP32's MAC, then connects to the core TCP listener at :9000 and forwards bytes bidirectionally. From the core's perspective, `bt_bridge.py` is just another TCP source speaking the wire contract. After a successful pair, `ws_server.py` spawns `bt_bridge.py` as a detached subprocess via `subprocess.Popen`. The bridge writes `/tmp/veya_bt_bridge_status.txt` as a heartbeat so `ws_server` can report bridge state to the UI.

| Source | Spawned by | Purpose |
| --- | --- | --- |
| `mock_source.py` | `core.py` (when `mode=mock`) | drive-cycle simulation, behaviour preserved bit-for-bit from the legacy `MockProvider` |
| `elm327_source.py` | manually, by the user | bridges a real ELM327 USB adapter into the wire format |
| `bt_bridge.py` + ESP32 firmware | `ws_server.py` spawns `bt_bridge.py` on successful BT pair; ESP32 connects back via RFCOMM | streams ESP32 telemetry over Bluetooth-SPP relay to TCP :9000 |

**Why standalone scripts and not subclasses:** each source can be debugged with `python -m services.veya_core.sources.mock_source` against any core. It can also be *replaced* by a non-Python implementation (the ESP32 case) without anyone needing to know.

### 3.4 Layer D — UI (`ui/`)

Unchanged from Phase 1. `VehicleDataProvider.qml` still binds to `ws://127.0.0.1:8765` and consumes the exact same legacy JSON shape. The Phase-2.0 refactor was specifically engineered so the UI needed zero edits.

See `CLAUDE.md` for the QML-side specifics (qmldir, navigation pattern, GaugeRing usage).

---

## 4. Data flow — one frame from steering wheel to pixel

This is the worked example of what happens when the engine spins up to 2400 RPM:

```
┌────────────────────────────────────────────────────────────────────┐
│  1. SOURCE — e.g. elm327_source.py running on the Pi               │
│     adapter.sample()  →  {"rpm":2400, "speed_kph":34.1, …}         │
│     contract.build_telemetry(ts=…, **sample)                       │
│         →  {"schema":1,"type":"telemetry","ts":…,"rpm":2400,…}     │
│     writer.write(json + "\n")                                      │
└──────────────────────────────────┬─────────────────────────────────┘
                                   │ TCP :9000  (one line)
┌──────────────────────────────────▼─────────────────────────────────┐
│  2. CORE — TcpSourceServer._handle_client()                        │
│     readline()  →  one bytes object                                │
│     json.loads + contract.validate_frame  →  (True, "")            │
│     await on_frame(frame)                                          │
│         → core._on_source_frame()                                  │
│             ftype=="telemetry"                                     │
│             ui_frame = self._translate_telemetry(frame)            │
│             • merges into self._cache                              │
│             • derives 4 warning booleans (coolant, speed, fuel, V) │
│             • adds legacy "status":"mock"|"elm" field              │
│             await self._ws.broadcast(ui_frame)                     │
└──────────────────────────────────┬─────────────────────────────────┘
                                   │ WebSocket :8765  (legacy JSON)
┌──────────────────────────────────▼─────────────────────────────────┐
│  3. UI — VehicleDataProvider.qml                                   │
│     ws.onTextMessageReceived  →  JSON.parse                        │
│     20 Hz throttle (skip if <50 ms since last update)              │
│     assigns to QML properties: rpm, speedKph, coolantC, …          │
│     and warning booleans                                           │
│     property bindings propagate to GaugeRing.value, etc.           │
└──────────────────────────────────┬─────────────────────────────────┘
                                   │ Qt scene graph
┌──────────────────────────────────▼─────────────────────────────────┐
│  4. RENDER — Drive.qml                                             │
│     GaugeRing.value = VehicleDataProvider.rpm  (= 2400)            │
│     Canvas onPaint  →  arc redraws with new sweep angle            │
│     scene graph commits  →  HDMI scanout                           │
└────────────────────────────────────────────────────────────────────┘
```

Two latency tells worth remembering:

- The 20 Hz UI cap (`UI_BROADCAST_HARD_HZ`) lives in `ws_server.py` and is enforced *before* the WebSocket send. A source running at 100 Hz will not flood the UI; the core drops frames at the gate.
- The `VehicleDataProvider.qml` side has its own 50 ms / 20 Hz throttle as belt-and-braces. Both sides need to stay aligned — if you raise one, raise the other.

---

## 5. Mode switching, end-to-end

The TEST/REAL toggle on Home is the only user-driven control flow that crosses all four layers. Walking through it once explains how the state machine fits together:

```
1. User taps the Home toggle.
   Home.qml  →  VehicleDataProvider.sendModeCommand("elm")
   sends      {"cmd":"set_mode","mode":"elm"}  via WebSocket.
   UI sets    `switching = true` and starts a 5 s safety timer.

2. ws_server.py receives the message in _handle_client().
   Validates mode is "mock"|"elm", awaits on_ui_command(...).

3. core._on_ui_command() runs:
   • UI's "elm" → internal "real" via the legacy mapping.
   • If already in real mode: ignore.
   • Otherwise:
       — Kills mock subprocess (if any).
       — Sets state = STATE_REAL_WAITING (no source yet) or
         STATE_REAL_CONNECTED (a source happens to already be connected).
       — Sends FRAME_SET_MODE("drive") to the source if connected.
       — Calls _broadcast_status_only() to push a frame with the new status NOW.
       — Schedules a 3 s "no source" timeout.

4. UI receives the status-only frame within ~10 ms.
   VehicleDataProvider sees `obj.status === _requestedMode` and clears
   `switching = false`. The toggle UI shows "REAL" steady.

5. If the 3 s timer fires before any source connects:
   core._real_wait_timeout() → broadcasts a frame with mode_error
   "Waiting for external source...". The UI surfaces this in the
   Home page's error pill.

6. When (eventually) the user runs elm327_source.py:
   The TCP connect → hello → core sets state=STATE_REAL_CONNECTED.
   Telemetry flows. The mode_error pill auto-clears after 3 s.
```

The contract between layers here is that **the UI never blocks waiting for a hardware confirmation**. Mode switch is fire-and-forget plus a 5 s safety net; the core acknowledges instantly via the status-only broadcast and only later signals failure if the hardware doesn't materialise.

---

## 6. What is NOT in v3.0c-stable

These are deliberately deferred:

- **No real OBD-II reading on the ESP32.** The reference sketch (`firmware/esp32/veya_esp32_sample.ino`) sends hardcoded telemetry values. Actual CAN/ISO 9141 reading is Phase 3.1 — Ingéniorat hardware track.
- **No server integration.** Get Report POST and Live Session WebSocket to the remote server are not implemented (Phase 3.2). The server URL is configurable and stored, but the HTTP/WS calls are placeholders.
- **No SQLite session logging.** Planned for Phase 3.4.
- **No DTC display on the Diagnostic page UI.** The `dtc` wire frame is defined in `contract.py` and the Diagnostic.qml placeholder exists, but they are not connected (Phase 3.5).
- **No multi-source aggregation.** Intentional — see `CONTRACT.md` §3.3.
- **No security layer on TCP :9000.** Localhost-only by default; LAN deployments rely on network isolation.

---

## 7. Recent additions through v3.0c

A condensed history of what each post-2.0 phase added, for contributors joining mid-project.

- **Phase 2.1:** 1024×600 visual fixes, warning telltales, animated road silhouette, RPM label cleanup, Qt6Svg linked.
- **Phase 2.2a:** User-facing Diagnostic page redesign, hidden DevDiagnostic developer gesture, Report and LiveSession placeholder screens, repo hygiene pass.
- **Phase 2.2b:** WS-backed UserProfile save/load, first-launch onboarding flow, custom QML on-screen keyboard, Settings/Wi-Fi/Diagnostic placeholder pages scaffolded.
- **Phase 3.0a:** Wi-Fi backend via WS commands (`wifi_scan`, `wifi_status`, `wifi_connect`, `wifi_disconnect`), Home Wi-Fi indicator, server URL config helper (`set_server_url.py`), no-source banner on Drive.
- **Phase 3.0b:** Bluetooth bridge (`bt_bridge.py`), BT manager UI (`bt_scan`, `bt_status`, `bt_pair`, `bt_unpair`, `bt_bridge_status`, `bt_pairing_mode` WS commands), `bt-agent` systemd service, `setup_bluetooth.sh` first-run script, three-state banner on Drive, BT indicator on Home.
- **Phase 3.0c:** ESP32 reference firmware with Class-of-Device fix for modern bluez, Python stdlib `AF_BLUETOOTH` / `BTPROTO_RFCOMM` socket in `bt_bridge` (replacing dead pybluez), pair sequencing with `bluetoothctl` + `hcitool` fallback for BR/EDR inquiry, end-to-end pipeline verified on real hardware.

---

*End of ARCHITECTURE.md*
