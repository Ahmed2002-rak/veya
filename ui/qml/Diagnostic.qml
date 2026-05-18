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

    // ── Report generation state ──────────────────────────────────────────
    property bool   reportLoading:  false
    property string reportError:    ""
    property var    cachedDtcs:     []
    property bool   awaitingDtcs:   false

    Timer {
        id: dtcWaitTimer
        interval: 5000
        repeat: false
        onTriggered: {
            root.awaitingDtcs = false
            if (VehicleDataProvider.latestDtcs.length > 0) {
                root.cachedDtcs = VehicleDataProvider.latestDtcs
                root._sendReportRequest()
            } else {
                root.reportLoading = false
                root.reportError   = "No DTC data available"
            }
        }
    }

    Connections {
        target: VehicleDataProvider
        function onLatestDtcsChanged() {
            if (!root.awaitingDtcs) return
            root.awaitingDtcs = false
            dtcWaitTimer.stop()
            root.cachedDtcs = VehicleDataProvider.latestDtcs
            root._sendReportRequest()
        }
        function onReportResultChanged() {
            const r = VehicleDataProvider.reportResult
            if (!r || !root.reportLoading) return
            root.reportLoading = false
            if (r.ok) {
                root.reportError = ""
                if (root.nav)
                    root.nav.push(Qt.resolvedUrl("ReportScreen.qml"),
                                  { nav: root.nav, reportData: r.report })
            } else {
                root.reportError = r.error || "Report generation failed"
            }
        }
    }

    function _sendReportRequest() {
        const profile = {}  // UserProfile not always available — keep it simple
        const payload = {
            dtcs:    root.cachedDtcs,
            vehicle: { make: "Unknown", model: "Unknown" },
            driver:  {}
        }
        VehicleDataProvider.sendCommand({ cmd: "server_request_report", payload: payload })
    }

    function startReport() {
        if (root.reportLoading) return
        root.reportError   = ""
        root.reportLoading = true

        if (VehicleDataProvider.latestDtcs.length > 0) {
            root.cachedDtcs = VehicleDataProvider.latestDtcs
            root._sendReportRequest()
        } else {
            // Query DTCs first, wait up to 5s
            root.awaitingDtcs = true
            VehicleDataProvider.sendCommand({ cmd: "esp32_query_dtc" })
            dtcWaitTimer.restart()
        }
    }

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

            // Settings icon
            Item {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                Layout.alignment: Qt.AlignVCenter
                Image {
                    id: diagSettingsIcon
                    anchors.fill: parent
                    source: "assets/icon_settings.svg"
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(72, 72)
                    smooth: true
                    visible: false
                }
                MultiEffect {
                    source: diagSettingsIcon
                    anchors.fill: diagSettingsIcon
                    colorization: 1.0
                    colorizationColor: root.cCyan
                    opacity: diagSettingsMouse.containsMouse ? 1.0 : 0.70
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
                scale: diagSettingsMouse.pressed ? 0.90 : (diagSettingsMouse.containsMouse ? 1.1 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150 } }
                MouseArea {
                    id: diagSettingsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.nav)
                            root.nav.push(Qt.resolvedUrl("SettingsScreen.qml"), { nav: root.nav })
                    }
                }
            }

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
                id: cardRow
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
                                source: "assets/icon_settings.svg"
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

                    // Loading overlay
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Qt.rgba(0, 0, 0, 0.65)
                        visible: root.reportLoading

                        Column {
                            anchors.centerIn: parent
                            spacing: 12
                            BusyIndicator {
                                anchors.horizontalCenter: parent.horizontalCenter
                                running: root.reportLoading
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Generating report..."
                                color: "white"
                                font.pixelSize: 14; font.family: "DejaVu Sans"
                            }
                        }
                    }

                    MouseArea {
                        id: reportHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.startReport()
                    }
                }

                // ── START LIVE SESSION card ───────────────────────────────
                Rectangle {
                    id: liveCard
                    width: root.width * 0.35
                    height: 220
                    radius: 16
                    opacity: 0.45
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

                    Rectangle {
                        anchors.top: parent.top; anchors.right: parent.right
                        anchors.topMargin: 12; anchors.rightMargin: 12
                        width: 100; height: 24; radius: 12
                        color: Qt.rgba(1, 1, 1, 0.08)
                        border.color: Qt.rgba(1, 1, 1, 0.20); border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "Coming soon"
                            color: Qt.rgba(1, 1, 1, 0.50)
                            font.pixelSize: 11; font.family: "DejaVu Sans"
                        }
                    }

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
                                source: "assets/icon_phone.svg"
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
                        cursorShape: Qt.ArrowCursor
                        onClicked: {}
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: cardRow.bottom
                anchors.topMargin: 16
                text: root.reportError
                visible: root.reportError.length > 0
                color: "#FF4D6D"
                font.pixelSize: 14; font.family: "DejaVu Sans"
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
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
