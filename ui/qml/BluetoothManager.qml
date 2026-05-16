import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebSockets
import Veya 1.0

// ─────────────────────────────────────────────────────────────────────────────
// BluetoothManager — BT-Classic SPP pairing page.
// Mirrors WifiManager structurally. 1024×600.
// ─────────────────────────────────────────────────────────────────────────────

Page {
    id: root
    clip: true
    property var nav: null
    background: Rectangle { color: "transparent" }

    readonly property color cBg:     "#0B0F14"
    readonly property color cBorder: "#1A3040"
    readonly property color cBt:     "#4DD2FF"    // BT cyan accent
    readonly property color cText:   "white"
    readonly property color cWarn:   "#FF4D6D"
    readonly property color cGreen:  "#47FF9A"
    readonly property color cAmber:  "#FFB347"

    // ── State ────────────────────────────────────────────────────────────
    property bool   scanning:         false
    property bool   pairing:          false
    property string statusMessage:    ""
    property var    devices:          []          // scan results

    // Paired ESP32 info (from bt_bridge_status / bt_status)
    property string pairedMac:           ""
    property string pairedName:          ""
    property bool   bridgeRunning:       false
    property bool   esp32Connected:      false
    property bool   pairedDeviceInRange: false

    // Scan results filtered to exclude the already-paired device
    property var filteredDevices: {
        if (!root.pairedMac || root.pairedMac.length === 0) return root.devices
        const mac = root.pairedMac.toUpperCase()
        return root.devices.filter(function(d) {
            return (d.mac || "").toUpperCase() !== mac
        })
    }

    // Confirm-pair popup
    property bool   popupVisible:     false
    property string popupMac:         ""
    property string popupName:        ""

    Component.onDestruction: {
        // Pi becomes invisible again when the page is popped from the stack.
        root.sendCmd({ cmd: "bt_pairing_mode", enabled: false })
    }

    // ── WebSocket ─────────────────────────────────────────────────────────
    WebSocket {
        id: btWs
        url: "ws://127.0.0.1:8765"
        active: true

        onStatusChanged: {
            if (status === WebSocket.Open) {
                root.sendCmd({ cmd: "bt_pairing_mode", enabled: true })
                root.sendCmd({ cmd: "bt_status" })
                root.sendCmd({ cmd: "bt_bridge_status" })
                root.doScan()
            }
        }

        onTextMessageReceived: function(message) {
            let obj
            try { obj = JSON.parse(message) } catch(e) { return }
            const t = obj.type
            if (!t) return

            if (t === "bt_scan_result") {
                root.scanning = false
                if (obj.error && obj.error.length > 0) {
                    root.statusMessage = "Scan error: " + obj.error
                } else {
                    root.devices       = obj.devices || []
                    root.statusMessage = root.devices.length > 0
                        ? root.devices.length + " device(s) found"
                        : "No devices found"
                }
                // Refresh connection state of the paired device after every scan
                root.sendCmd({ cmd: "bt_status" })
            } else if (t === "bt_status") {
                const paired = obj.paired || []
                if (paired.length > 0) {
                    root.pairedMac           = paired[0].mac      || ""
                    root.pairedName          = paired[0].name     || ""
                    root.pairedDeviceInRange = paired[0].in_range || false
                } else {
                    root.pairedMac           = ""
                    root.pairedName          = ""
                    root.pairedDeviceInRange = false
                }
            } else if (t === "bt_bridge_status") {
                root.bridgeRunning  = obj.running        || false
                root.esp32Connected = obj.esp32_connected || false
            } else if (t === "bt_pair_result") {
                root.pairing = false
                if (obj.ok) {
                    root.statusMessage = "Pairing successful — starting bridge…"
                    root.popupVisible  = false
                    // Refresh status after 2 s
                    refreshDelay.start()
                } else {
                    root.statusMessage = "Pair failed: " + (obj.error || "unknown error")
                }
            } else if (t === "bt_unpair_result") {
                if (obj.ok) {
                    root.statusMessage  = "Device unpaired"
                    root.pairedMac      = ""
                    root.pairedName     = ""
                    root.bridgeRunning  = false
                    root.esp32Connected = false
                } else {
                    root.statusMessage = "Unpair failed: " + (obj.error || "")
                }
            } else if (t === "bt_disconnect_result") {
                if (obj.ok) {
                    root.statusMessage  = "Bridge stopped (device still paired)"
                    root.bridgeRunning  = false
                    root.esp32Connected = false
                } else {
                    root.statusMessage = "Disconnect failed: " + (obj.error || "")
                }
            }
        }

        onErrorStringChanged: {
            if (errorString && errorString.length > 0)
                console.warn("[BluetoothManager] ws error:", errorString)
        }
    }

    Timer {
        id: refreshDelay
        interval: 2000
        repeat: false
        onTriggered: {
            root.sendCmd({ cmd: "bt_status" })
            root.sendCmd({ cmd: "bt_bridge_status" })
        }
    }

    // 5-second "paired but not responding" check after pairing
    Timer {
        id: noResponseTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (!root.esp32Connected && root.bridgeRunning) {
                root.statusMessage = "Paired — ESP32 not responding yet"
            }
        }
    }

    function sendCmd(obj) {
        if (btWs.status === WebSocket.Open)
            btWs.sendTextMessage(JSON.stringify(obj))
        else
            console.warn("[BluetoothManager] WS not open:", JSON.stringify(obj))
    }

    function doScan() {
        root.scanning      = true
        root.statusMessage = "Scanning…"
        root.sendCmd({ cmd: "bt_scan" })
    }

    function doPair(mac, name) {
        root.pairing       = true
        root.statusMessage = "Pairing with " + (name || mac) + "…"
        root.sendCmd({ cmd: "bt_pair", mac: mac })
        noResponseTimer.start()
    }

    function doUnpair(mac) {
        root.statusMessage = "Unpairing…"
        root.sendCmd({ cmd: "bt_unpair", mac: mac })
    }

    function doDisconnect() {
        root.statusMessage = "Stopping bridge…"
        root.sendCmd({ cmd: "bt_disconnect" })
    }

    // ── Background ───────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0B0F14" }
            GradientStop { position: 1.0; color: "#070A0E" }
        }
        Repeater {
            model: 50
            Rectangle {
                width: 2; height: 2; radius: 1
                color: Qt.rgba(1, 1, 1, 0.07)
                x: Math.random() * parent.width
                y: Math.random() * parent.height
            }
        }
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: 8
        color: "transparent"
        border.color: root.cBorder; border.width: 2; radius: 24
    }

    // ── Main layout ───────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 0

        // Top bar
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.height * 0.09
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 92; Layout.preferredHeight: 36
                Layout.alignment: Qt.AlignVCenter
                radius: 8
                color: backMouse.containsMouse ? Qt.rgba(0.30, 0.82, 1, 0.14)
                                               : Qt.rgba(1, 1, 1, 0.05)
                border.color: Qt.rgba(1, 1, 1, 0.10); border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: "← Back"; color: root.cBt
                    font.pixelSize: 13; font.family: "DejaVu Sans"
                }
                MouseArea {
                    id: backMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.sendCmd({ cmd: "bt_pairing_mode", enabled: false })
                        if (root.nav) root.nav.pop()
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "BLUETOOTH"; color: root.cText
                font.pixelSize: 18; font.bold: true
                font.letterSpacing: 4; font.family: "DejaVu Sans"
            }

            Item { Layout.fillWidth: true }

            // Mode / Demo badges (same as WifiManager)
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: root.width * 0.28
                Layout.maximumWidth:   root.width * 0.30
                spacing: 4
                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: Math.min(btBadgeRow.implicitWidth + 16, root.width * 0.28)
                    radius: 14
                    color: VehicleDataProvider.connected
                           ? (VehicleDataProvider.dataMode === "elm"
                              ? Qt.rgba(0.47, 1, 0.60, 0.10)
                              : Qt.rgba(0.30, 0.82, 1, 0.10))
                           : Qt.rgba(1, 0.30, 0.43, 0.12)
                    border.color: VehicleDataProvider.connected
                                  ? (VehicleDataProvider.dataMode === "elm" ? "#47FF9A" : root.cBt)
                                  : root.cWarn
                    border.width: 1
                    Behavior on color        { ColorAnimation { duration: 400 } }
                    Behavior on border.color { ColorAnimation { duration: 400 } }
                    Row {
                        id: btBadgeRow
                        anchors.centerIn: parent; spacing: 6
                        Rectangle {
                            width: 7; height: 7; radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: VehicleDataProvider.connected
                                   ? (VehicleDataProvider.dataMode === "elm" ? "#47FF9A" : root.cBt)
                                   : root.cWarn
                            Behavior on color { ColorAnimation { duration: 400 } }
                        }
                        Text {
                            text: {
                                if (!VehicleDataProvider.connected) return "OFFLINE"
                                const m = VehicleDataProvider.dataMode
                                return m === "elm" ? "ELM" : m === "mock" ? "MOCK" : "—"
                            }
                            color: root.cText; font.pixelSize: 11; font.bold: true
                            font.letterSpacing: 1.4; font.family: "DejaVu Sans"
                        }
                    }
                }
                DemoBadge {
                    Layout.alignment: Qt.AlignRight
                    Layout.maximumWidth: root.width * 0.28
                }
            }
        }

        Item { Layout.preferredHeight: 8 }

        // ── Current ESP32 card ────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            radius: 12
            color: root.pairedDeviceInRange
                   ? Qt.rgba(0.278, 1.0, 0.604, 0.06)
                   : (root.pairedMac.length > 0
                      ? Qt.rgba(1.0, 0.70, 0.28, 0.04)
                      : Qt.rgba(1, 1, 1, 0.03))
            border.color: root.pairedDeviceInRange ? root.cGreen
                          : (root.pairedMac.length > 0 ? root.cAmber
                             : Qt.rgba(1,1,1,0.10))
            border.width: 1
            Behavior on color        { ColorAnimation { duration: 300 } }
            Behavior on border.color { ColorAnimation { duration: 300 } }

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                spacing: 10

                // Status dot
                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: root.pairedDeviceInRange ? root.cGreen
                           : (root.pairedMac.length > 0 ? root.cAmber : Qt.rgba(1,1,1,0.20))
                    Behavior on color { ColorAnimation { duration: 300 } }
                    SequentialAnimation on opacity {
                        running: root.pairedMac.length > 0 && !root.pairedDeviceInRange
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 700 }
                        NumberAnimation { to: 1.0; duration: 700 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text {
                        text: root.pairedMac.length > 0
                              ? (root.pairedName.length > 0 ? root.pairedName : "(unknown name)")
                              : "No OBD device paired"
                        color: root.pairedMac.length > 0 ? root.cText : Qt.rgba(1,1,1,0.35)
                        font.pixelSize: 14; font.bold: root.pairedDeviceInRange
                        font.family: "DejaVu Sans"; elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Text {
                        visible: root.pairedMac.length > 0
                        text: root.pairedDeviceInRange ? "Connected · " + root.pairedMac
                                                       : "Paired — not in range · " + root.pairedMac
                        color: root.pairedDeviceInRange ? Qt.rgba(0.278, 1.0, 0.604, 0.80)
                                                        : root.cAmber
                        font.pixelSize: 11; font.family: "DejaVu Sans"
                        Layout.fillWidth: true; elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: 300 } }
                    }
                }

                // Disconnect button (stops bridge, keeps pairing)
                Rectangle {
                    visible: root.bridgeRunning
                    width: 110; height: 32; radius: 16
                    color: discMouse.containsMouse
                           ? Qt.rgba(1, 0.71, 0.28, 0.22)
                           : Qt.rgba(1, 0.71, 0.28, 0.10)
                    border.color: root.cAmber; border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        anchors.centerIn: parent; text: "Disconnect"
                        color: root.cAmber; font.pixelSize: 12; font.family: "DejaVu Sans"
                    }
                    MouseArea {
                        id: discMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.doDisconnect()
                    }
                }

                // Unpair button
                Rectangle {
                    visible: root.pairedMac.length > 0 && !root.pairing
                    width: 80; height: 32; radius: 16
                    color: unpairMouse.containsMouse
                           ? Qt.rgba(1, 0.30, 0.43, 0.20)
                           : Qt.rgba(1, 0.30, 0.43, 0.10)
                    border.color: root.cWarn; border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        anchors.centerIn: parent; text: "Unpair"
                        color: root.cWarn; font.pixelSize: 12; font.family: "DejaVu Sans"
                    }
                    MouseArea {
                        id: unpairMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.doUnpair(root.pairedMac)
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 10 }

        // ── Section header + Refresh button ──────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 12

            Text {
                text: "Available Devices"
                color: Qt.rgba(1,1,1,0.60)
                font.pixelSize: 13; font.family: "DejaVu Sans"
                font.letterSpacing: 1.2
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 80; height: 30; radius: 15
                color: rScanMouse.containsMouse
                       ? Qt.rgba(0.30, 0.82, 1, 0.20)
                       : Qt.rgba(0.30, 0.82, 1, 0.10)
                border.color: root.cBt; border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }
                opacity: root.scanning ? 0.50 : 1.0
                Text {
                    anchors.centerIn: parent
                    text: root.scanning ? "…" : "⟳ Refresh"
                    color: root.cBt; font.pixelSize: 12; font.family: "DejaVu Sans"
                }
                MouseArea {
                    id: rScanMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!root.scanning) root.doScan()
                }
            }
        }

        Item { Layout.preferredHeight: 6 }

        // ── Device list ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: Qt.rgba(1,1,1,0.03)
            border.color: Qt.rgba(1,1,1,0.08); border.width: 1

            ListView {
                id: deviceList
                anchors { fill: parent; margins: 4 }
                clip: true
                model: root.filteredDevices
                spacing: 0

                delegate: Rectangle {
                    width: deviceList.width
                    height: 54
                    color: devMouse.containsMouse
                           ? Qt.rgba(0.30, 0.82, 1, 0.08) : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 10

                        // BT icon placeholder (simple "BT" text badge)
                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: Qt.rgba(0.30, 0.82, 1, 0.12)
                            border.color: Qt.rgba(0.30, 0.82, 1, 0.30); border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "BT"
                                color: root.cBt
                                font.pixelSize: 9; font.bold: true
                                font.family: "DejaVu Sans"
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 2
                            Text {
                                text: modelData.name && modelData.name.length > 0
                                      ? modelData.name : "(unknown device)"
                                color: root.cText
                                font.pixelSize: 14; font.family: "DejaVu Sans"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.mac || ""
                                color: Qt.rgba(1,1,1,0.40)
                                font.pixelSize: 11; font.family: "DejaVu Sans"
                            }
                        }

                        // Paired badge
                        Rectangle {
                            visible: modelData.paired || false
                            width: 60; height: 22; radius: 11
                            color: Qt.rgba(0.278, 1.0, 0.604, 0.12)
                            border.color: root.cGreen; border.width: 1
                            Text {
                                anchors.centerIn: parent; text: "Paired"
                                color: root.cGreen
                                font.pixelSize: 11; font.family: "DejaVu Sans"
                            }
                        }

                        // Pair button
                        Rectangle {
                            visible: !modelData.paired && !root.pairing
                            width: 72; height: 32; radius: 16
                            color: pairBtnMouse.containsMouse
                                   ? Qt.rgba(0.30, 0.82, 1, 0.24)
                                   : Qt.rgba(0.30, 0.82, 1, 0.12)
                            border.color: root.cBt; border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                anchors.centerIn: parent; text: "Pair"
                                color: root.cBt; font.pixelSize: 12; font.bold: true
                                font.family: "DejaVu Sans"
                            }
                            MouseArea {
                                id: pairBtnMouse; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.popupMac  = modelData.mac  || ""
                                    root.popupName = modelData.name || ""
                                    root.popupVisible = true
                                }
                            }
                        }
                    }

                    // Divider
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        anchors.leftMargin: 10; anchors.rightMargin: 10
                        height: 1; color: Qt.rgba(1,1,1,0.06)
                    }

                    MouseArea {
                        id: devMouse; anchors.fill: parent; hoverEnabled: true
                        // Whole row hoverable; button click handled by nested MouseArea
                    }
                }

                // Scanning overlay
                Text {
                    anchors.centerIn: parent
                    visible: root.scanning
                    text: "Scanning for devices…"
                    color: root.cBt; font.pixelSize: 14; font.family: "DejaVu Sans"
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: root.filteredDevices.length === 0 && !root.scanning
                    text: "No Bluetooth devices found"
                    color: Qt.rgba(1,1,1,0.30)
                    font.pixelSize: 14; font.family: "DejaVu Sans"
                }
            }
        }

        Item { Layout.preferredHeight: 8 }

        // ── Status footer ─────────────────────────────────────────────────
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: {
                if (root.esp32Connected)  return "Bridge running — ESP32 connected"
                if (root.bridgeRunning)   return "Bridge running — ESP32 reconnecting…"
                if (root.pairedMac.length > 0) return "Bridge stopped — tap Pair to restart"
                return root.statusMessage
            }
            color: {
                if (root.esp32Connected) return root.cGreen
                if (root.bridgeRunning)  return root.cAmber
                if (root.statusMessage.startsWith("Pair failed") ||
                    root.statusMessage.startsWith("Scan error") ||
                    root.statusMessage.startsWith("Unpair failed"))
                    return root.cWarn
                if (root.statusMessage.startsWith("Pairing") ||
                    root.statusMessage.startsWith("Paired"))
                    return root.cGreen
                return Qt.rgba(1,1,1,0.45)
            }
            font.pixelSize: 12; font.family: "DejaVu Sans"
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        Item { Layout.preferredHeight: 6 }
    }

    // ── Confirm-pair popup ────────────────────────────────────────────────
    Rectangle {
        id: confirmPopup
        anchors.centerIn: parent
        width: root.width * 0.44; height: 180
        radius: 16
        visible: root.popupVisible
        color: "#111922"
        border.color: root.cBt; border.width: 1

        // Dim overlay
        Rectangle {
            anchors.fill: parent.parent
            color: Qt.rgba(0,0,0,0.55); z: -1
            visible: root.popupVisible
            MouseArea { anchors.fill: parent; onClicked: root.popupVisible = false }
        }

        ColumnLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 12

            Text {
                text: "Pair with device?"
                color: root.cText; font.pixelSize: 15; font.bold: true
                font.family: "DejaVu Sans"
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: (root.popupName.length > 0 ? root.popupName + "\n" : "") + root.popupMac + "\n\nMake sure your OBD device is in pairing mode."
                color: Qt.rgba(1,1,1,0.65); font.pixelSize: 12
                font.family: "DejaVu Sans"
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 10

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 90; height: 36; radius: 18
                    color: popCancelMouse.containsMouse ? Qt.rgba(1,1,1,0.10) : Qt.rgba(1,1,1,0.05)
                    border.color: Qt.rgba(1,1,1,0.20); border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        anchors.centerIn: parent; text: "Cancel"
                        color: Qt.rgba(1,1,1,0.60); font.pixelSize: 13
                        font.family: "DejaVu Sans"
                    }
                    MouseArea {
                        id: popCancelMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.popupVisible = false
                    }
                }

                Rectangle {
                    width: 100; height: 36; radius: 18
                    color: popPairMouse.containsMouse
                           ? Qt.rgba(0.30, 0.82, 1, 0.28)
                           : Qt.rgba(0.30, 0.82, 1, 0.14)
                    border.color: root.cBt; border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        anchors.centerIn: parent; text: "Pair"
                        color: root.cBt; font.pixelSize: 13; font.bold: true
                        font.family: "DejaVu Sans"
                    }
                    MouseArea {
                        id: popPairMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.popupVisible = false
                            root.doPair(root.popupMac, root.popupName)
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }
}
