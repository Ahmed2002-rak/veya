import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebSockets
import Veya 1.0

Page {
    id: root
    clip: true
    property var nav: null
    background: Rectangle { color: "transparent" }

    readonly property color cBg:     "#0B0F14"
    readonly property color cBorder: "#1A4040"
    readonly property color cCyan:   "#4DD2FF"
    readonly property color cText:   "white"
    readonly property color cWarn:   "#FF4D6D"
    readonly property color cGreen:  "#47FF9A"

    // ── State ────────────────────────────────────────────────────────────
    property bool   scanning:         false
    property bool   connecting:       false
    property string statusMessage:    ""
    property string currentSSID:      ""
    property bool   currentConnected: false
    property var    networks:         []

    // Connect popup state
    property bool   popupVisible:  false
    property string popupSSID:     ""
    property string popupPassword: ""

    // On-screen keyboard state
    property bool   kbVisible: false

    // ── WebSocket ─────────────────────────────────────────────────────────
    // Own connection — separate from VehicleDataProvider to keep concerns clean.
    WebSocket {
        id: wifiWs
        url: "ws://127.0.0.1:8765"
        active: true

        onStatusChanged: {
            if (status === WebSocket.Open) {
                root.sendCmd({ cmd: "wifi_status" })
                root.doScan()
            }
        }

        onTextMessageReceived: function(message) {
            let obj
            try { obj = JSON.parse(message) } catch(e) { return }

            // Only handle Wi-Fi response frames (ignore telemetry frames)
            const t = obj.type
            if (!t) return

            if (t === "wifi_scan_result") {
                root.scanning = false
                if (obj.error && obj.error.length > 0) {
                    root.statusMessage = "Scan error: " + obj.error
                } else {
                    root.networks      = obj.networks || []
                    root.statusMessage = root.networks.length > 0
                        ? root.networks.length + " networks found"
                        : "No networks found"
                }
            } else if (t === "wifi_status") {
                root.currentConnected = obj.connected || false
                root.currentSSID      = obj.ssid      || ""
            } else if (t === "wifi_connect_result") {
                root.connecting = false
                if (obj.ok) {
                    root.statusMessage    = 'Connected to "' + root.popupSSID + '"'
                    root.currentSSID      = root.popupSSID
                    root.currentConnected = true
                    root.popupVisible     = false
                    root.kbVisible        = false
                    wifiKeyboard.hide()
                    // Refresh status to get real device info
                    root.sendCmd({ cmd: "wifi_status" })
                } else {
                    root.statusMessage = "Failed: " + (obj.error || "unknown error")
                }
            } else if (t === "wifi_disconnect_result") {
                if (obj.ok) {
                    root.statusMessage    = "Disconnected"
                    root.currentSSID      = ""
                    root.currentConnected = false
                    root.networks         = []
                } else {
                    root.statusMessage = "Disconnect failed: " + (obj.error || "")
                }
            }
        }

        onErrorStringChanged: {
            if (errorString && errorString.length > 0)
                console.warn("[WifiManager] ws error:", errorString)
        }
    }

    function sendCmd(obj) {
        if (wifiWs.status === WebSocket.Open) {
            wifiWs.sendTextMessage(JSON.stringify(obj))
        } else {
            console.warn("[WifiManager] WS not open, cannot send:", JSON.stringify(obj))
        }
    }

    function doScan() {
        root.scanning      = true
        root.statusMessage = "Scanning…"
        root.sendCmd({ cmd: "wifi_scan" })
    }

    function doConnect(ssid, password) {
        root.connecting    = true
        root.statusMessage = 'Connecting to "' + ssid + '"...'
        root.sendCmd({ cmd: "wifi_connect", ssid: ssid, password: password })
    }

    function doDisconnect() {
        root.statusMessage = "Disconnecting…"
        root.sendCmd({ cmd: "wifi_disconnect" })
    }

    Component.onCompleted: {
        // scan is fired in onStatusChanged once WS is open
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
                    text: "← Back"; color: root.cCyan
                    font.pixelSize: 13; font.family: "DejaVu Sans"
                }
                MouseArea {
                    id: backMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.nav) root.nav.pop()
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "WI-FI"; color: root.cText
                font.pixelSize: 18; font.bold: true
                font.letterSpacing: 4; font.family: "DejaVu Sans"
            }

            Item { Layout.fillWidth: true }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: root.width * 0.28
                Layout.maximumWidth:   root.width * 0.30
                spacing: 4
                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: Math.min(wfBadgeRow.implicitWidth + 16, root.width * 0.28)
                    radius: 14
                    color: VehicleDataProvider.connected
                           ? (VehicleDataProvider.dataMode === "elm"
                              ? Qt.rgba(0.47, 1, 0.60, 0.10)
                              : Qt.rgba(0.30, 0.82, 1, 0.10))
                           : Qt.rgba(1, 0.30, 0.43, 0.12)
                    border.color: VehicleDataProvider.connected
                                  ? (VehicleDataProvider.dataMode === "elm" ? "#47FF9A" : root.cCyan)
                                  : root.cWarn
                    border.width: 1
                    Behavior on color        { ColorAnimation { duration: 400 } }
                    Behavior on border.color { ColorAnimation { duration: 400 } }
                    Row {
                        id: wfBadgeRow
                        anchors.centerIn: parent; spacing: 6
                        Rectangle {
                            width: 7; height: 7; radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: VehicleDataProvider.connected
                                   ? (VehicleDataProvider.dataMode === "elm" ? "#47FF9A" : root.cCyan)
                                   : root.cWarn
                            Behavior on color { ColorAnimation { duration: 400 } }
                            SequentialAnimation on opacity {
                                running: !VehicleDataProvider.connected; loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
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

        // ── Current connection card ───────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            radius: 12
            color: root.currentConnected
                   ? Qt.rgba(0.278, 1.0, 0.604, 0.06)
                   : Qt.rgba(1, 1, 1, 0.04)
            border.color: root.currentConnected ? root.cGreen : Qt.rgba(1,1,1,0.12)
            border.width: 1
            Behavior on color        { ColorAnimation { duration: 300 } }
            Behavior on border.color { ColorAnimation { duration: 300 } }

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                spacing: 10

                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: root.currentConnected ? root.cGreen : Qt.rgba(1,1,1,0.25)
                    Behavior on color { ColorAnimation { duration: 300 } }
                    SequentialAnimation on opacity {
                        running: root.connecting; loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: 500 }
                        NumberAnimation { to: 1.0; duration: 500 }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    Text {
                        text: root.currentConnected ? root.currentSSID : "Not connected"
                        color: root.currentConnected ? root.cText : Qt.rgba(1,1,1,0.45)
                        font.pixelSize: 15; font.bold: root.currentConnected
                        font.family: "DejaVu Sans"
                    }
                    Text {
                        visible: root.connecting
                        text: "Connecting…"; color: root.cCyan
                        font.pixelSize: 12; font.family: "DejaVu Sans"
                    }
                }

                // Disconnect button
                Rectangle {
                    visible: root.currentConnected && !root.connecting
                    width: 100; height: 32; radius: 16
                    color: discMouse.containsMouse
                           ? Qt.rgba(1, 0.30, 0.43, 0.20)
                           : Qt.rgba(1, 0.30, 0.43, 0.10)
                    border.color: root.cWarn; border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        anchors.centerIn: parent
                        text: "Disconnect"; color: root.cWarn
                        font.pixelSize: 12; font.family: "DejaVu Sans"
                    }
                    MouseArea {
                        id: discMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.doDisconnect()
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 10 }

        // ── Scan button + header ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: "Available Networks"
                color: Qt.rgba(1,1,1,0.60)
                font.pixelSize: 13; font.family: "DejaVu Sans"
                font.letterSpacing: 1.2
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 80; height: 30; radius: 15
                color: scanMouse.containsMouse
                       ? Qt.rgba(0.30, 0.82, 1, 0.20)
                       : Qt.rgba(0.30, 0.82, 1, 0.10)
                border.color: root.cCyan; border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }
                opacity: root.scanning ? 0.50 : 1.0
                Text {
                    anchors.centerIn: parent
                    text: root.scanning ? "…" : "⟳ Refresh"
                    color: root.cCyan; font.pixelSize: 12
                    font.family: "DejaVu Sans"
                }
                MouseArea {
                    id: scanMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (!root.scanning) root.doScan()
                }
            }
        }

        Item { Layout.preferredHeight: 6 }

        // ── Network list ──────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: Qt.rgba(1,1,1,0.03)
            border.color: Qt.rgba(1,1,1,0.08); border.width: 1

            ListView {
                id: networkList
                anchors { fill: parent; margins: 4 }
                clip: true
                model: root.networks
                spacing: 0

                delegate: Rectangle {
                    width: networkList.width
                    property bool isActive: modelData.ssid === root.currentSSID
                    visible: !isActive
                    height: isActive ? 0 : 52
                    color: netMouse.containsMouse
                           ? Qt.rgba(0.30, 0.82, 1, 0.08) : "transparent"
                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 10

                        // Signal strength bar
                        Column {
                            spacing: 2
                            Layout.alignment: Qt.AlignVCenter
                            Repeater {
                                model: 4
                                Rectangle {
                                    width: 4
                                    height: 4 + index * 3
                                    radius: 1
                                    color: modelData.signal >= (index + 1) * 25
                                           ? root.cCyan
                                           : Qt.rgba(1,1,1,0.18)
                                    anchors.bottom: parent ? parent.bottom : undefined
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.ssid
                            color: root.cText
                            font.pixelSize: 14; font.family: "DejaVu Sans"
                            elide: Text.ElideRight
                        }

                        Text {
                            text: modelData.signal + "%"
                            color: Qt.rgba(1,1,1,0.45)
                            font.pixelSize: 12; font.family: "DejaVu Sans"
                        }

                        Text {
                            visible: modelData.secured
                            text: "🔒"
                            font.pixelSize: 14
                            opacity: 0.60
                        }
                    }

                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        anchors.leftMargin: 10; anchors.rightMargin: 10
                        height: 1; color: Qt.rgba(1,1,1,0.06)
                    }

                    MouseArea {
                        id: netMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.popupSSID     = modelData.ssid
                            root.popupPassword = ""
                            root.popupVisible  = true
                        }
                    }
                }

                // Scanning overlay
                Text {
                    anchors.centerIn: parent
                    visible: root.scanning
                    text: "Scanning…"
                    color: root.cCyan
                    font.pixelSize: 14; font.family: "DejaVu Sans"
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: root.networks.length === 0 && !root.scanning
                    text: "No networks found"
                    color: Qt.rgba(1,1,1,0.30)
                    font.pixelSize: 14; font.family: "DejaVu Sans"
                }
            }
        }

        Item { Layout.preferredHeight: 8 }

        // ── Status footer ─────────────────────────────────────────────────
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.statusMessage
            color: root.statusMessage.startsWith("Failed") || root.statusMessage.startsWith("Scan error")
                   ? root.cWarn
                   : (root.statusMessage.startsWith("Connected")
                      ? root.cGreen
                      : Qt.rgba(1,1,1,0.45))
            font.pixelSize: 12; font.family: "DejaVu Sans"
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        Item { Layout.preferredHeight: 6 }
    }

    // ── Connect popup ─────────────────────────────────────────────────────
    Rectangle {
        id: connectPopup
        anchors.centerIn: parent
        // Shift the popup up when the keyboard is visible so password field stays visible
        anchors.verticalCenterOffset: root.kbVisible ? -140 : 0
        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        width: root.width * 0.44
        height: 220
        radius: 16
        visible: root.popupVisible
        color: "#111922"
        border.color: root.cCyan; border.width: 1

        // Dim overlay behind
        Rectangle {
            anchors.fill: parent.parent   // fills the page
            color: Qt.rgba(0,0,0,0.55)
            z: -1
            visible: root.popupVisible
            MouseArea { anchors.fill: parent; onClicked: root.popupVisible = false }
        }

        ColumnLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: root.popupSSID
                color: root.cText; font.pixelSize: 16; font.bold: true
                font.family: "DejaVu Sans"; elide: Text.ElideRight
            }

            TextField {
                id: passField
                Layout.fillWidth: true
                placeholderText: "Password (leave blank if open)"
                echoMode: TextInput.Password
                text: root.popupPassword
                font.pixelSize: 14; font.family: "DejaVu Sans"
                color: root.cText
                placeholderTextColor: Qt.rgba(1,1,1,0.30)
                onTextChanged: root.popupPassword = text
                background: Rectangle {
                    color: Qt.rgba(1,1,1,0.06)
                    border.color: passField.activeFocus ? root.cCyan : Qt.rgba(1,1,1,0.18)
                    border.width: 1; radius: 8
                }
                leftPadding: 10; rightPadding: 10
                onActiveFocusChanged: {
                    if (activeFocus) {
                        root.kbVisible = true
                        wifiKeyboard.show(passField)
                    }
                }
                Keys.onReturnPressed: root.doConnect(root.popupSSID, root.popupPassword)
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 10

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 90; height: 36; radius: 18
                    color: cancelMouse.containsMouse ? Qt.rgba(1,1,1,0.10) : Qt.rgba(1,1,1,0.05)
                    border.color: Qt.rgba(1,1,1,0.20); border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        anchors.centerIn: parent; text: "Cancel"
                        color: Qt.rgba(1,1,1,0.60)
                        font.pixelSize: 13; font.family: "DejaVu Sans"
                    }
                    MouseArea {
                        id: cancelMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.popupVisible = false
                            root.kbVisible = false
                            wifiKeyboard.hide()
                        }
                    }
                }

                Rectangle {
                    width: 100; height: 36; radius: 18
                    color: connMouse.containsMouse
                           ? Qt.rgba(0.30, 0.82, 1, 0.28)
                           : Qt.rgba(0.30, 0.82, 1, 0.14)
                    border.color: root.cCyan; border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        anchors.centerIn: parent; text: "Connect"
                        color: root.cCyan; font.pixelSize: 13; font.bold: true
                        font.family: "DejaVu Sans"
                    }
                    MouseArea {
                        id: connMouse; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.doConnect(root.popupSSID, root.popupPassword)
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }
    }

    // ── On-screen keyboard for password entry ─────────────────────────────
    OnScreenKeyboard {
        id: wifiKeyboard
        anchors.fill: parent
        onDoneClicked: {
            root.kbVisible = false
            wifiKeyboard.hide()
        }
    }
}
