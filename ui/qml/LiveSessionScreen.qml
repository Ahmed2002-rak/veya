import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebSockets
import Veya 1.0

Page {
    id: root
    width: parent.width
    height: parent.height
    clip: true

    property var nav: null

    background: Rectangle { color: "transparent" }

    readonly property color cBorder: "#1A4040"
    readonly property color cCyan:   "#4DD2FF"
    readonly property color cText:   "white"
    readonly property color cWarn:   "#FF4D6D"
    readonly property color cGreen:  "#47FF9A"

    property string liveSessionState: "stopped"

    // ── Server config (Phase 3.0a) ───────────────────────────────────────
    property string liveUrl: ""

    readonly property string buttonTooltip: {
        if (liveUrl.length === 0) return "Server not configured — run set_server_url.py live <url>"
        return "Server unreachable — check network connection"
    }

    function sendCmd(obj) {
        if (liveConfigWs.status === WebSocket.Open)
            liveConfigWs.sendTextMessage(JSON.stringify(obj))
    }

    WebSocket {
        id: liveConfigWs
        url: "ws://127.0.0.1:8765"
        active: true
        onStatusChanged: {
            if (status === WebSocket.Open) {
                liveConfigWs.sendTextMessage(JSON.stringify({ cmd: "load_server_config" }))
                liveConfigWs.sendTextMessage(JSON.stringify({ cmd: "live_session_status" }))
            }
        }
        onTextMessageReceived: function(message) {
            let obj
            try { obj = JSON.parse(message) } catch(e) { return }
            if (obj.type === "server_config") {
                root.liveUrl = (obj.data && obj.data.live_session_url) ? obj.data.live_session_url : ""
            }
            if (obj.type === "live_session_status" && obj.state !== undefined) {
                root.liveSessionState = obj.state
            }
        }
    }

    // ── Background ───────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0B0F14" }
            GradientStop { position: 1.0; color: "#070A0E" }
        }
        Repeater {
            model: 60
            Rectangle {
                width: 2; height: 2; radius: 1
                color: Qt.rgba(1, 1, 1, 0.07)
                x: Math.random() * parent.width
                y: Math.random() * parent.height
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        color: "transparent"
        border.color: root.cBorder; border.width: 2
        radius: 24
    }

    // ════════════════════════════════════════════════════════════════════
    //  MAIN LAYOUT
    // ════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 0

        // ── TOP STRIP ─────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.height * 0.08
            spacing: 12

            Rectangle {
                Layout.preferredWidth: 92
                Layout.preferredHeight: 36
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
                    id: backMouse
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.nav) root.nav.pop()
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "LIVE SESSION"
                color: root.cText
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
                    Layout.preferredWidth: Math.min(lBadgeRow.implicitWidth + 22, root.width * 0.28)
                    radius: 14
                    color: {
                        if (!VehicleDataProvider.connected)
                            return Qt.rgba(1, 0.30, 0.43, 0.12)
                        return VehicleDataProvider.dataMode === "elm"
                            ? Qt.rgba(0.47, 1, 0.60, 0.10)
                            : Qt.rgba(0.30, 0.82, 1, 0.10)
                    }
                    border.color: {
                        if (!VehicleDataProvider.connected) return root.cWarn
                        return VehicleDataProvider.dataMode === "elm"
                            ? "#47FF9A" : root.cCyan
                    }
                    border.width: 1
                    Behavior on color        { ColorAnimation { duration: 400 } }
                    Behavior on border.color { ColorAnimation { duration: 400 } }

                    Row {
                        id: lBadgeRow
                        anchors.centerIn: parent
                        spacing: 7

                        Rectangle {
                            width: 7; height: 7; radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: {
                                if (!VehicleDataProvider.connected) return root.cWarn
                                return VehicleDataProvider.dataMode === "elm"
                                    ? "#47FF9A" : root.cCyan
                            }
                            SequentialAnimation on opacity {
                                running: !VehicleDataProvider.connected
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
                        }

                        Text {
                            text: {
                                if (!VehicleDataProvider.connected) return "OFFLINE"
                                const m = VehicleDataProvider.dataMode
                                return m === "elm"  ? "ELM"
                                     : m === "mock" ? "MOCK"
                                     :                "—"
                            }
                            color: root.cText
                            font.pixelSize: 11; font.bold: true
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

        // ── Center content ────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                width: root.width * 0.65
                spacing: 22

                // Connection state badge — dynamic
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 240; height: 56
                    radius: 14
                    color: {
                        if (root.liveSessionState === "connected_active")  return Qt.rgba(0.28, 1, 0.60, 0.12)
                        if (root.liveSessionState === "connected_idle")    return Qt.rgba(0.302, 0.824, 1, 0.10)
                        if (root.liveSessionState === "connecting")        return Qt.rgba(1, 0.76, 0.03, 0.12)
                        return Qt.rgba(1, 1, 1, 0.04)
                    }
                    border.color: {
                        if (root.liveSessionState === "connected_active")  return root.cGreen
                        if (root.liveSessionState === "connected_idle")    return root.cCyan
                        if (root.liveSessionState === "connecting")        return root.cWarn
                        return Qt.rgba(1, 1, 1, 0.15)
                    }
                    border.width: 1
                    Behavior on color        { ColorAnimation { duration: 400 } }
                    Behavior on border.color { ColorAnimation { duration: 400 } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 10

                        Rectangle {
                            width: 10; height: 10; radius: 5
                            anchors.verticalCenter: parent.verticalCenter
                            color: {
                                if (root.liveSessionState === "connected_active")  return root.cGreen
                                if (root.liveSessionState === "connected_idle")    return root.cCyan
                                if (root.liveSessionState === "connecting")        return root.cWarn
                                return "#6B7A8A"
                            }
                            Behavior on color { ColorAnimation { duration: 300 } }
                            SequentialAnimation on opacity {
                                running: root.liveSessionState === "connecting"
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                                onRunningChanged: { if (!running) parent.opacity = 1.0 }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (root.liveSessionState === "connected_active") return "LIVE — expert connected"
                                if (root.liveSessionState === "connected_idle")   return "Connected — waiting"
                                if (root.liveSessionState === "connecting")       return "Connecting…"
                                if (root.liveSessionState === "disconnected")     return "Disconnected"
                                return "Offline"
                            }
                            color: root.cText
                            font.pixelSize: 14; font.bold: true
                            font.family: "DejaVu Sans"
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Live Expert Session"
                    color: root.cText
                    font.pixelSize: 24; font.bold: true
                    font.family: "DejaVu Sans"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: root.width * 0.6
                    text: "When you start a session, a certified technician will see your car's live data and guide you through diagnosis."
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: 14; font.family: "DejaVu Sans"
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                // 2-column info grid
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: root.width * 0.58
                    height: infoGrid.implicitHeight + 28
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.03)
                    border.color: Qt.rgba(1, 1, 1, 0.08); border.width: 1

                    GridLayout {
                        id: infoGrid
                        anchors { left: parent.left; right: parent.right; margins: 16 }
                        anchors.verticalCenter: parent.verticalCenter
                        columns: 2
                        rowSpacing: 10
                        columnSpacing: 12

                        // Row 1
                        Text { text: "Live telemetry stream";    color: root.cText;              font.pixelSize: 13; font.family: "DejaVu Sans" }
                        Text { text: "Real-time car data";       color: Qt.rgba(1,1,1,0.5);      font.pixelSize: 13; font.family: "DejaVu Sans" }
                        // Row 2
                        Text { text: "Diagnostic codes (DTCs)";  color: root.cText;              font.pixelSize: 13; font.family: "DejaVu Sans" }
                        Text { text: "Read on request";          color: Qt.rgba(1,1,1,0.5);      font.pixelSize: 13; font.family: "DejaVu Sans" }
                        // Row 3
                        Text { text: "Remote PID queries";       color: root.cText;              font.pixelSize: 13; font.family: "DejaVu Sans" }
                        Text { text: "Expert can probe sensors"; color: Qt.rgba(1,1,1,0.5);      font.pixelSize: 13; font.family: "DejaVu Sans" }
                        // Row 4
                        Text { text: "Two-way text channel";     color: root.cText;              font.pixelSize: 13; font.family: "DejaVu Sans" }
                        Text { text: "Expert can give instructions"; color: Qt.rgba(1,1,1,0.5); font.pixelSize: 13; font.family: "DejaVu Sans" }
                    }
                }
            }
        }

        // ── Start / Stop Session button ───────────────────────────────────
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 20
            width: root.width * 0.4
            height: 50

            property bool isRunning: root.liveSessionState === "connecting"
                                  || root.liveSessionState === "connected_idle"
                                  || root.liveSessionState === "connected_active"

            property bool canStart: root.liveUrl.length > 0

            Rectangle {
                anchors.fill: parent
                radius: 10
                opacity: (!parent.canStart && !parent.isRunning) ? 0.4 : 1.0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                color: {
                    if (!parent.canStart && !parent.isRunning) return Qt.rgba(1, 1, 1, 0.04)
                    if (parent.isRunning) return Qt.rgba(1, 0.30, 0.43, 0.10)
                    return Qt.rgba(0.28, 1, 0.60, 0.10)
                }
                border.color: {
                    if (!parent.canStart && !parent.isRunning) return Qt.rgba(1, 1, 1, 0.10)
                    if (parent.isRunning) return root.cWarn
                    return root.cGreen
                }
                border.width: 1
                Behavior on color        { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                Text {
                    anchors.centerIn: parent
                    text: parent.parent.isRunning ? "Stop Session" : "Start Session"
                    color: {
                        if (!parent.parent.canStart && !parent.parent.isRunning) return Qt.rgba(1, 1, 1, 0.5)
                        if (parent.parent.isRunning) return root.cWarn
                        return root.cGreen
                    }
                    font.pixelSize: 16; font.bold: true; font.family: "DejaVu Sans"
                }
            }

            ToolTip {
                visible: btnMouse.containsMouse && !parent.canStart && !parent.isRunning
                text: root.buttonTooltip
            }

            MouseArea {
                id: btnMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: (!parent.canStart && !parent.isRunning)
                             ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                onClicked: {
                    if (!parent.canStart && !parent.isRunning) return
                    if (parent.isRunning) {
                        root.sendCmd({ cmd: "live_session_stop" })
                    } else {
                        root.sendCmd({ cmd: "live_session_start" })
                    }
                }
            }
        }
    }
}
