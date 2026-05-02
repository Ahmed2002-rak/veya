# VEYA Dashboard — Complete Architecture Document

> Generated: April 2026  
> Branch: `feature/holiday-work`  
> Last stable commit: `18c0977` — "VEYA stable version - WebSocket working - dashboard functional"

---

## 1. Project Overview

### What VEYA Is

VEYA is a fullscreen automotive diagnostic dashboard running on a **Raspberry Pi 5** in kiosk mode. It provides real-time vehicle telemetry (speed, RPM, coolant temperature, battery voltage, fuel level, throttle position, engine load, intake air temperature, and warning flags) sourced either from a realistic mock simulation or from a real ELM327 OBD-II USB adapter.

The system is a **dual academic project**:
- **Ingéniorat stream** (Ahmed Khodhir REZIG): custom OBD-II/CAN hardware (STM32 + MCP2515 PCB — not yet built)
- **Master stream** (Sid Ahmed LAKEHAL): software stack, analytics, and the prototype being documented here

It is also intended as a **startup prototype** for a vehicle intelligence product.

### End-to-End Flow (Today)

```
Boot (bash_profile)
  └─► start_veya.sh
        ├─► obd_service.py  ──── WebSocket ──► VehicleDataProvider.qml
        │     MockProvider                           (Qt singleton)
        │     Elm327Provider (optional)                    │
        │                                           QML property bindings
        └─► veya_ui (Qt binary)                           │
              Main.qml (ApplicationWindow)          Drive.qml, Home.qml
              StackView navigation                  GaugeRing, MiniMetric, ThinBar
```

### Hardware

| Component | Detail |
|---|---|
| Board | Raspberry Pi 5 |
| OS | Raspberry Pi OS (Linux 6.12 kernel, GCC 14.2) |
| Display | HDMI display (resolution not yet verified in code) |
| Input | Keyboard (Ctrl+Shift+Q to quit), mouse/touch |
| OBD adapter | ELM327 USB on `/dev/ttyUSB0` (optional, not always present) |
| CAN hardware | STM32 + MCP2515 custom PCB — **not yet built** |

### Deployment Model

- On RPi5 boot, `~/.bash_profile` calls `start_veya.sh`
- Qt UI runs fullscreen frameless (`Window.FullScreen` + `Qt.FramelessWindowHint`)
- No window manager; display via linuxfb or X11 depending on session
- All logs go to `/home/pfe/veya/logs/`

---

## 2. Full Directory Tree

```
/home/pfe/veya/
│
├── CLAUDE.md                          ← Project instructions for Claude Code (AI context file)
├── VEYA_DASHBOARD_ARCHITECTURE.md     ← This document
├── .gitignore                         ← Excludes build/, .venv/, logs/, *.log, Qt artifacts
│
├── start_veya.sh                      ← MAIN ENTRY POINT: orchestrates backend + UI launch
├── start_mock.sh                      ← Minimal dev shortcut: activates venv, runs obd_service.py
├── start_mock.sh.backup               ← Identical to start_mock.sh (redundant backup)
│
├── services/
│   └── obd_service/
│       └── obd_service.py             ← Python WebSocket server: MockProvider + Elm327Provider
│
├── ui/
│   ├── CMakeLists.txt                 ← Qt6 CMake build: defines veya_ui executable + QML module
│   ├── src/
│   │   └── main.cpp                   ← C++ entry point: creates QGuiApplication + QQmlEngine
│   └── qml/
│       ├── qmldir                     ← QML module manifest: registers singleton + GaugeRing
│       ├── Main.qml                   ← ApplicationWindow: fullscreen shell + StackView root
│       ├── Home.qml                   ← Landing page: 3 profile buttons + TEST/REAL mode toggle
│       ├── Drive.qml                  ← Live dashboard: 3-column telemetry layout
│       ├── Drive.qml.backup           ← Old Qt5-style Drive layout (kept for reference)
│       ├── Diagnostic.qml             ← Diagnostic page: placeholder UI, no real DTC logic
│       ├── providers/
│       │   ├── VehicleDataProvider.qml        ← WebSocket singleton: all telemetry + reconnect
│       │   └── VehicleDataProvider.qml.backup ← Old version (no extended fields, no dataMode)
│       └── components/
│           └── GaugeRing.qml          ← Canvas arc gauge component (reusable)
│
├── external_ui/
│   └── Modern-Car-Dashboard/          ← Reference Qt5 project (NOT used in VEYA build)
│       ├── Car_5.pro                  ← Qt5 .pro file (qmake, incompatible with VEYA's CMake)
│       ├── main.qml                   ← Qt5 dashboard UI (not integrated)
│       ├── SideGauge.qml              ← Qt5 gauge (not integrated)
│       ├── MyButton.qml               ← Qt5 button component (not integrated)
│       ├── icons/                     ← SVG/PNG icon assets
│       └── img/                       ← Background/needle/dial images
│
└── logs/                              ← Runtime logs (gitignored)
    ├── kiosk.log                      ← start_veya.sh execution log
    ├── obd_service.log                ← Python backend stdout/stderr
    ├── veya_ui.log                    ← Qt QML console output
    ├── mock_data.log                  ← (empty / unused)
    └── xinit_debug.log                ← X11 session debug (if applicable)
```

---

## 3. Technology Stack

### UI Layer

| Item | Detail |
|---|---|
| Framework | Qt 6 (exact version: system Qt6 on RPi5) |
| Language | QML (unversioned Qt6 imports in all current files) |
| Qt modules | `QtQuick`, `QtQuick.Controls`, `QtQuick.Layouts`, `QtWebSockets` |
| Rendering | Hardware-accelerated Canvas2D for gauge arcs; QML scene graph for everything else |
| Font | DejaVu Sans (system font, always available on RPi OS) |
| Color palette | Dark theme: `#0B0F14` background, accent colors `#4DD2FF` (cyan), `#7CFF4A` (green), `#B788FF` (violet), `#FF4D6D` (warning red), `#FFD84D` (amber) |

### Backend Layer

| Item | Detail |
|---|---|
| Language | Python 3.13.5 |
| Runtime | CPython, venv at `/home/pfe/veya/.venv` |
| Key library | `websockets` 16.0 (async WebSocket server) |
| Concurrency | `asyncio` (single event loop, `run_in_executor` for blocking OBD queries) |
| OBD library | `python-obd` — **NOT installed** in venv (must `pip install obd` before ELM mode works) |
| Data model | Python `dataclasses` (`Telemetry`, `TelemetryProvider`) |

### Build System

| Item | Detail |
|---|---|
| System | CMake 3.16+ |
| C++ standard | C++17 |
| Qt tooling | `qt_standard_project_setup()`, `qt_add_executable()`, `qt_add_qml_module()` |
| QML module URI | `Veya` version `1.0` |
| Binary output | `ui/build/veya_ui` |
| Build command | `cd ui && mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Release && make -j4` |
| Linked libs | `Qt6::Core`, `Qt6::Gui`, `Qt6::Qml`, `Qt6::Quick`, `Qt6::WebSockets` |

### Runtime Environment

| Item | Detail |
|---|---|
| OS | Raspberry Pi OS (Debian-based, Linux 6.12.47) |
| Shell | bash |
| Display | Kiosk mode; `Window.FullScreen` + `Qt.FramelessWindowHint` (no WM needed) |
| Env vars | Standard Qt env; no custom vars set in start_veya.sh |
| WebSocket | `ws://127.0.0.1:8765` (loopback only, not exposed externally) |
| Exit | `Ctrl+Shift+Q` (caught by `Keys.onPressed` in `Main.qml`) |

### Languages Present

| Language | Files | Role |
|---|---|---|
| QML | `*.qml` (7 active + 2 backups) | UI, navigation, data binding |
| Python 3 | `obd_service.py` | Backend telemetry server |
| C++ | `main.cpp` | Qt application bootstrap |
| CMake | `CMakeLists.txt` | Build system |
| Bash | `start_veya.sh`, `start_mock.sh` | Orchestration scripts |

---

## 4. Architecture Layers

### Layer 1 — Boot & Orchestration (`start_veya.sh`)

**Responsibility:** Start the Python backend, wait for the WebSocket port to open, then launch the Qt binary. Kill stale backend processes on restart.

**Files:** `start_veya.sh`, `start_mock.sh`

**Sequence:**
1. Parse CLI args (`--mode`, `--elm-port`, `--elm-baud`, `--hz`)
2. Redirect stdout/stderr to `logs/kiosk.log`
3. Kill any existing process bound to `127.0.0.1:8765` via `ss + awk`
4. `source .venv/bin/activate`
5. Launch `obd_service.py $OBD_ARGS` in background → capture PID
6. Poll `127.0.0.1:8765` every 0.5s (max 12 attempts = 6s) using Python `socket`
7. Launch `ui/build/veya_ui` in foreground
8. On UI exit → kill backend PID

**Current state:** DONE. One historical awk syntax error seen in logs (since fixed). WS readiness poll sometimes times out on RPi5 before backend is ready (non-fatal; UI launches anyway and auto-reconnects).

---

### Layer 2 — Qt/QML Presentation (`Main.qml`, pages)

**Responsibility:** Fullscreen application window, background styling, global key handler, StackView navigation host.

**Files:** `Main.qml`, `Home.qml`, `Drive.qml`, `Diagnostic.qml`

**Key design decisions:**
- `ApplicationWindow` in `Main.qml` is the only window; it owns the `StackView`
- Background has a dark gradient + 70 randomly positioned semi-transparent dots (star field effect)
- `Ctrl+Shift+Q` exits via `Keys.onPressed` on a focused `Item` (reliable across Qt versions)
- All pages are `Page` items (not `Item`) — best practice for StackView to avoid anchor conflicts

**Current state:** DONE for Home and Drive. Diagnostic is a placeholder.

---

### Layer 3 — Navigation System

**Pattern:** Explicit `nav` property passing.

```qml
// Main.qml
StackView { id: stack; initialItem: Home { nav: stack } }

// Pushing (Home.qml):
root.nav.push(Qt.resolvedUrl("Drive.qml"), { nav: root.nav })

// Popping (Drive.qml):
root.nav.pop()
```

**Rule:** Never use `StackView.view` — `nav` is always passed explicitly as a property. This avoids timing issues where `StackView.view` is null during item construction.

**Historical bug:** Logs show `TypeError: Cannot read property 'push' of null` on `Home.qml:242` in older builds. This is the old `StackView.view` pattern — the explicit `nav` prop fixes it. Not present in the current codebase.

**Current state:** DONE.

---

### Layer 4 — Data/Provider Layer (`VehicleDataProvider.qml`)

**Responsibility:** Single WebSocket client for the entire UI. All telemetry is stored as QML properties here. Pages bind declaratively. Handles reconnection, UI throttling (20 Hz cap), mode switching, and error reporting.

**Files:** `providers/VehicleDataProvider.qml` (registered as `pragma Singleton` in `qmldir`)

**Access pattern:**
```qml
import Veya 1.0
// then use directly:
VehicleDataProvider.rpm
VehicleDataProvider.speedKph
VehicleDataProvider.sendModeCommand("elm")
```

**Reconnect:** On WebSocket close, a 1-second `Timer` restarts `ws.active = true`.

**UI throttle:** Frames are dropped if `Date.now() - _lastUiUpdateMs < 50ms` (caps at 20 Hz regardless of backend Hz).

**Current state:** DONE. Full implementation with all extended fields, `dataMode`, `anyWarning`, `sendModeCommand()`.

---

### Layer 5 — Backend Service (`obd_service.py`)

**Responsibility:** WebSocket server on `127.0.0.1:8765`. Produces telemetry frames at a configurable rate. Supports live mode switching between mock and ELM327 without restarting.

**Files:** `services/obd_service/obd_service.py`

**Classes:**

| Class | Role |
|---|---|
| `Telemetry` | Dataclass — the JSON wire format |
| `TelemetryProvider` | Abstract base class |
| `_DriveCycle` | State machine: idle → city_accel → city_cruise → decel → highway → decel |
| `MockProvider` | Realistic mock: warmup, fuel drain, battery sag, heat soak |
| `Elm327Provider` | Real OBD-II via `python-obd`; queries 8 PIDs; runs sync in executor |
| `TelemetryServer` | asyncio WebSocket server; manages client set; broadcast loop; command queue |

**Default rates:** mock = 10 Hz, elm = 4 Hz (configurable via `--hz`)

**Mode switch:** UI sends `{"cmd":"set_mode","mode":"elm"}` over WS → `TelemetryServer._cmdq` drains it → `_handle_set_mode()` stops old provider, starts new one. On failure, reverts to mock and sends a one-shot `mode_error` frame.

**Current state:** DONE for mock + mode switching infrastructure. ELM327 provider requires `pip install obd` and a connected, key-on vehicle.

---

### Layer 6 — Network Service Layer

**Current state:** There is no separate network/server layer yet. The WebSocket is **localhost-only** (`127.0.0.1:8765`). No remote server, no SQLite persistence, no analytics backend exists. The Diagnostic page has placeholder "Send to server" buttons that do nothing. This entire layer is **NOT DONE**.

---

## 5. File-by-File Breakdown

### `start_veya.sh`
- **Purpose:** Kiosk orchestration — kills stale processes, starts backend, polls WS readiness, launches Qt UI, cleans up on exit.
- **Imports/deps:** `bash`, `ss`, `awk`, `python3` (for socket probe), `.venv`, `obd_service.py`, `ui/build/veya_ui`
- **Exposes:** `--mode`, `--elm-port`, `--elm-baud`, `--hz` CLI flags
- **State:** DONE
- **Missing:** Does not set `QT_QPA_PLATFORM` or display environment — relies on system defaults. No systemd unit file.

---

### `start_mock.sh`
- **Purpose:** Minimal dev shortcut — activates venv and runs obd_service.py with no args (mock mode, 10 Hz).
- **State:** DONE (trivial 4-line script)
- **Missing:** No logging, no arg passing, no UI launch. Pure backend-only dev tool.

---

### `start_mock.sh.backup`
- **Purpose:** Identical backup of `start_mock.sh`. Redundant.
- **State:** DONE / redundant
- **Missing:** Nothing — should be deleted.

---

### `services/obd_service/obd_service.py`
- **Purpose:** Async WebSocket telemetry server with mock simulation and ELM327 OBD-II integration.
- **Imports:** `asyncio`, `json`, `random`, `signal`, `time`, `dataclasses`, `websockets` 16.0
- **Exposes:** WebSocket endpoint `ws://127.0.0.1:8765`; JSON telemetry frames; `set_mode` command handler
- **State:** DONE (mock + mode switch infrastructure). ELM327 path blocked by missing `obd` package.
- **Missing:** `python-obd` not installed. `WebSocketServerProtocol` import triggers deprecation warning on websockets 16.0 (API changed). No `requirements.txt` in repo. No SQLite session logging.

---

### `ui/CMakeLists.txt`
- **Purpose:** Qt6 CMake build definition — creates `veya_ui` executable, registers QML module `Veya 1.0`.
- **Imports:** `Qt6::Core`, `Qt6::Gui`, `Qt6::Qml`, `Qt6::Quick`, `Qt6::WebSockets`
- **Exposes:** `veya_ui` binary; `Veya` QML module with URI `Veya`
- **State:** DONE
- **Missing:** No install target, no release packaging, no strip/UPX step.

---

### `ui/src/main.cpp`
- **Purpose:** Minimal C++ bootstrap — creates `QGuiApplication` and `QQmlApplicationEngine`, loads `qrc:/Veya/qml/Main.qml`.
- **Imports:** `QGuiApplication`, `QQmlApplicationEngine`
- **State:** DONE (17 lines, nothing to change here)
- **Missing:** Nothing. Could add `QQuickWindow::setTextRenderType` for sharper text on RPi but not required.

---

### `ui/qml/qmldir`
- **Purpose:** QML module manifest — registers `VehicleDataProvider` as a singleton and `GaugeRing` as a component under the `Veya` module.
- **State:** DONE
- **Missing:** Any new component added to `components/` must be manually added here AND in `CMakeLists.txt`.

---

### `ui/qml/Main.qml`
- **Purpose:** Root `ApplicationWindow` — fullscreen, frameless, dark background with star-field, global `Ctrl+Shift+Q` exit handler, hosts `StackView` with `Home` as initial item.
- **Imports:** `QtQuick`, `QtQuick.Controls`, `QtQuick.Layouts`
- **Exposes:** `StackView id:stack` (passed as `nav` to child pages)
- **State:** DONE
- **Missing:** Nothing functional. Star-field dots use `Math.random()` at component creation — positions are fixed per session (fine for kiosk).

---

### `ui/qml/Home.qml`
- **Purpose:** Landing page with 3 circular profile buttons (Drive, Media, Diagnostic) and a TEST/REAL mode toggle pill in the top-right corner.
- **Imports:** `QtQuick`, `QtQuick.Controls`, `QtQuick.Layouts`, `Veya 1.0`
- **Exposes:** `nav` property (must be set by parent)
- **Components defined inline:** `GlassCard`, `CircleProfileButton`
- **Data-bound to:** `VehicleDataProvider.dataMode`, `VehicleDataProvider.connected`, `VehicleDataProvider.sendModeCommand()`
- **State:** DONE
- **Missing:** Media profile navigates to a "Coming Soon" `Popup` — no real Media page exists. The `System Ready` / `Pi 5` status bar at the bottom is cosmetic only (always shows "System Ready", does not reflect actual backend state).

---

### `ui/qml/Drive.qml`
- **Purpose:** Main live dashboard page — 3-column layout showing speed (left), engine/RPM (center), and sensors + warnings (right).
- **Imports:** `QtQuick`, `QtQuick.Controls`, `QtQuick.Layouts`, `Veya 1.0`
- **Components defined inline:** `GlassCard`, `MiniMetric`, `ThinBar`
- **Uses:** `GaugeRing` (from `Veya 1.0` module)
- **Data-bound to:** All `VehicleDataProvider` telemetry fields and warnings
- **State:** DONE — fully data-bound, warnings strip functional, mode badge functional
- **Missing:** Layout has a known "recursive rearrange" Qt warning in logs (see risks). Font sizes not yet verified on actual RPi5 display. No gear indicator, no time/clock, no trip odometer.

---

### `ui/qml/Drive.qml.backup`
- **Purpose:** Old Qt5-style Drive layout (versioned imports, 2-gauge + center placeholder design).
- **State:** OBSOLETE / reference only
- **Missing:** Uses `import QtQuick 2.15` / `import QtQuick.Controls 2.15` (Qt5-style). Uses `import "components"` relative path instead of `Veya 1.0`. Should not be compiled.

---

### `ui/qml/Diagnostic.qml`
- **Purpose:** Diagnostic page — placeholder UI with 4 buttons (Read DTC, Send to server, Start live scan, Stop) and a read-only TextArea console.
- **Imports:** `QtQuick`, `QtQuick.Controls`, `QtQuick.Layouts` (no `Veya 1.0` — not data-bound)
- **State:** PLACEHOLDER — no real functionality
- **Missing:** DTC read logic via ELM327 (`obd.commands.GET_DTC`), display of parsed DTC codes with descriptions, server upload, live PID scan table, freeze frame data.

---

### `ui/qml/providers/VehicleDataProvider.qml`
- **Purpose:** `pragma Singleton` WebSocket client — source of truth for all telemetry in the UI. Handles connection lifecycle, frame parsing, UI throttling, mode commands, and warning aggregation.
- **Imports:** `QtQuick`, `QtWebSockets`
- **Exposes:** `connected`, `statusText`, `dataMode`, `rpm`, `speedKph`, `coolantC`, `throttlePct`, `engineLoad`, `batteryV`, `fuelLevel`, `intakeTempC`, `warnCoolantHigh`, `warnOverspeed`, `warnLowFuel`, `warnLowBattery`, `anyWarning`, `lastTs`, `sendModeCommand(mode)`
- **State:** DONE
- **Missing:** No persistence of last known values across reconnect. No timestamp staleness check (if backend dies, UI shows last values indefinitely).

---

### `ui/qml/providers/VehicleDataProvider.qml.backup`
- **Purpose:** Old version of VehicleDataProvider — only 4 telemetry fields, no `dataMode`, no `sendModeCommand`, no extended fields, uses `QtObject` instead of `Item`.
- **State:** OBSOLETE / reference only
- **Missing:** Many fields. Should not be used.

---

### `ui/qml/components/GaugeRing.qml`
- **Purpose:** Reusable circular arc gauge — Canvas2D drawing, configurable min/max/value/unit/label/accent/startDeg/spanDeg/thickness. Repaints on any property change.
- **Imports:** `import QtQuick 2.15` ← **versioned Qt5-style import** (inconsistency with rest of codebase)
- **Exposes:** `min`, `max`, `value`, `unit`, `label`, `accent`, `startDeg`, `spanDeg`, `thickness`
- **State:** DONE — functional
- **Missing:** No inner glow on the arc tip. Text inside gauge uses hardcoded white color (not parameterized). The Qt5-style versioned import should be updated to unversioned Qt6 form.

---

### `.gitignore`
- **Purpose:** Excludes `ui/build/`, `.venv/`, `logs/`, CMake artifacts, Qt compiled QML files.
- **State:** DONE

---

### `external_ui/Modern-Car-Dashboard/` (entire subtree)
- **Purpose:** Reference Qt5 project cloned from GitHub. Contains a car dashboard UI with SVG gauges.
- **State:** NOT INTEGRATED — Qt5 only, uses `.pro`/qmake, incompatible with VEYA's Qt6/CMake stack. Kept for visual inspiration.
- **Missing:** Would require full rewrite to work with Qt6. The CLAUDE.md explicitly prohibits copying from this project.

---

## 6. Data Flow Map

### Full Path

```
┌──────────────────────────────────────────────┐
│              obd_service.py                  │
│                                              │
│  _DriveCycle.tick()                          │
│    → (speed_kph, rpm, throttle_pct)          │
│                                              │
│  MockProvider.read()                         │
│    + coolant warmup (22→92°C over 90s)       │
│    + fuel drain (0.0028%/s)                  │
│    + battery sag (12.4V idle / 14.2V running)│
│    + engine load = throttle*0.65 + rpm/8000  │
│    + intake heat soak (26→34°C over 300s)    │
│    → Telemetry dataclass                     │
│                                              │
│  Telemetry.to_dict()                         │
│    → JSON string (compact, no whitespace)    │
│                                              │
│  TelemetryServer._broadcast_loop()           │
│    → ws.send(payload) to all clients         │
│      at 10 Hz (mock) or 4 Hz (elm)           │
└────────────────────────────┬─────────────────┘
                             │ WebSocket ws://127.0.0.1:8765
                             │ (loopback, JSON text frames)
┌────────────────────────────▼─────────────────┐
│         VehicleDataProvider.qml              │
│                                              │
│  WebSocket.onTextMessageReceived(message)    │
│    → JSON.parse(message)                     │
│    → throttle: skip if < 50ms since last     │
│    → assign to QML properties (below)        │
└────────────────────────────┬─────────────────┘
                             │ QML property bindings
┌────────────────────────────▼─────────────────┐
│              Drive.qml / Home.qml            │
│                                              │
│  GaugeRing.value ← VehicleDataProvider.rpm   │
│  GaugeRing.value ← VehicleDataProvider.speedKph
│  ThinBar.value   ← VehicleDataProvider.engineLoad
│  ThinBar.value   ← VehicleDataProvider.throttlePct
│  MiniMetric.val  ← VehicleDataProvider.coolantC
│  MiniMetric.val  ← VehicleDataProvider.batteryV
│  MiniMetric.val  ← VehicleDataProvider.fuelLevel
│  MiniMetric.val  ← VehicleDataProvider.intakeTempC
│  warnings strip  ← VehicleDataProvider.anyWarning
│  mode badge      ← VehicleDataProvider.dataMode
└──────────────────────────────────────────────┘
```

### WebSocket JSON Schema (Outgoing: Backend → UI)

```json
{
  "schema":        1,
  "ts":            1773381689.793,
  "status":        "mock",
  "rpm":           2400,
  "speed_kph":     87.3,
  "coolant_c":     91.2,
  "throttle_pct":  34.0,
  "engine_load":   45.1,
  "battery_v":     14.21,
  "fuel_level":    72.0,
  "intake_temp_c": 31.4,
  "warnings": {
    "coolant_high": false,
    "overspeed":    false,
    "low_fuel":     false,
    "low_battery":  false
  }
}
```

Optional field (only on mode-switch failure):
```json
{ "...all above...", "mode_error": "ELM327 on /dev/ttyUSB0 — vehicle not responding." }
```

### WebSocket JSON Schema (Incoming: UI → Backend)

```json
{ "cmd": "set_mode", "mode": "mock" }
{ "cmd": "set_mode", "mode": "elm"  }
```

### Field Mapping Table

| JSON field | VehicleDataProvider property | Drive.qml consumer |
|---|---|---|
| `status` | `dataMode` | mode badge text + color |
| `rpm` | `rpm` | GaugeRing (ENGINE col), value: 0–8000 |
| `speed_kph` | `speedKph` | GaugeRing (SPEED col), speed number text, speed bar |
| `coolant_c` | `coolantC` | MiniMetric "COOLANT" |
| `throttle_pct` | `throttlePct` | ThinBar "THROTTLE" |
| `engine_load` | `engineLoad` | ThinBar "ENGINE LOAD" (green/amber/red) |
| `battery_v` | `batteryV` | MiniMetric "BATTERY" |
| `fuel_level` | `fuelLevel` | MiniMetric "FUEL" |
| `intake_temp_c` | `intakeTempC` | MiniMetric "INTAKE AIR" |
| `warnings.coolant_high` | `warnCoolantHigh` | MiniMetric alert + warnings strip |
| `warnings.overspeed` | `warnOverspeed` | speed bar color + warnings strip |
| `warnings.low_fuel` | `warnLowFuel` | MiniMetric alert + warnings strip |
| `warnings.low_battery` | `warnLowBattery` | MiniMetric alert + warnings strip |
| `ts` | `lastTs` | (internal only — not displayed) |

---

## 7. UI Pages — Current State

### Home.qml

**What is visible:**
- Dark gradient background (`#0B0F14 → #070A0E`) with subtle star-field dots
- Title: "Welcome to VEYA" (52px, white, raised shadow effect)
- Gradient underline bar (decorative)
- Subtitle: "Select Your Profile"
- 3 large circular buttons in a horizontal row:
  - **Drive** (cyan `#4DD2FF`): ⟡ icon → pushes `Drive.qml`
  - **Media** (violet `#B788FF`): ♪ icon → shows "Coming Soon" popup
  - **Diagnostic** (green `#47FF9A`): ⚙ icon → pushes `Diagnostic.qml`
- Each button has: hover scale (1.05×), press scale (0.95×), rotating glow ring on hover, ripple animation on click, accent-colored label pill below
- Bottom status bar: pulsing green dot + "System Ready" + "Pi 5" (cosmetic only)
- Top-right corner: TEST/REAL toggle pill — sliding knob, color transitions, "switching…" tooltip

**Data-bound:** mode toggle reads `VehicleDataProvider.dataMode` and `VehicleDataProvider.connected`; calls `VehicleDataProvider.sendModeCommand()`

**Visual state:** Complete and polished.

**Missing for production:** System status bar should reflect real backend health (WebSocket connected/disconnected). Media profile needs implementation. No user profile persistence (3 buttons are cosmetically different but all launch the same pages).

---

### Drive.qml

**What is visible:**
- Top bar: "← Back" button | "DRIVE" title | connection/mode badge (pulsing dot + text)
- **Column 1 (30% width):** "SPEED" label, `GaugeRing` (0–200 km/h, cyan arc), large speed number (52px), speed progress bar (cyan → warning red on overspeed)
- **Column 2 (fills remaining):** "ENGINE" label, `GaugeRing` (0–8000 rpm, green arc), "ENGINE LOAD" ThinBar (green/amber/red thresholds at 60%/80%), "THROTTLE" ThinBar (cyan)
- **Column 3 (28% width):** "SENSORS" label, 4× `MiniMetric` cards (COOLANT °C, BATTERY V, FUEL %, INTAKE AIR °C); each turns red with pulsing border on alert; dynamic warnings strip at bottom showing active warning names

**Data-bound:** Every field and warning from `VehicleDataProvider`.

**Visual state:** Complete and polished. All data live.

**Missing for production:**
- Font size verification on actual RPi5 display resolution (not yet done)
- No gear indicator
- No clock/time display
- No trip counter or odometer
- No DTC (check engine) icon
- Known "Qt Quick Layouts: Detected recursive rearrange" warning in logs (layout constraint issue)

---

### Diagnostic.qml

**What is visible:**
- Top bar: "← Back" button | "Profile 3 – Diagnostic" title
- A single `GlassCard` filling the page containing:
  - Title: "Diagnostic Controls (mock for now)"
  - Text: "No car connected yet. We will add real ELM327 logic later."
  - 4 buttons: Read DTC, Send to server, Start live scan, Stop (all log to TextArea)
  - Read-only `TextArea` console

**Data-bound:** None — `Veya 1.0` not imported.

**Visual state:** PLACEHOLDER. Functional as a stub.

**Missing for production:**
- Read and display real DTC codes from `obd.commands.GET_DTC`
- DTC code lookup (P0xxx → human-readable description)
- Freeze frame data display
- Live PID scan table
- "Send to server" needs a real server endpoint
- Should import `Veya 1.0` to show connection status
- No styling consistency with Drive.qml (uses default Qt button style, not the dark glass theme)

---

## 8. What is Done vs What is Missing

### Done ✅

- **Boot:** RPi5 kiosk auto-launch via `~/.bash_profile → start_veya.sh`
- **Orchestration:** `start_veya.sh` kills stale backend, starts service, polls WS readiness, launches Qt UI, cleans up on exit
- **Qt6 build:** CMake project compiles to `veya_ui`, QML module `Veya 1.0` registered correctly
- **ApplicationWindow:** Fullscreen, frameless, `Ctrl+Shift+Q` exit, dark gradient + star-field background
- **Navigation:** StackView with explicit `nav` property passing (no `StackView.view` bugs)
- **Home page:** 3 circular profile buttons with hover/press/ripple animations
- **Mode toggle:** TEST/REAL pill switch on Home — sends WS command, updates on confirmed response
- **VehicleDataProvider:** WebSocket singleton, auto-reconnect (1s), 20 Hz UI throttle, all 8 telemetry fields, 4 warnings, `anyWarning`, `dataMode`, `sendModeCommand()`
- **Drive page:** 3-column layout — speed gauge, RPM gauge, engine load/throttle bars, 4 sensor cards, warning strip
- **GaugeRing:** Canvas arc gauge with ticks, value text, unit, label, repaint on change
- **MockProvider:** Realistic 8-state drive cycle, coolant warmup, fuel drain, battery model, heat soak
- **Elm327Provider:** Queries 8 OBD PIDs via python-obd, runs in executor (non-blocking), DTC presence check
- **Live mode switch:** Backend hot-swaps provider on `set_mode` command; sends error frame on failure and reverts to mock
- **Warning system:** 4 thresholds (coolant >105°C, speed >150 km/h, fuel <15%, battery <11.8V); UI alerts on all four

---

### Missing / TODO

**UI:**
- [ ] Verify Drive.qml layout on actual RPi5 display (font sizes, column proportions)
- [ ] Fix "Qt Quick Layouts: Detected recursive rearrange" warning in Drive.qml
- [ ] Diagnostic page: full dark-theme redesign to match Drive.qml visual language
- [ ] Diagnostic page: DTC display with code descriptions
- [ ] Media page: any implementation (currently "Coming Soon" popup)
- [ ] No clock/time widget on Drive page
- [ ] No gear indicator
- [ ] Home status bar should reflect real WS connection state, not static "System Ready"

**Backend:**
- [ ] `pip install obd` — python-obd not installed; ELM327 mode will always fail until this is done
- [ ] Fix `WebSocketServerProtocol` deprecation: update to `websockets` 16.0 API (`websockets.ServerConnection` or use `websockets.serve` handler signature)
- [ ] Add `requirements.txt` to repo (`websockets>=16.0`, `obd` optional)
- [ ] SQLite session database: record each drive session (timestamps, min/max/avg for each field)
- [ ] `obd_service.log` is flooded with deprecation warnings — add warning filter

**Integration:**
- [ ] Network service layer: REST or WebSocket server for remote analytics (currently localhost-only)
- [ ] "Send to server" in Diagnostic page needs a real endpoint
- [ ] No DTC read path in Diagnostic: `Elm327Provider` queries `GET_DTC` but result is not surfaced to UI
- [ ] No data export (CSV, JSON session files)

**Hardware:**
- [ ] Custom CAN PCB (STM32 + MCP2515) — not yet designed/built
- [ ] ELM327 real-world test: confirm all 8 PIDs supported by target vehicle
- [ ] Validate `FUEL_LEVEL` PID availability (some vehicles don't support it; fallback already coded)
- [ ] Set correct `--elm-baud` for target vehicle (default 38400 may not match all adapters)

---

## 9. Identified Risks and Technical Debt

### Critical / Blocking

1. **`python-obd` not installed**  
   ELM327 mode (`--mode elm` or UI toggle to REAL) immediately fails with `RuntimeError`. The mode switch path and error frame work correctly — but ELM327 cannot actually be tested until `pip install obd` is run. This must happen before any real vehicle testing.

2. **`WebSocketServerProtocol` deprecated in websockets 16.0**  
   Line 35 of `obd_service.py`: `from websockets.server import WebSocketServerProtocol` triggers a `DeprecationWarning` on every process start. The `obd_service.log` fills entirely with these warnings, burying real errors. In a future websockets release this import may break entirely. Fix: use `websockets.ServerConnection` or use `async with websockets.serve(handler, host, port)` with the handler signature `async def handler(ws)` (no protocol arg).

### Medium / Should Fix Before Demo

3. **Qt Quick Layouts recursive rearrange warning**  
   `veya_ui.log` shows repeated: `Qt Quick Layouts: Detected recursive rearrange. Aborting after two iterations.`  
   This appears in Drive.qml and is caused by conflicting size constraints in the nested `ColumnLayout → RowLayout → GlassCard` hierarchy. The layout still renders, but this warning indicates a constraint cycle that could cause visual glitches on different display sizes.

4. **`GaugeRing.qml` uses Qt5-style versioned import**  
   `import QtQuick 2.15` instead of `import QtQuick`. All other QML files use the unversioned Qt6 form. This is a minor inconsistency that could cause confusion and should be updated.

5. **WS readiness polling timeout**  
   `start_veya.sh` polls for 6 seconds (12 × 0.5s). Logs show the poll times out and the UI launches before the backend is ready. The auto-reconnect in `VehicleDataProvider` handles this gracefully (1s retry), but the startup delay of ~1–2s before data appears could be improved by increasing the poll timeout or using a proper socket wait.

6. **No `requirements.txt`**  
   The Python dependencies are not pinned anywhere in the repo. A fresh RPi5 setup requires manual `pip install websockets`. Contributors have no record of required versions.

### Low / Tech Debt

7. **Backup files committed to repo**  
   `Drive.qml.backup`, `VehicleDataProvider.qml.backup`, `start_mock.sh.backup` are committed. These are dead code and should be removed (the git history preserves them).

8. **`external_ui/Modern-Car-Dashboard/` is a nested git repo**  
   This is a submodule without being declared as one — it has its own `.git` directory. It should either be added as a proper `git submodule` or removed entirely since it's Qt5-incompatible.

9. **Home.qml status bar is cosmetic only**  
   The "System Ready" / "Pi 5" pill at the bottom of Home.qml is hardcoded. It does not read `VehicleDataProvider.connected`. Users cannot tell from the Home screen whether the backend is running.

10. **No data staleness detection**  
    If the backend freezes without closing the WebSocket, `VehicleDataProvider` will display the last received values indefinitely. A `lastTs` staleness check (e.g., warn if no frame in 2s) would improve reliability.

11. **`awk` PID extraction in `start_veya.sh`**  
    The `awk` command used to extract the PID from `ss` output uses `match()` with a gensub-style array capture. On some awk implementations (mawk, which is default on Debian), this syntax is invalid. Logs show `awk: line 1: syntax error at or near ,`. Should use `grep -oP 'pid=\K[0-9]+'` or a pure-bash approach.

12. **`Diagnostic.qml` `console` variable name**  
    The `TextArea` is given `id: console`, which shadows the global `console` QML object (used for `console.log()`). This is a latent bug — clicking the buttons calls `console.text += "..."` which currently works only because `TextArea` happens to have a `text` property, but it prevents any actual `console.log()` calls from within those handlers.

---

## 10. Suggested Next Steps

### UI Completion Tasks

1. **Verify Drive.qml on actual RPi5 display:** Boot the kiosk, screenshot or photograph the screen, adjust `font.pixelSize` values and column width ratios if anything is clipped or oversized.

2. **Fix Drive.qml layout rearrange warning:** Profile which layout item is causing the constraint cycle. Likely culprit: `Layout.fillHeight: true` combined with `Layout.preferredHeight` inside the same `ColumnLayout`. Add explicit heights or remove conflicting size hints.

3. **Update GaugeRing.qml import:** Change `import QtQuick 2.15` to `import QtQuick` for consistency with the rest of the codebase.

4. **Redesign Diagnostic.qml:** Apply the same `GlassCard` + dark theme from Drive.qml. Import `Veya 1.0` and show connection status. Add a scrollable DTC list widget (placeholder rows for now).

5. **Home status bar fix:** Bind the "System Ready" text and dot color to `VehicleDataProvider.connected`.

6. **Rename `id: console` in Diagnostic.qml** to `id: outputArea` or similar to avoid shadowing the global `console` object.

---

### Backend Tasks (Before Remote Server Available)

7. **Add `requirements.txt`:**
   ```
   websockets>=16.0
   # obd  # uncomment when ELM327 testing
   ```

8. **Fix websockets 16.0 deprecation:** Update `obd_service.py` line 35:
   ```python
   # Remove: from websockets.server import WebSocketServerProtocol
   # Change handler signature:
   async def _client_handler(self, ws) -> None:  # ws is ServerConnection in v16+
   ```
   And update the type annotation from `WebSocketServerProtocol` to `Any` or `websockets.ServerConnection`.

9. **Fix `awk` PID extraction in `start_veya.sh`:** Replace the fragile awk command with `grep -oP 'pid=\K[0-9]+'` which works on all Debian-family systems.

10. **Add staleness guard to VehicleDataProvider:** If `Date.now()/1000 - lastTs > 2.0` and connected is true, surface a "stale data" warning.

11. **Add SQLite session logging to obd_service.py:** On each `Telemetry` write, append a row to `~/.veya/sessions.db`. Schema: `(id INTEGER PRIMARY KEY, ts REAL, status TEXT, rpm INTEGER, speed_kph REAL, coolant_c REAL, throttle_pct REAL, engine_load REAL, battery_v REAL, fuel_level REAL, intake_temp_c REAL)`.

---

### Backend Tasks (After Remote Server Available)

12. **Implement REST upload in obd_service.py:** At session end (SIGTERM), POST the session summary (duration, max speed, avg RPM, etc.) to a remote endpoint.

13. **Wire "Send to server" in Diagnostic.qml:** Implement a WS command `{"cmd": "upload_session"}` that triggers the upload.

14. **Implement DTC surfacing:** Add a `{"cmd": "read_dtc"}` command to the backend. Backend queries `GET_DTC` and sends `{"dtc_codes": [{"code": "P0300", "description": "..."}]}` frame. Diagnostic.qml listens for this frame type.

---

### OBD / Hardware Integration Tasks

15. **Install python-obd:** `source .venv/bin/activate && pip install obd`

16. **Real-vehicle ELM327 test:**
    - Connect ELM327 to `/dev/ttyUSB0`
    - Key-on (not necessarily engine running for some PIDs)
    - `./start_veya.sh --mode elm`
    - Confirm all 8 PIDs respond; note which are null and add fallbacks
    - Test mode switch from mock → elm while running

17. **Validate baud rate:** Try `--elm-baud 9600` if 38400 fails (ELM327 clone adapters often default to 9600).

18. **Custom CAN PCB design:** STM32 + MCP2515 schematic and layout. Plan Python driver that exposes the same `TelemetryProvider` interface so it can drop in alongside `MockProvider` and `Elm327Provider`.

19. **Test `FUEL_LEVEL` PID availability** on target vehicle. The provider already has a fallback (`self._last_fuel`) for vehicles that don't respond to it.

---

*End of VEYA_DASHBOARD_ARCHITECTURE.md*
