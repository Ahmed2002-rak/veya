pragma Singleton
import QtQuick
import QtWebSockets

// ─────────────────────────────────────────────────────────────────────────────
// UserProfile — singleton, owns its own WebSocket to the core.
//
// On startup it sends {"cmd":"load_profile"} and populates fields from the
// response. saveProfile() sends {"cmd":"save_profile","data":{...}}.
//
// The core's ws_server.py handles these commands (added in Phase 2.2b).
// This does NOT share VehicleDataProvider's WebSocket to keep concerns
// separate; the server simply ignores unknown-type frames from each client.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    visible: false

    // ── Profile fields ───────────────────────────────────────────────────
    property string driverName:       ""
    property string emergencyContact: ""
    property string carMake:          ""
    property string carModel:         ""
    property string carYear:          ""
    property string carFuelType:      ""   // "Gasoline" | "Diesel" | "Hybrid" | "Electric"
    property string carVIN:           ""   // optional — empty string if not provided

    // ── State ────────────────────────────────────────────────────────────
    property bool   profileExists: false
    property bool   loading:       true
    property string loadError:     ""

    signal saveResult(bool ok, string message)

    // ── Connection timeout ───────────────────────────────────────────────
    // If the WS never opens within 3 s we degrade gracefully (no profile →
    // onboarding will run, which is the safe default).
    Timer {
        id: connectTimeout
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.loading) {
                console.warn("[UserProfile] WS connect timeout — defaulting to no profile")
                root.loading       = false
                root.profileExists = false
                root.loadError     = ""
            }
        }
    }

    // ── Auto-reconnect ───────────────────────────────────────────────────
    Timer {
        id: reconnectTimer
        interval: 2000
        repeat: false
        onTriggered: profileWs.active = true
    }

    // ── WebSocket ────────────────────────────────────────────────────────
    WebSocket {
        id: profileWs
        url: "ws://127.0.0.1:8765"
        active: true

        onStatusChanged: {
            if (status === WebSocket.Open) {
                connectTimeout.stop()
                profileWs.sendTextMessage(JSON.stringify({ cmd: "load_profile" }))
            } else if (status === WebSocket.Closed) {
                if (root.loading) {
                    // Backend not up yet — reconnect timer will retry
                    reconnectTimer.start()
                }
            }
        }

        onErrorStringChanged: {
            if (errorString && errorString.length > 0) {
                console.warn("[UserProfile] ws error:", errorString)
                if (root.loading) {
                    connectTimeout.stop()
                    root.loading       = false
                    root.profileExists = false
                    root.loadError     = ""
                }
            }
        }

        onTextMessageReceived: function(message) {
            let obj
            try { obj = JSON.parse(message) } catch(e) { return }

            // Ignore telemetry frames (they have "schema" not "type")
            if (!obj.type) return

            if (obj.type === "profile_data") {
                const d = obj.data || {}
                root.driverName       = d.driverName       || ""
                root.emergencyContact = d.emergencyContact || ""
                root.carMake          = d.carMake          || ""
                root.carModel         = d.carModel         || ""
                root.carYear          = d.carYear          || ""
                root.carFuelType      = d.carFuelType      || ""
                root.carVIN           = d.carVIN           || ""
                root.profileExists    = (root.driverName.length > 0)
                root.loading          = false
                root.loadError        = obj.error || ""
                console.log("[UserProfile] profile loaded, exists=", root.profileExists)
            } else if (obj.type === "profile_saved") {
                if (obj.ok) {
                    root.profileExists = true
                    root.saveResult(true, "Profile saved.")
                    console.log("[UserProfile] profile saved OK")
                } else {
                    root.saveResult(false, "Save failed: " + (obj.error || "unknown"))
                    console.warn("[UserProfile] profile save failed:", obj.error)
                }
            }
        }
    }

    // ── Public API ────────────────────────────────────────────────────────

    function saveProfile() {
        const data = {
            driverName:       root.driverName,
            emergencyContact: root.emergencyContact,
            carMake:          root.carMake,
            carModel:         root.carModel,
            carYear:          root.carYear,
            carFuelType:      root.carFuelType,
            carVIN:           root.carVIN,
            savedAt:          new Date().toISOString()
        }
        if (profileWs.status === WebSocket.Open) {
            profileWs.sendTextMessage(JSON.stringify({ cmd: "save_profile", data: data }))
        } else {
            console.warn("[UserProfile] saveProfile: WS not connected")
            root.saveResult(false, "Not connected to backend")
        }
    }

    function loadProfile() {
        if (profileWs.status === WebSocket.Open) {
            root.loading = true
            profileWs.sendTextMessage(JSON.stringify({ cmd: "load_profile" }))
        }
    }

    Component.onCompleted: connectTimeout.start()
}
