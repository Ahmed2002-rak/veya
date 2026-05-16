pragma Singleton
import QtQuick
import QtWebSockets

// ─────────────────────────────────────────────────────────────────────────────
// BluetoothStatusProvider — singleton, polls bt_bridge_status every 10 s.
// Exposes adapterPowered / esp32Connected / bridgeRunning so Home and other
// pages can show a BT indicator without opening BluetoothManager.
// Own WebSocket to ws://127.0.0.1:8765 — same pattern as WifiStatusProvider.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    visible: false

    property bool   adapterPowered:      false
    property bool   esp32Connected:      false
    property bool   bridgeRunning:       false
    property bool   pairedDeviceInRange: false
    property var    pairedDevices:       []   // [{mac, name, in_range}, …]

    // ── Poll timer ───────────────────────────────────────────────────────
    Timer {
        id: pollTimer
        interval: 10000
        repeat: true
        running: btStatusWs.status === WebSocket.Open
        onTriggered: root._poll()
    }

    // ── Auto-reconnect ───────────────────────────────────────────────────
    Timer {
        id: reconnectTimer
        interval: 3000
        repeat: false
        onTriggered: btStatusWs.active = true
    }

    // ── WebSocket ────────────────────────────────────────────────────────
    WebSocket {
        id: btStatusWs
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

            if (obj.type === "bt_status") {
                root.adapterPowered = obj.adapter_powered || false
                const pd = obj.paired || []
                root.pairedDevices       = pd
                root.pairedDeviceInRange = pd.length > 0 && (pd[0].in_range || false)
            } else if (obj.type === "bt_bridge_status") {
                root.bridgeRunning  = obj.running         || false
                root.esp32Connected = obj.esp32_connected || false
            }
        }

        onErrorStringChanged: {
            if (errorString && errorString.length > 0)
                console.warn("[BluetoothStatusProvider] ws error:", errorString)
        }
    }

    function _poll() {
        if (btStatusWs.status === WebSocket.Open) {
            btStatusWs.sendTextMessage(JSON.stringify({ cmd: "bt_status" }))
            btStatusWs.sendTextMessage(JSON.stringify({ cmd: "bt_bridge_status" }))
        }
    }

    function scan()           { _sendCmd({ cmd: "bt_scan" }) }
    function pair(mac)        { _sendCmd({ cmd: "bt_pair",   mac: mac }) }
    function unpair(mac)      { _sendCmd({ cmd: "bt_unpair", mac: mac }) }
    function disconnect()     { _sendCmd({ cmd: "bt_disconnect" }) }
    function refresh()        { _poll() }

    function _sendCmd(obj) {
        if (btStatusWs.status === WebSocket.Open)
            btStatusWs.sendTextMessage(JSON.stringify(obj))
    }
}
