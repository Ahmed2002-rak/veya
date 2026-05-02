# VEYA — Claude Code Project Context

> Claude Code reads this file automatically at session start.
> It is the single source of truth. Update after every milestone.
> Last updated: March 2026 — after mode-switch integration.

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
├── start_veya.sh                          ← kiosk entry point
├── start_mock.sh                          ← quick backend-only dev shortcut
│
├── services/
│   └── obd_service/
│       └── obd_service.py                 ← WebSocket telemetry server
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

# Run — mock mode (default)
./start_veya.sh

# Run — real ELM327
./start_veya.sh --mode elm --elm-port /dev/ttyUSB0

# Backend only (dev)
source .venv/bin/activate
python services/obd_service/obd_service.py --mode mock
python services/obd_service/obd_service.py --mode elm

# Install ELM327 library when ready
source .venv/bin/activate && pip install obd

# Watch logs
tail -f logs/kiosk.log
tail -f logs/obd_service.log
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

## Current status (March 2026)

### Done ✅
- RPi5 kiosk boot: `~/.bash_profile → start_veya.sh`
- Qt6/QML fullscreen, `Ctrl+Shift+Q` exits
- Home: 3 circular profile buttons with hover/ripple animations
- Home: TEST/REAL mode toggle (top-right pill switch) — sends WS command to backend
- Drive: 3-column layout (speed gauge | RPM + engine | sensors + warnings)
- VehicleDataProvider: WebSocket singleton, auto-reconnect, 20 Hz UI throttle, sendModeCommand()
- obd_service.py: MockProvider (drive cycle simulation) + Elm327Provider (python-obd)
- obd_service.py: live mode switch — handles `{"cmd":"set_mode"}` commands from UI
- start_veya.sh: `--mode mock|elm --elm-port --elm-baud --hz` passthrough

### Not done yet 📋
- Verify Drive layout on actual RPi5 display resolution (may need font size tuning)
- Diagnostic: real DTC read logic
- SQLite session database
- Custom CAN PCB: STM32 + MCP2515

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
