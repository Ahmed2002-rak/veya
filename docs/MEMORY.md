# VEYA — Project Memory

> **Audience:** future-you, future contributors, AI assistants resuming a session
> **Read alongside:** [`CONTRACT.md`](./CONTRACT.md), [`ARCHITECTURE.md`](./ARCHITECTURE.md), [`../CLAUDE.md`](../CLAUDE.md)
> **Last updated:** May 2026 (after Phase 3.0c — ESP32 BT pipeline verified end-to-end)

This file is the place for things that are *not* derivable from the code: decisions, conventions, reasons, and traps. If something is mechanically obvious from `git log` or from reading a file, it does not belong here.

---

## 1. Project state — at a glance

**Where we are:** v3.0c-stable on main. End-to-end pipeline (ESP32 → BT-SPP → bt_bridge → core → UI) verified on real hardware with the reference firmware.

**What works today:**
- Kiosk boot through `start_veya.sh` — RPi5 auto-starts on login via `~/.bash_profile`.
- `python -m services.veya_core.core --mode mock` boots a self-contained mock dashboard.
- `python -m services.veya_core.core --mode real` listens on TCP :9000; running `elm327_source.py` (or any compliant source) feeds the UI.
- Live mode switching from the Home toggle, with instant status confirmation and a 3 s timeout when no real source materialises.
- All Phase 1 telemetry fields, warnings, and the dual-channel UX (TEST badge / REAL badge) preserved.
- Bluetooth pairing via dashboard UI (`BluetoothManager.qml`): scan, pair, unpair, bridge-status.
- `bt_bridge.py` opens an RFCOMM socket to the paired ESP32 and forwards frames to TCP :9000.
- Wi-Fi management via dashboard UI (`WifiManager.qml`): scan, connect, disconnect, status.
- First-launch onboarding flow with custom QML on-screen keyboard.
- Reference ESP32 sketch at `firmware/esp32/veya_esp32_sample.ino` — BT-Classic SPP, hardcoded telemetry values.
- Settings → Wi-Fi and Settings → Bluetooth status indicators on the Home screen.
- Three-state banner on Drive: waiting-for-source / no-telemetry / streaming.
- Server URL configurable via `python3 services/veya_core/helpers/set_server_url.py`.

**What does not work yet:**
- Real OBD reading on the ESP32 — the reference sketch sends hardcoded values; actual CAN/ISO 9141 reading is the Ingéniorat hardware track (Phase 3.1).
- Server integration: Get Report POST and Live Session WebSocket are not yet implemented (Phase 3.2).
- SQLite session logging (Phase 3.4).
- DTC display on Diagnostic page UI — the `dtc` wire frame is defined and the Diagnostic.qml placeholder exists, but they are not connected (Phase 3.5).

---

## 2. Phase plan (the long arc)

| Phase | Title | Status |
| --- | --- | --- |
| 1.0 | Mock + ELM327 backend, Qt6 dashboard, RPi5 kiosk | ✅ done — `v1.0-stable` |
| 2.0 | Architecture refactor: `core` + `sources` over TCP | ✅ done — `v2.0-stable` |
| 2.1 | 1024×600 visual polish + warning telltales | ✅ done — `v2.1-stable` |
| 2.2a | User-facing Diagnostic + hidden DevDiagnostic gesture | ✅ done — `v2.2a-stable` |
| 2.2b | Onboarding flow + custom QML keyboard + UserProfile | ✅ done — `v2.2b-stable` |
| 3.0a | Wi-Fi backend via WS commands + Home indicator + COMMANDS.md | ✅ done — `v3.0a-stable` |
| 3.0b | Bluetooth bridge + BT manager UI + bt-agent + setup_bluetooth.sh | ✅ done — `v3.0b-stable` |
| 3.0c | ESP32 reference firmware + end-to-end pipeline verified on hardware | ✅ done — `v3.0c-stable` |
| 3.1 | Real OBD reading on ESP32 (replace hardcoded values, integrate CAN/ISO 9141) | not started — Ingéniorat hardware track |
| 3.2 | Server integration (Get Report POST, Live Session WebSocket) | not started — friend's server work |
| 3.3 | Production cleanup (unpair test devices, kiosk hardening, autostart polish) | not started |
| 3.4 | SQLite session logging + per-trip stats | not started |
| 3.5 | DTC pipe to Diagnostic page UI | not started |

The phase numbers are how the team refers to milestones in conversation; they do not appear in code or commit messages except where explicitly tagged.

---

## 3. Decisions worth remembering

These are all conscious choices, not arbitrary code; if you find yourself wanting to undo one, re-read the rationale first.

### 3.1 The UI WS schema is FROZEN

`VehicleDataProvider.qml` consumes a JSON shape with nested `warnings`, a `status` field whose values are `"mock"` or `"elm"` (not `"real"`), and flat top-level telemetry keys. **This shape is frozen** for the lifetime of the QML provider as it stands today. The Phase 2.0 refactor goes out of its way (`core._translate_telemetry`, `core._legacy_status`) to keep the wire format byte-identical to Phase 1.

If you need to add a UI field, the right move is:
1. Add it to the source-facing `contract.py` first.
2. Translate it into the legacy schema in `core._translate_telemetry`.
3. Add a property in `VehicleDataProvider.qml`.
4. Bind in the consuming page.

Do *not* "modernise" the UI schema in passing — it will silently break the QML provider.

### 3.2 The source-facing schema is the EXTENSIBLE one

When you need a new field, kind of frame, or mode, extend `contract.py`. That is the protocol Phase 2.0 was built to grow into. See `docs/CONTRACT.md` §3 for the forward-compat rules (unknown fields ignored; unknown frame types rejected).

### 3.3 Single source, by design

`TcpSourceServer` rejects the second concurrent connection. Multi-source aggregation (e.g. ELM327 *and* an aux ESP32 simultaneously) is intentionally out of scope. If a future use case demands it, do *not* paper over it — that is a real architectural change requiring its own design pass, not a `if not self._writer:` tweak.

### 3.4 Mock subprocess, not a thread

`core.py` spawns `mock_source.py` as a separate OS process via `asyncio.create_subprocess_exec`. The reason is that the mock is then *exactly the same* type of object as a future ESP32 — both are external sources speaking TCP. We trade ~30 MB of RSS and a fork() for keeping the source-or-not distinction crisp. Do not refactor the mock back into in-process code.

### 3.5 Status-only broadcast for instant mode-switch UX

When the user toggles TEST/REAL, the UI must see the status badge change *before* the next telemetry tick (which could be up to 1 s away in diagnostic mode). `core._broadcast_status_only()` resets the 20 Hz throttle gate and emits one frame using cached telemetry but the new `status`. This is the only place we deliberately bypass the throttle. Don't over-use it; one frame per mode switch is enough.

### 3.6 `--mode elm` is a back-compat alias

Internally the core knows two modes: `mock` and `real`. The UI and the legacy CLI use `mock` and `elm`. The mapping lives in two places only:
- `start_veya.sh` translates `--mode elm` → `--mode real`.
- `core._on_ui_command` translates `mode: "elm"` → `INTERNAL_MODE_REAL`.
- `core._legacy_status` translates `INTERNAL_MODE_REAL` → `"elm"` on the way out.

If you ever rename "real" to "live" or similar, the legacy mapping must stay in place — see §3.1.

### 3.7 Why TCP / line-JSON between source and core

Documented at length in [`CONTRACT.md` §2.1](./CONTRACT.md#21-why-line-delimited-json-not-websocket--mqtt--protobuf). TL;DR: ESP32 firmware is the binding constraint; JSON over a stream socket parses cleanly there with zero deps.

---

## 4. Conventions

### 4.1 Python

- Python 3.13.5 system interpreter, virtualenv at `/home/pfe/veya/.venv`.
- `from __future__ import annotations` at the top of every new module.
- Package-relative imports inside `services/veya_core/` (e.g. `from . import contract`).
- Logging via the `logging` module, not `print`. Each module has its own `log = logging.getLogger(...)`.
- Source scripts must work both as `python -m services.veya_core.sources.X` *and* as `python services/veya_core/sources/X.py` — see the `if __package__ in (None, "")` block at the top of `mock_source.py` for the pattern.

### 4.2 QML

- Unversioned Qt6 imports (`import QtQuick`, not `import QtQuick 2.15`). The one offender is `GaugeRing.qml` — known tech debt, do not extend it.
- All telemetry through `VehicleDataProvider`. Never open a second WebSocket from any other QML file.
- New components go in `ui/qml/components/` AND must be added to BOTH `qmldir` AND `CMakeLists.txt QML_FILES`.

### 4.3 Bash

- `start_veya.sh` is the only script that runs at boot. Do not chain other scripts in front of it.
- Logs go to `/home/pfe/veya/logs/`. Never log to stdout — the kiosk has no visible terminal.

### 4.4 Git

- `main` is always demo-ready. Risky work goes on a feature branch.
- Tags: `v1.0-stable`, `v1.1-stable`, etc. — created *after* a milestone is verified on real hardware, not before.
- The `phase-2.0-architecture` branch will merge to `main` after the user reviews this work locally and runs the smoke tests on the actual Pi.

---

## 5. Shortcuts — useful one-liners

```bash
# Start core in mock mode, no UI, see frames
python -m services.veya_core.core --mode mock --hz 5

# Run the mock source against an existing core
python -m services.veya_core.sources.mock_source --port 9000

# Tail the WebSocket output as JSON
wscat -c ws://127.0.0.1:8765            # npm install -g wscat

# Hand-craft a TCP frame to the core (one line)
echo '{"schema":1,"type":"hello","source_id":"x","source_kind":"manual"}' \
    | nc -q1 127.0.0.1 9000

# Send a UI mode-switch command directly (skip the QML toggle)
echo '{"cmd":"set_mode","mode":"elm"}' | wscat -c ws://127.0.0.1:8765

# Smoke-compile every Python file in the package
python -m compileall -q services/veya_core

# Build the Qt UI after editing CMakeLists.txt
cd ui/build && cmake .. -DCMAKE_BUILD_TYPE=Release && make -j4

# Kill any leftover backend before rerunning
pkill -f services.veya_core.core ; pkill -f mock_source

# Watch all three logs at once
tail -f logs/kiosk.log logs/obd_service.log logs/veya_ui.log
```

---

## 6. Things never to do

The catalogue of "I tried this in 2026, do not try it again."

1. **Do not rename a JSON field on the UI WS without updating BOTH `core.py:_translate_telemetry` AND `VehicleDataProvider.qml`.** They are coupled by name. The legacy schema is frozen — see §3.1.
2. **Do not import `QtWebSockets` from any QML file other than `VehicleDataProvider.qml`.** The whole point of the singleton is one socket for the whole app.
3. **Do not use Qt5 modules** — `QtGraphicalEffects`, `QtQuick.Extras`, `QtQuick.Controls.Styles`. They are gone in Qt6.
4. **Do not copy QML from `external_ui/`** — those projects are Qt5/qmake and will not compile.
5. **Do not work directly on `main`** for risky changes. Use a branch, tag, then merge.
6. **Do not run two sources simultaneously** against the core. The TCP server rejects the second one — see §3.3.
7. **Do not skip `\n` between TCP frames** when writing a custom source. The core uses `readline()`. A frame without a trailing newline will be buffered until the *next* frame's newline arrives; you will think the protocol is broken when really it is your line terminator.
8. **Do not raise the broadcast Hz above 20** without raising both `UI_BROADCAST_HARD_HZ` in `ws_server.py` AND `uiUpdateMinMs` in `VehicleDataProvider.qml`. They must stay aligned.
9. **Do not bypass `start_veya.sh` on the Pi**. The script handles the port-clean step that prevents "address already in use" on reboot.
10. **Do not commit anything in `logs/`, `ui/build/`, or `.venv/`.** Already in `.gitignore`; mentioned here because new contributors sometimes try.
11. **Do not put workaround comments like `// fix for ws bug` in code.** Phase 2.0 deliberately removed several such comments. The git log is the place for that context.
12. **Do not auto-start `bt_bridge.py` from `start_veya.sh`.** The bridge is spawned by `ws_server.py` only after a successful `bt_pair` WS command. Auto-starting it would race with the pair handshake — the bridge needs the paired MAC from `~/.veya/bt_config.json`, which only exists after a successful pair.

---

## 7. Known issues / tech debt carried into Phase 2.1

These are *not* blockers for Phase 2.0 acceptance — they are carry-overs.

- `GaugeRing.qml` uses the Qt5-style versioned import (`import QtQuick 2.15`). Functional; should be unversioned.
- `Drive.qml` emits a "Qt Quick Layouts: Detected recursive rearrange" warning at startup. Renders correctly; constraint cycle should be cleaned up.
- `Diagnostic.qml`'s TextArea has `id: console`, which shadows the global QML `console` object. Latent bug; does not currently break anything but blocks `console.log()` from those handlers.
- `python-obd` is not in `.venv`. `--mode real` paired with `elm327_source.py` will exit code 2 with a clear error until `pip install obd` is run.

---

## 8. System dependencies

These packages must be present on the Pi for all features to work. Run `scripts/setup_bluetooth.sh` on a fresh Pi — it handles items 3–5 automatically.

| Package / service | Purpose | How to install |
| --- | --- | --- |
| `bluez` | Core Bluetooth stack (bluetoothd, bluetoothctl, **hcitool**). `hcitool scan` is used by `helpers/bluetooth.py scan()` for raw BR/EDR inquiry — required to discover BT-Classic SPP devices (e.g. ESP32) that bluetoothctl's filtered scan misses. | `sudo apt-get install -y bluez` |
| `bluez-tools` | `bt-agent` binary for no-PIN pairing | `sudo apt-get install -y bluez-tools` |
| Python stdlib `socket` (AF_BLUETOOTH + BTPROTO_RFCOMM) | RFCOMM connection in `bt_bridge.py`. Built-in on Linux — **no install needed**. pybluez / python3-bluez is NOT required and should NOT be installed (dead on Python 3.13). | built-in |
| `bt-agent` systemd service | Runs `bt-agent --capability=NoInputNoOutput` at boot so the Pi accepts pairing requests without a PIN | `bash scripts/setup_bluetooth.sh` |
| `matchbox-keyboard` | On-screen keyboard for the Settings / onboarding flow | `sudo apt-get install -y matchbox-keyboard` |
| NetworkManager + `nmcli` | Wi-Fi management used by the Wi-Fi settings page and `helpers/wifi.py` | `sudo apt-get install -y network-manager` |
| `firmware/esp32/veya_esp32_sample.ino` | ESP32 reference firmware (BT-Classic SPP, hardcoded telemetry) | Flash with Arduino IDE 2.x + esp32 board manager 2.0.14+ |

---

## 9. People & contact

| Role | Name | Stream |
| --- | --- | --- |
| Hardware (CAN PCB, ELM327 wiring) | Ahmed Khodhir REZIG | Ingéniorat |
| Software (Python, QML, RPi) | Sid Ahmed LAKEHAL | Master |

Project repo: <https://github.com/Ahmed2002-rak/veya.git>

---

*End of MEMORY.md*
