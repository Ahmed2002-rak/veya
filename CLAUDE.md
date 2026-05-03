# VEYA — Claude Code Project Context

> Claude Code reads this file automatically at session start.
> It is the single source of truth. Update after every milestone.
> Last updated: May 2026 — after Phase 2.0 architecture refactor.

---

## REQUIRED READING (read in order before touching code)

After this file, open these in this exact order. Each one is short and they are mutually consistent — newest understanding lives in the later docs.

1. **[`docs/MEMORY.md`](docs/MEMORY.md)** — current project state, the phase plan, decisions worth remembering, conventions, shortcuts, traps. Start here so you know which phase we're in and what NOT to redo.
2. **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** — three-process layout (source → core → UI), the two wires, layer-by-layer walkthrough, mode-switch flow.
3. **[`docs/CONTRACT.md`](docs/CONTRACT.md)** — source-to-core wire protocol (TCP, line-JSON). Authoritative spec for any new source (ESP32 firmware, custom CAN board, …). The UI WS schema is *not* this — it's the legacy one documented in §"WebSocket JSON contract" below.
4. **[`VEYA_DASHBOARD_ARCHITECTURE.md`](VEYA_DASHBOARD_ARCHITECTURE.md)** — Phase-1 architecture document. Still useful as reference for the QML/Qt layer, the file-by-file breakdown, and the historical UI schema. Predates Phase 2.0; cross-check against `docs/ARCHITECTURE.md` if anything conflicts.

If you're resuming a session mid-task, also `git status` and `git log --oneline -10` to see what work survived from the previous session.

---

## One-line summary

VEYA is an embedded vehicle dashboard on Raspberry Pi 5 (Qt6/QML + Python WebSocket), built as a dual academic project (Ingéniorat = custom OBD-II/CAN hardware, Master = software/analytics) and a startup prototype.

**Students:** Ahmed Khodhir REZIG · Sid Ahmed LAKEHAL  
**Year:** 2025/2026 · Electronics / Industrial Informatics  
**GitHub:** https://github.com/Ahmed2002-rak/PFE2026.git  
**Dev env:** SSH + VS Code Remote → Raspberry Pi 5

---

## Repository layout

```
PFE2026/
├── CLAUDE.md                              ← this file
├── .gitignore
├── requirements.txt                       ← top-level (-r services/veya_core/requirements.txt)
├── start_veya.sh                          ← kiosk entry point
├── start_mock.sh                          ← quick backend-only dev shortcut
│
├── docs/                                  ← Phase 2.0+ docs (READ FIRST — see top of this file)
│   ├── MEMORY.md
│   ├── ARCHITECTURE.md
│   └── CONTRACT.md
│
├── VEYA_DASHBOARD_ARCHITECTURE.md         ← Phase-1 reference doc
│
├── services/
│   └── veya_core/                         ← Phase 2.0 core service (was obd_service/)
│       ├── __init__.py
│       ├── contract.py                    ← source-to-core wire schema + validators
│       ├── tcp_server.py                  ← single-source TCP listener
│       ├── ws_server.py                   ← UI-facing WebSocket (legacy schema)
│       ├── core.py                        ← orchestrator + mode state machine
│       ├── requirements.txt
│       └── sources/                       ← standalone source scripts
│           ├── __init__.py
│           ├── mock_source.py             ← drive-cycle simulation (TCP client)
│           └── elm327_source.py           ← real ELM327 USB bridge (TCP client)
│
└── ui/
    ├── CMakeLists.txt
    ├── src/main.cpp                       ← loads qrc:/Veya/qml/Main.qml
    └── qml/
        ├── qmldir                         ← singleton + component registration
        ├── Main.qml                       ← ApplicationWindow + StackView
        ├── Home.qml                       ← 3 profile buttons + TEST/REAL toggle
        ├── Drive.qml                      ← live dashboard (3-column layout)
        ├── Diagnostic.qml                 ← DTC placeholder
        ├── providers/
        │   └── VehicleDataProvider.qml    ← WebSocket singleton (all telemetry)
        └── components/
            └── GaugeRing.qml             ← Canvas arc gauge
```

---

## Tech stack

| Layer | Technology |
|---|---|
| UI | Qt6 / QML, CMake |
| QML modules used | QtQuick 2, QtQuick.Controls 2, QtWebSockets |
| Backend | Python 3, asyncio, websockets library |
| Transport | WebSocket ws://127.0.0.1:8765 |
| Python env | .venv at /home/pfe/veya/.venv |
| Deploy path | /home/pfe/veya/ |
| Font | DejaVu Sans (everywhere, always available on RPi) |

---

## How to build & run

```bash
# Build Qt UI
cd /home/pfe/veya/ui
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release && make -j4

# Run — mock mode (default; core auto-spawns mock_source.py)
./start_veya.sh

# Run — real mode (core listens on TCP :9000 for an external source)
./start_veya.sh --mode real
# legacy alias: ./start_veya.sh --mode elm   (silently mapped to --mode real)

# Then, in another terminal, point the ELM327 source at the core:
source .venv/bin/activate && pip install obd          # one-time
python -m services.veya_core.sources.elm327_source --device /dev/ttyUSB0

# Backend only (dev) — core in mock mode, no UI
source .venv/bin/activate
python -m services.veya_core.core --mode mock --hz 10

# Watch logs
tail -f logs/kiosk.log
tail -f logs/obd_service.log         # core stdout/stderr (filename kept from Phase 1)
tail -f logs/veya_ui.log
```

---

## WebSocket JSON contract

**NEVER rename these fields without updating BOTH obd_service.py AND VehicleDataProvider.qml.**

```json
{
  "schema":        1,
  "ts":            1234567890.123,
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

`status` values: `"mock"` (simulation) | `"elm"` (real ELM327)

**Incoming command** (UI → backend, for live mode switch):
```json
{ "cmd": "set_mode", "mode": "mock" }
{ "cmd": "set_mode", "mode": "elm"  }
```

**Error frame** (backend → UI, when mode switch fails):
```json
{ ...normal telemetry..., "mode_error": "ELM327 not connected: ..." }
```

---

## VehicleDataProvider — all properties

Access from any QML: `import Veya 1.0` then use `VehicleDataProvider.xxx` directly.

```
// Connection
connected          bool    WebSocket open
statusText         string  "mock" | "elm" | "connecting" | "closed" | "error: ..."
dataMode           string  "mock" | "elm" | "unknown"

// Core telemetry (ORIGINAL — never rename these)
rpm                real
speedKph           real
coolantC           real
throttlePct        real

// Extended telemetry
engineLoad         real
batteryV           real
fuelLevel          real
intakeTempC        real

// Warnings
warnCoolantHigh    bool
warnOverspeed      bool
warnLowFuel        bool
warnLowBattery     bool
anyWarning         bool    OR of all four warnings

// Mode switch (called by Home.qml toggle)
sendModeCommand("mock")   // sends {"cmd":"set_mode","mode":"mock"} over WebSocket
sendModeCommand("elm")    // sends {"cmd":"set_mode","mode":"elm"}  over WebSocket
```

---

## qmldir (DO NOT CHANGE without updating CMakeLists.txt too)

```
module Veya
singleton VehicleDataProvider 1.0 providers/VehicleDataProvider.qml
GaugeRing 1.0 components/GaugeRing.qml
```

**Adding a new component:**
1. Create `ui/qml/components/MyThing.qml`
2. Add `MyThing 1.0 components/MyThing.qml` to qmldir
3. Add `qml/components/MyThing.qml` to `QML_FILES` in CMakeLists.txt
4. `make -j4`

---

## Navigation pattern (always use this)

```qml
// Main.qml — owns the StackView:
initialItem: Home { nav: stack }

// Pushing a page (e.g. Home.qml):
root.nav.push(Qt.resolvedUrl("Drive.qml"), { nav: root.nav })

// Going back (e.g. Drive.qml):
root.nav.pop()
```

Never use `StackView.view` — always pass `nav` explicitly as a property.

---

## GaugeRing usage

```qml
GaugeRing {
    min:       0
    max:       8000
    value:     VehicleDataProvider.rpm
    unit:      "rpm"
    label:     "RPM"
    accent:    "#7CFF4A"          // any CSS color string
    // optional: startDeg=-210, spanDeg=240, thickness=18
}
```

---

## Inline Drive.qml components (not external files)

Drive.qml defines these inline — they are NOT standalone files, NOT in qmldir:
- `GlassCard` — dark semi-transparent panel with border
- `MiniMetric` — compact labeled value with alert pulsing state
- `ThinBar` — labeled progress bar with glowing tip

Do NOT try to use these from other QML files.

---

## Hard rules

### Never do
1. Rename JSON fields (`rpm`, `speed_kph`, etc.) without updating both Python + QML
2. Use Qt5 modules: no `QtQuick.Extras`, `QtGraphicalEffects`, `QtQuick.Controls.Styles`
3. Copy external GitHub QML dashboard files — they are Qt5-only
4. Put WebSocket code anywhere except `VehicleDataProvider.qml`
5. Work directly on `main` branch for risky changes — always branch first

### Always do
1. `import Veya 1.0` to access VehicleDataProvider and GaugeRing
2. `font.family: "DejaVu Sans"` everywhere
3. Add new QML files to BOTH `qmldir` AND `CMakeLists.txt QML_FILES`
4. `make -j4` after any CMakeLists.txt change or new QML file
5. `git tag vX.Y-pre` before any large change

---

## Current status (May 2026 — Phase 2.0)

### Done ✅
- RPi5 kiosk boot: `~/.bash_profile → start_veya.sh`
- Qt6/QML fullscreen, `Ctrl+Shift+Q` exits
- Home: 3 circular profile buttons with hover/ripple animations
- Home: TEST/REAL mode toggle (top-right pill switch) — sends WS command to backend
- Drive: 3-column layout (speed gauge | RPM + engine | sensors + warnings)
- VehicleDataProvider: WebSocket singleton, auto-reconnect, 20 Hz UI throttle, sendModeCommand()
- **Phase 2.0 architecture refactor**: legacy monolithic `obd_service.py` split into
  `services/veya_core/{contract, tcp_server, ws_server, core}.py` plus standalone source
  scripts in `services/veya_core/sources/`. Mock auto-spawned by core; ELM327 runs as a
  standalone TCP-client script. UI WS schema unchanged.
- New source-to-core wire contract (TCP, line-JSON) — see [`docs/CONTRACT.md`](docs/CONTRACT.md)
- Live mode switch with status-only fast-path: instant TEST/REAL UI confirmation, 3 s timeout
  with `mode_error` when no real source materialises

### Not done yet 📋
- Verify Drive layout on actual RPi5 display resolution (may need font size tuning)
- Diagnostic: real DTC read logic (`query_dtc` frame is in the contract; UI not wired yet)
- SQLite session database (Phase 2.1)
- ESP32 firmware as a third source kind (Phase 2.3)
- Custom CAN PCB: STM32 + MCP2515 (Phase 3.0)

---

## Git workflow

```
main           → always stable, always demo-ready
feature/xxx    → all risky work
hotfix/xxx     → critical fixes only

v1.0-stable    → RPi5 boot + mock + Drive screen
v1.1-stable    → (next) after ELM327 confirmed working
v2.0-stable    → (future) after DB + analytics layer
```

---

## Useful commands

```bash
# Manual WebSocket test
wscat -c ws://127.0.0.1:8765              # npm install -g wscat

# Send mode switch manually
echo '{"cmd":"set_mode","mode":"elm"}' | wscat -c ws://127.0.0.1:8765

# Check port
ss -ltnp | grep 8765

# Kill everything
pkill veya_ui; pkill -f obd_service.py

# RPi CPU temp
vcgencmd measure_temp
```

---

*Update this file after every milestone.*
