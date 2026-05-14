import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Veya 1.0

Page {
    id: root
    width: parent.width
    height: parent.height
    clip: true

    property var nav: null

    background: Rectangle { color: "transparent" }

    // ── Palette (matches Drive.qml) ──────────────────────────────────────
    readonly property color cBg:     "#0B0F14"
    readonly property color cBorder: "#1A4040"
    readonly property color cCyan:   "#4DD2FF"
    readonly property color cGreen:  "#47FF9A"
    readonly property color cText:   "white"
    readonly property color cWarn:   "#FF4D6D"

    // ── Developer unlock state ───────────────────────────────────────────
    property int  tapCount:    0
    property bool devUnlocked: false

    Timer {
        id: tapResetTimer
        interval: 3000
        repeat: false
        onTriggered: root.tapCount = 0
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

    // ── Outer bezel (matches Drive.qml) ─────────────────────────────────
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

            // Back button
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
                text: "DIAGNOSTIC"
                color: root.cText
                font.pixelSize: 18
                font.bold: true
                font.letterSpacing: 4
                font.family: "DejaVu Sans"
            }

            Item { Layout.fillWidth: true }

            // Connection badge + DemoBadge stacked
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: root.width * 0.28
                Layout.maximumWidth:   root.width * 0.30
                spacing: 4

                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: Math.min(badgeRow.implicitWidth + 22, root.width * 0.28)
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
                        id: badgeRow
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

        // ── Subtitle ─────────────────────────────────────────────────────
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 12
            Layout.bottomMargin: 20
            text: "What would you like to do?"
            color: Qt.rgba(1, 1, 1, 0.6)
            font.pixelSize: 16
            font.family: "DejaVu Sans"
        }

        // ── Two action cards ──────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Row {
                anchors.centerIn: parent
                spacing: 32

                // ── GET REPORT card ───────────────────────────────────────
                Rectangle {
                    id: reportCard
                    width: root.width * 0.35
                    height: 220
                    radius: 16
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#111D23" }
                        GradientStop { position: 0.5; color: "#0E1418" }
                        GradientStop { position: 1.0; color: "#0E1418" }
                    }
                    border.color: reportHover.containsMouse
                                  ? root.cCyan
                                  : Qt.rgba(0.302, 0.824, 1.0, 0.40)
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    scale: reportHover.pressed ? 0.98 : (reportHover.containsMouse ? 1.02 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 48
                        spacing: 14

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            width: 56; height: 56

                            Image {
                                id: reportIcon
                                anchors.fill: parent
                                source: "qrc:/qt/qml/Veya/qml/assets/icon_settings.svg"
                                fillMode: Image.PreserveAspectFit
                                sourceSize: Qt.size(112, 112)
                                smooth: true
                                visible: false
                            }
                            MultiEffect {
                                source: reportIcon
                                anchors.fill: reportIcon
                                colorization: 1.0
                                colorizationColor: root.cCyan
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Get Report"
                            color: root.cText
                            font.pixelSize: 24; font.bold: true
                            font.family: "DejaVu Sans"
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: parent.width
                            text: "Diagnose your car and receive a guided report"
                            color: Qt.rgba(1, 1, 1, 0.6)
                            font.pixelSize: 14; font.family: "DejaVu Sans"
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    Text {
                        anchors.bottom: parent.bottom
                        anchors.right:  parent.right
                        anchors.bottomMargin: 16
                        anchors.rightMargin:  16
                        text: "→"
                        color: root.cCyan
                        opacity: 0.6
                        font.pixelSize: 24
                        font.family: "DejaVu Sans"
                    }

                    MouseArea {
                        id: reportHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.nav)
                                root.nav.push(Qt.resolvedUrl("ReportScreen.qml"), { nav: root.nav })
                        }
                    }
                }

                // ── START LIVE SESSION card ───────────────────────────────
                Rectangle {
                    id: liveCard
                    width: root.width * 0.35
                    height: 220
                    radius: 16
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#111F1E" }
                        GradientStop { position: 0.5; color: "#0E1418" }
                        GradientStop { position: 1.0; color: "#0E1418" }
                    }
                    border.color: liveHover.containsMouse
                                  ? root.cGreen
                                  : Qt.rgba(0.278, 1.0, 0.604, 0.40)
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    scale: liveHover.pressed ? 0.98 : (liveHover.containsMouse ? 1.02 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width - 48
                        spacing: 14

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            width: 56; height: 56

                            Image {
                                id: liveIcon
                                anchors.fill: parent
                                source: "qrc:/qt/qml/Veya/qml/assets/icon_phone.svg"
                                fillMode: Image.PreserveAspectFit
                                sourceSize: Qt.size(112, 112)
                                smooth: true
                                visible: false
                            }
                            MultiEffect {
                                source: liveIcon
                                anchors.fill: liveIcon
                                colorization: 1.0
                                colorizationColor: root.cGreen
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Start Live Session"
                            color: root.cText
                            font.pixelSize: 24; font.bold: true
                            font.family: "DejaVu Sans"
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: parent.width
                            text: "Connect live with a remote expert for diagnosis"
                            color: Qt.rgba(1, 1, 1, 0.6)
                            font.pixelSize: 14; font.family: "DejaVu Sans"
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    Text {
                        anchors.bottom: parent.bottom
                        anchors.right:  parent.right
                        anchors.bottomMargin: 16
                        anchors.rightMargin:  16
                        text: "→"
                        color: root.cGreen
                        opacity: 0.6
                        font.pixelSize: 24
                        font.family: "DejaVu Sans"
                    }

                    MouseArea {
                        id: liveHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.nav)
                                root.nav.push(Qt.resolvedUrl("LiveSessionScreen.qml"), { nav: root.nav })
                        }
                    }
                }
            }
        }
    }

    // ── Hidden 5-tap developer unlock ────────────────────────────────────
    // Subtle dot bottom-right. 5 taps within 3s → DevDiagnostic.
    // Once unlocked this session, single tap opens DevDiagnostic.
    Item {
        anchors { bottom: parent.bottom; right: parent.right }
        anchors.bottomMargin: 12
        anchors.rightMargin:  12
        width: 30; height: 30

        Rectangle {
            anchors.centerIn: parent
            width: 6; height: 6; radius: 3
            color: "white"; opacity: 0.15
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (root.devUnlocked) {
                    if (root.nav)
                        root.nav.push(Qt.resolvedUrl("DevDiagnostic.qml"), { nav: root.nav })
                    return
                }
                root.tapCount++
                tapResetTimer.restart()
                if (root.tapCount >= 5) {
                    root.devUnlocked = true
                    root.tapCount = 0
                    tapResetTimer.stop()
                    if (root.nav)
                        root.nav.push(Qt.resolvedUrl("DevDiagnostic.qml"), { nav: root.nav })
                }
            }
        }
    }
}
