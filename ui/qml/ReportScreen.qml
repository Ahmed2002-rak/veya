import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
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
    readonly property color cDim:    Qt.rgba(1, 1, 1, 0.6)

    // ── Server config (Phase 3.0a) ───────────────────────────────────────
    property string reportUrl: ""

    readonly property string buttonTooltip: {
        if (reportUrl.length === 0) return "Server not configured — run set_server_url.py report <url>"
        return "Server unreachable — check network connection"
    }

    WebSocket {
        id: reportConfigWs
        url: "ws://127.0.0.1:8765"
        active: true
        onStatusChanged: {
            if (status === WebSocket.Open)
                reportConfigWs.sendTextMessage(JSON.stringify({ cmd: "load_server_config" }))
        }
        onTextMessageReceived: function(message) {
            let obj
            try { obj = JSON.parse(message) } catch(e) { return }
            if (obj.type === "server_config") {
                root.reportUrl = (obj.data && obj.data.report_url) ? obj.data.report_url : ""
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
                text: "DIAGNOSTIC REPORT"
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
                    Layout.preferredWidth: Math.min(rBadgeRow.implicitWidth + 22, root.width * 0.28)
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
                        id: rBadgeRow
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
                width: root.width * 0.6
                spacing: 20

                // Icon
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    width: 80; height: 80

                    Image {
                        id: reportBigIcon
                        anchors.fill: parent
                        source: "qrc:/qt/qml/Veya/qml/assets/icon_settings.svg"
                        fillMode: Image.PreserveAspectFit
                        visible: false
                    }
                    MultiEffect {
                        source: reportBigIcon
                        anchors.fill: reportBigIcon
                        colorization: 1.0
                        colorizationColor: root.cCyan
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Report Coming Soon"
                    color: root.cText
                    font.pixelSize: 28; font.bold: true
                    font.family: "DejaVu Sans"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: root.width * 0.6
                    text: "Connect to the internet and start a session to receive a guided diagnostic report from a remote expert."
                    color: root.cDim
                    font.pixelSize: 16; font.family: "DejaVu Sans"
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                // Status panel
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: root.width * 0.5
                    height: statusCol.implicitHeight + 24
                    radius: 12
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.color: Qt.rgba(1, 1, 1, 0.09); border.width: 1

                    ColumnLayout {
                        id: statusCol
                        anchors { left: parent.left; right: parent.right; margins: 16 }
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        // Backend status row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: VehicleDataProvider.connected ? "#47FF9A" : root.cWarn
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                            Text {
                                text: "Backend: " + (VehicleDataProvider.connected ? "Connected" : "Disconnected")
                                color: root.cText
                                font.pixelSize: 14; font.family: "DejaVu Sans"
                            }
                            Item { Layout.fillWidth: true }
                        }

                        // Mode row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: root.cCyan; opacity: 0.7
                            }
                            Text {
                                text: "Mode: " + VehicleDataProvider.dataMode.toUpperCase()
                                color: root.cText
                                font.pixelSize: 14; font.family: "DejaVu Sans"
                            }
                            Item { Layout.fillWidth: true }
                        }

                        // Internet row (placeholder)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: Qt.rgba(1, 1, 1, 0.3)
                            }
                            Text {
                                text: "Internet: Not configured"
                                color: Qt.rgba(1, 1, 1, 0.45)
                                font.pixelSize: 14; font.family: "DejaVu Sans"
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }

        // ── Disabled Generate Report button ───────────────────────────────
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 20
            width: root.width * 0.4
            height: 50

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.04)
                border.color: Qt.rgba(1, 1, 1, 0.10); border.width: 1
                opacity: 0.5

                Text {
                    anchors.centerIn: parent
                    text: "Generate Report"
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 16; font.bold: true; font.family: "DejaVu Sans"
                }
            }

            ToolTip.visible: disabledHover.containsMouse
            ToolTip.text: root.buttonTooltip

            MouseArea {
                id: disabledHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.ForbiddenCursor
            }
        }
    }
}
