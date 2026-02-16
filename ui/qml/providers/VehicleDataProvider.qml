pragma Singleton
import QtQuick
import QtWebSockets

Item {
    id: root
    visible: false

    property string url: "ws://127.0.0.1:8765"

    property bool connected: (ws.status === WebSocket.Open)
    property string lastStatus: ""
    property string statusText: connected
                               ? (lastStatus.length ? lastStatus : "connected")
                               : (lastStatus.length ? lastStatus : "disconnected")

    property real rpm: 0
    property real speedKph: 0
    property real coolantC: 0
    property real throttlePct: 0

    property bool warnCoolantHigh: false
    property bool warnOverspeed: false
    property double lastTs: 0

    property int uiUpdateMinMs: 50
    property double _lastUiUpdateMs: 0
    property bool _loggedFirstMsg: false

    property int reconnectMs: 1000

    Timer {
        id: reconnectTimer
        interval: root.reconnectMs
        repeat: false
        onTriggered: ws.active = true
    }

    WebSocket {
        id: ws
        url: root.url
        active: true

        onStatusChanged: {
            root.lastStatus =
                    (status === WebSocket.Open) ? "open" :
                    (status === WebSocket.Connecting) ? "connecting" :
                    (status === WebSocket.Closing) ? "closing" :
                    "closed"

            console.log("[VehicleDataProvider] ws status:", root.lastStatus, "url=", root.url)

            if (status === WebSocket.Closed)
                reconnectTimer.restart()
        }

        onErrorStringChanged: {
            if (ws.errorString && ws.errorString.length) {
                root.lastStatus = "error: " + ws.errorString
                console.log("[VehicleDataProvider] ws error:", ws.errorString)
            }
        }

        onTextMessageReceived: function(message) {
            let obj
            try { obj = JSON.parse(message) } catch (e) { return }

            const nowMs = Date.now()
            if (nowMs - root._lastUiUpdateMs < root.uiUpdateMinMs) return
            root._lastUiUpdateMs = nowMs

            if (!root._loggedFirstMsg) {
                root._loggedFirstMsg = true
                console.log("[VehicleDataProvider] first msg:", message)
            }

            if (obj.ts !== undefined) root.lastTs = Number(obj.ts)
            if (obj.rpm !== undefined) root.rpm = Number(obj.rpm)
            if (obj.speed_kph !== undefined) root.speedKph = Number(obj.speed_kph)
            if (obj.coolant_c !== undefined) root.coolantC = Number(obj.coolant_c)
            if (obj.throttle_pct !== undefined) root.throttlePct = Number(obj.throttle_pct)

            if (obj.warnings) {
                root.warnCoolantHigh = !!obj.warnings.coolant_high
                root.warnOverspeed   = !!obj.warnings.overspeed
            }

            if (obj.status !== undefined)
                root.lastStatus = String(obj.status)
        }
    }
}
