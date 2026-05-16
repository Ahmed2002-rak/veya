pragma Singleton
import QtQuick
import QtWebSockets

// ─────────────────────────────────────────────────────────────────────────────
// WifiStatusProvider — singleton, polls wifi_status every 10 s.
// Exposes connected/ssid so Home and any other page can show a Wi-Fi dot
// without opening WifiManager.
// Own WebSocket to ws://127.0.0.1:8765 (same pattern as UserProfile).
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    visible: false

    property bool   connected: false
    property string ssid:      ""

    // ── Poll timer ───────────────────────────────────────────────────────
    Timer {
        id: pollTimer
        interval: 10000
        repeat: true
        running: wifiStatusWs.status === WebSocket.Open
        onTriggered: root._poll()
    }

    // ── Auto-reconnect ───────────────────────────────────────────────────
    Timer {
        id: reconnectTimer
        interval: 3000
        repeat: false
        onTriggered: wifiStatusWs.active = true
    }

    // ── WebSocket ────────────────────────────────────────────────────────
    WebSocket {
        id: wifiStatusWs
        url: "ws://127.0.0.1:8765"
        active: true

        onStatusChanged: {
            if (status === WebSocket.Open) {
                root._poll()
            } else if (status === WebSocket.Closed) {
                reconnectTimer.start()
            }
        }

        onTextMessageReceived: function(message) {
            let obj
            try { obj = JSON.parse(message) } catch(e) { return }
            if (obj.type === "wifi_status") {
                root.connected = obj.connected || false
                root.ssid      = obj.ssid      || ""
            }
        }

        onErrorStringChanged: {
            if (errorString && errorString.length > 0)
                console.warn("[WifiStatusProvider] ws error:", errorString)
        }
    }

    function _poll() {
        if (wifiStatusWs.status === WebSocket.Open)
            wifiStatusWs.sendTextMessage(JSON.stringify({ cmd: "wifi_status" }))
    }
}
