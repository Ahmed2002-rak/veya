pragma Singleton
import QtQuick
import QtWebSockets

// ─────────────────────────────────────────────────────────────────────────────
// VehicleDataProvider — singleton, WebSocket client.
// ALL telemetry lives here. Pages bind to properties and call functions.
// Never import QtWebSockets in any other QML file.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    visible: false

    property string url: "ws://127.0.0.1:8765"

    // ── Connection state ──────────────────────────────────────────────────────
    property bool   connected:   (ws.status === WebSocket.Open)
    property string lastStatus:  ""
    property string statusText:  connected
                                ? (lastStatus.length ? lastStatus : "connected")
                                : (lastStatus.length ? lastStatus : "disconnected")

    // "mock" | "elm" | "unknown"
    // Driven by obj.status from each JSON frame — not by WS connection status.
    property string dataMode: "unknown"

    // ── Core telemetry (ORIGINAL NAMES — never rename) ─────────────────────
    property real rpm:          0
    property real speedKph:     0
    property real coolantC:     0
    property real throttlePct:  0

    // ── Extended telemetry ──────────────────────────────────────────────────
    property real engineLoad:   0
    property real batteryV:     12.4
    property real fuelLevel:    80.0
    property real intakeTempC:  25.0

    // ── Warning flags ───────────────────────────────────────────────────────
    // PHASE-2.1.1-DEBUG: when true, all 4 warning flags are forced ON.
    // Used by Ctrl+Shift+W shortcut in Main.qml. Remove in Phase 2.2.
    property bool debugForceWarnings: false

    // Internal backing — written by WS message handler
    property bool _wsCoolantHigh: false
    property bool _wsOverspeed:   false
    property bool _wsLowFuel:     false
    property bool _wsLowBattery:  false

    // Public — OR'd with debug override (API unchanged for all consumers)
    readonly property bool warnCoolantHigh: _wsCoolantHigh || debugForceWarnings
    readonly property bool warnOverspeed:   _wsOverspeed   || debugForceWarnings
    readonly property bool warnLowFuel:     _wsLowFuel     || debugForceWarnings
    readonly property bool warnLowBattery:  _wsLowBattery  || debugForceWarnings

    // Convenience: any active warning at all
    readonly property bool anyWarning: warnCoolantHigh || warnOverspeed
                                       || warnLowFuel  || warnLowBattery

    // ── Pseudo-gear (UI-only simulation) ───────────────────────────────────
    // OBD-II does not expose the gear selector. In TEST/mock mode we derive
    // a plausible gear from speed + RPM purely so the dashboard's P/R/N/D
    // indicator has something to show. In REAL/elm mode we display "—"
    // because we cannot infer the gear without a transmission CAN bus.
    readonly property string pseudoGear: {
        if (dataMode !== "mock") return "—"
        if (speedKph < 1) return "P"
        if (speedKph < 5 && rpm < 900) return "N"
        return "D"
    }

    // ── Misc ────────────────────────────────────────────────────────────────
    property double lastTs: 0

    // ── Stale data detection (Phase 3.0a) ───────────────────────────────────
    // dataStale becomes true when 3 s pass with no telemetry frame in ELM mode.
    // Drive.qml uses this to show the "Waiting for OBD-II device" banner.
    property bool dataStale: false

    readonly property bool noSourceConnected: dataMode === "elm" && dataStale

    Timer {
        id: staleTimer
        interval: 3000
        repeat: false
        onTriggered: root.dataStale = true
    }

    // ── Mode-switch state ───────────────────────────────────────────────────
    property bool   switching:      false
    property string lastModeError:  ""
    property string _requestedMode: ""

    // ── UI throttling (don't update QML bindings faster than ~20 Hz) ───────
    property int    uiUpdateMinMs:   50
    property double _lastUiUpdateMs: 0
    property bool   _loggedFirstMsg: false

    // ── Auto-reconnect ───────────────────────────────────────────────────────
    property int reconnectMs: 1000

    Timer {
        id: reconnectTimer
        interval: root.reconnectMs
        repeat:   false
        onTriggered: ws.active = true
    }

    // Safety net: if backend never confirms the switch, clear the spinner after 5s
    Timer {
        id: switchTimeout
        interval: 5000
        repeat:   false
        onTriggered: {
            if (root.switching) {
                console.warn("[VehicleDataProvider] mode switch timed out (5s, no confirmation)")
                root.switching      = false
                root._requestedMode = ""
            }
        }
    }

    // Auto-clear the error message 3s after it is shown
    Timer {
        id: errorClearTimer
        interval: 3000
        repeat:   false
        onTriggered: root.lastModeError = ""
    }

    // ── Public API ────────────────────────────────────────────────────────────
    //
    // sendModeCommand(mode)
    //   Called by Home.qml mode toggle.
    //   Sends {"cmd":"set_mode","mode":"mock"|"elm"} to obd_service.py.
    //   The backend hot-swaps providers. The next JSON frame will carry
    //   the new status ("mock" or "elm"), which updates dataMode here.
    //
    function sendModeCommand(mode) {
        if (!connected) {
            console.warn("[VehicleDataProvider] sendModeCommand: not connected, ignoring")
            return
        }
        if (mode !== "mock" && mode !== "elm") {
            console.warn("[VehicleDataProvider] sendModeCommand: unknown mode:", mode)
            return
        }
        console.log("[VehicleDataProvider] sendModeCommand →", mode)
        root.switching      = true
        root._requestedMode = mode
        root.lastModeError  = ""
        errorClearTimer.stop()
        switchTimeout.restart()
        ws.sendTextMessage(JSON.stringify({ cmd: "set_mode", mode: mode }))
    }

    // ── WebSocket ─────────────────────────────────────────────────────────────
    WebSocket {
        id: ws
        url: root.url
        active: true

        onStatusChanged: {
            const s = status === WebSocket.Open       ? "open"
                    : status === WebSocket.Connecting ? "connecting"
                    : status === WebSocket.Closing    ? "closing"
                    :                                   "closed"

            if (status !== WebSocket.Open)
                root.lastStatus = s

            console.log("[VehicleDataProvider] ws:", s, "  url=", root.url)

            if (status === WebSocket.Closed) {
                root.dataMode        = "unknown"
                root._loggedFirstMsg = false
                reconnectTimer.restart()
            }
        }

        onErrorStringChanged: {
            if (ws.errorString && ws.errorString.length > 0) {
                root.lastStatus = "error: " + ws.errorString
                console.log("[VehicleDataProvider] ws error:", ws.errorString)
            }
        }

        onTextMessageReceived: function(message) {
            let obj
            try { obj = JSON.parse(message) } catch (e) { return }

            // Throttle — skip frame if we updated too recently
            const nowMs = Date.now()
            if (nowMs - root._lastUiUpdateMs < root.uiUpdateMinMs) return
            root._lastUiUpdateMs = nowMs

            if (!root._loggedFirstMsg) {
                root._loggedFirstMsg = true
                console.log("[VehicleDataProvider] first frame — status:", obj.status)
            }

            // ── Telemetry fields ───────────────────────────────────────────
            if (obj.ts            !== undefined) root.lastTs       = Number(obj.ts)
            // Reset stale timer on any telemetry frame with real data fields
            if (obj.rpm !== undefined || obj.speed_kph !== undefined) {
                root.dataStale = false
                staleTimer.restart()
            }
            if (obj.rpm           !== undefined) root.rpm          = Number(obj.rpm)
            if (obj.speed_kph     !== undefined) root.speedKph     = Number(obj.speed_kph)
            if (obj.coolant_c     !== undefined) root.coolantC     = Number(obj.coolant_c)
            if (obj.throttle_pct  !== undefined) root.throttlePct  = Number(obj.throttle_pct)
            if (obj.engine_load   !== undefined) root.engineLoad   = Number(obj.engine_load)
            if (obj.battery_v     !== undefined) root.batteryV     = Number(obj.battery_v)
            if (obj.fuel_level    !== undefined) root.fuelLevel    = Number(obj.fuel_level)
            if (obj.intake_temp_c !== undefined) root.intakeTempC  = Number(obj.intake_temp_c)

            // ── Mode confirmation ──────────────────────────────────────────
            // obj.status is "mock" or "elm" — this drives the UI toggle and badge
            if (obj.status !== undefined) {
                const newMode = String(obj.status)
                root.dataMode   = newMode
                root.lastStatus = newMode

                // When switching to ELM, start the stale timer immediately;
                // mock mode is never considered stale.
                if (newMode === "elm") {
                    root.dataStale = false
                    staleTimer.restart()
                } else {
                    staleTimer.stop()
                    root.dataStale = false
                }

                // Backend confirmed the requested mode → clear switching spinner
                if (root.switching && root._requestedMode === newMode) {
                    root.switching      = false
                    root._requestedMode = ""
                    switchTimeout.stop()
                }
            }

            // ── Warning flags ──────────────────────────────────────────────
            if (obj.warnings) {
                root._wsCoolantHigh = !!obj.warnings.coolant_high
                root._wsOverspeed   = !!obj.warnings.overspeed
                root._wsLowFuel     = !!obj.warnings.low_fuel
                root._wsLowBattery  = !!obj.warnings.low_battery
            }

            // ── Mode switch error from backend ─────────────────────────────
            // Backend reverted to mock and sent mode_error.
            if (obj.mode_error !== undefined) {
                console.warn("[VehicleDataProvider] backend mode switch failed:", obj.mode_error)
                root.switching      = false
                root._requestedMode = ""
                root.lastModeError  = String(obj.mode_error)
                switchTimeout.stop()
                errorClearTimer.restart()
            }
        }
    }
}
