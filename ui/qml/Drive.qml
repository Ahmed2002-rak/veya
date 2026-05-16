import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Veya 1.0

Page {
    id: root
    clip: true

    property var nav: null
    background: Rectangle { color: "transparent" }

    function clamp(x, a, b) { return Math.max(a, Math.min(b, x)) }

    // When source is connected but not yet streaming, show zeros rather than
    // frozen last-known values (so the user doesn't think 0 km/h is real data).
    readonly property bool _zeroGauges: VehicleDataProvider.sourceState === "no_telemetry"

    // ── Palette ───────────────────────────────────────────────────────────
    readonly property color cBg:      "#0B0F14"
    readonly property color cBorder:  "#1A4040"
    readonly property color cCyan:    "#4DD2FF"
    readonly property color cGreen:   "#7CFF4A"
    readonly property color cWarn:    "#FF4D6D"
    readonly property color cAmber:   "#FFD84D"
    readonly property color cText:    "white"
    readonly property color cDim:     Qt.rgba(1, 1, 1, 0.55)

    // ── MiniMetric tile (right-column 2x2 grid) ──────────────────────────
    component MiniMetric: Rectangle {
        id: mm
        property string label:  "LABEL"
        property string val:    "0"
        property string unit:   ""
        property bool   alert:  false
        property color  accent: root.cCyan

        radius: 12
        color:  mm.alert ? Qt.rgba(1, 0.30, 0.43, 0.12) : "#0E1418"
        border.color: mm.alert ? root.cWarn : root.cBorder
        border.width: 1

        Behavior on color        { ColorAnimation { duration: 300 } }
        Behavior on border.color { ColorAnimation { duration: 300 } }

        Column {
            anchors {
                left: parent.left; leftMargin: 12
                verticalCenter: parent.verticalCenter
            }
            spacing: 4

            Text {
                text: mm.label
                color: root.cDim
                font.pixelSize: 9
                font.letterSpacing: 1.6
                font.family: "DejaVu Sans"
            }
            Row {
                spacing: 4
                Text {
                    id: valLbl
                    text:  mm.val
                    color: mm.alert ? root.cWarn : mm.accent
                    font.pixelSize: 18
                    font.bold: true
                    font.family: "DejaVu Sans"
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
                Text {
                    anchors.baseline: valLbl.baseline
                    text:  mm.unit
                    color: root.cDim
                    font.pixelSize: 11
                    font.family: "DejaVu Sans"
                }
            }
        }

        // Alert pulse outline
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: "transparent"
            border.color: root.cWarn; border.width: 1
            visible: mm.alert
            SequentialAnimation on opacity {
                running: mm.alert; loops: Animation.Infinite
                NumberAnimation { to: 0.1; duration: 600 }
                NumberAnimation { to: 1.0; duration: 600 }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    //  ROOT BACKGROUND
    // ══════════════════════════════════════════════════════════════════════
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
        border.color: root.cBorder
        border.width: 2
        radius: 24
    }

    // ══════════════════════════════════════════════════════════════════════
    //  MAIN LAYOUT
    // ══════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 12

        // ── TOP STRIP (~9%) ───────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.height * 0.09
            spacing: 12

            // LEFT: Back button
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
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.nav) root.nav.pop()
                }
            }

            // CENTER: spacer · StatusIconBar · spacer
            Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }

            StatusIconBar {
                Layout.alignment: Qt.AlignVCenter
                iconSize: 20
                accentColor: root.cCyan
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }

            // Settings icon
            Item {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                Layout.alignment: Qt.AlignVCenter
                Image {
                    id: driveSettingsIcon
                    anchors.fill: parent
                    source: "assets/icon_settings.svg"
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(72, 72)
                    smooth: true
                    visible: false
                }
                MultiEffect {
                    source: driveSettingsIcon
                    anchors.fill: driveSettingsIcon
                    colorization: 1.0
                    colorizationColor: root.cCyan
                    opacity: settingsMouse.containsMouse ? 1.0 : 0.70
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }
                scale: settingsMouse.pressed ? 0.90 : (settingsMouse.containsMouse ? 1.1 : 1.0)
                Behavior on scale { NumberAnimation { duration: 150 } }
                MouseArea {
                    id: settingsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.nav)
                            root.nav.push(Qt.resolvedUrl("SettingsScreen.qml"), { nav: root.nav })
                    }
                }
            }

            // RIGHT: connection/mode badge + DemoBadge (capped at 30% root.width)
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: root.width * 0.30
                spacing: 4

                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: Math.min(badgeRow.implicitWidth + 16, root.width * 0.28)
                    Layout.maximumWidth: 110
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
                        spacing: 6

                        Rectangle {
                            width: 7; height: 7; radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: {
                                if (!VehicleDataProvider.connected) return root.cWarn
                                return VehicleDataProvider.dataMode === "elm"
                                    ? "#47FF9A" : root.cCyan
                            }
                            Behavior on color { ColorAnimation { duration: 400 } }
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
                                if (VehicleDataProvider.switching)   return "SWITCHING…"
                                const m = VehicleDataProvider.dataMode
                                return m === "elm"  ? "ELM"
                                     : m === "mock" ? "MOCK"
                                     :                "—"
                            }
                            color: root.cText
                            font.pixelSize: 11; font.bold: true
                            font.letterSpacing: 1.4
                            font.family: "DejaVu Sans"
                        }
                    }
                }

                DemoBadge {
                    Layout.alignment: Qt.AlignRight
                    Layout.maximumWidth: 130
                }

                // Mode error toast
                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    visible: VehicleDataProvider.lastModeError.length > 0
                    Layout.preferredHeight: 18
                    Layout.preferredWidth: Math.min(errLbl.implicitWidth + 14, root.width * 0.28)
                    radius: 9
                    color: Qt.rgba(0.5, 0.05, 0.10, 0.85)
                    border.color: root.cWarn; border.width: 1
                    Text {
                        id: errLbl
                        anchors.centerIn: parent
                        text: VehicleDataProvider.lastModeError
                        color: "#FFB0B8"
                        font.pixelSize: 9
                        font.family: "DejaVu Sans"
                    }
                }
            }
        }

        // ── OBD-II source banner (Phase 3.0b) ───────────────────────────────
        // Three-state banner driven by VehicleDataProvider.sourceState:
        //   "ok"           — hidden (mock mode or live telemetry flowing)
        //   "waiting"      — amber: no source connected at all
        //   "no_telemetry" — cyan: source connected but no data yet (zero gauges)
        Rectangle {
            id: sourceBanner
            Layout.fillWidth: true
            readonly property bool showBanner: VehicleDataProvider.sourceState !== "ok"
            Layout.preferredHeight: showBanner ? 32 : 0
            visible: showBanner
            clip: true
            radius: 6
            color: VehicleDataProvider.sourceState === "no_telemetry" ? "#1A2E3A" : "#4A3D1A"
            border.color: VehicleDataProvider.sourceState === "no_telemetry" ? "#4DD2FF" : "#FFB347"
            border.width: 1
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 200 } }
            Behavior on color        { ColorAnimation { duration: 300 } }
            Behavior on border.color { ColorAnimation { duration: 300 } }

            Row {
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    width: 8; height: 8; radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: VehicleDataProvider.sourceState === "no_telemetry" ? "#4DD2FF" : "#FFB347"
                    Behavior on color { ColorAnimation { duration: 300 } }
                    SequentialAnimation on opacity {
                        running: sourceBanner.showBanner
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.5; duration: 750 }
                        NumberAnimation { to: 1.0; duration: 750 }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: VehicleDataProvider.sourceState === "no_telemetry"
                          ? "Connected — waiting for data"
                          : "Waiting for OBD-II device..."
                    color: VehicleDataProvider.sourceState === "no_telemetry" ? "#4DD2FF" : "#FFB347"
                    font.pixelSize: 14; font.bold: true
                    font.family: "DejaVu Sans"
                    Behavior on color { ColorAnimation { duration: 300 } }
                }
            }
        }

        // ── MAIN AREA: unified panel ──────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Single unified backdrop
            Rectangle {
                anchors.fill: parent
                radius: 16
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0.06, 0.09, 0.12, 0.88) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.06, 0.09, 0.92) }
                }
                border.color: Qt.rgba(0.10, 0.25, 0.25, 0.30)
                border.width: 1
            }

            // Three-column layout with thin dividers
            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ── LEFT (35%): Speed gauge + speed bar ──────────────────
                Item {
                    Layout.preferredWidth: root.width * 0.35
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors { fill: parent; margins: 18 }
                        spacing: 8

                        GaugeRing {
                            Layout.fillWidth:  true
                            Layout.fillHeight: true
                            min: 0; max: 200
                            value:  root._zeroGauges ? 0 : VehicleDataProvider.speedKph
                            unit:   "km/h"
                            label:  ""
                            accent: root.cCyan
                        }

                        SpeedBar {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 14
                            value: root._zeroGauges ? 0
                                   : clamp(VehicleDataProvider.speedKph / 200.0, 0, 1)
                            segmentCount: 8
                            accentColor: VehicleDataProvider.warnOverspeed
                                         ? root.cWarn : root.cCyan
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "KPH"
                            color: root.cDim
                            font.pixelSize: 10
                            font.letterSpacing: 2
                            font.family: "DejaVu Sans"
                        }
                    }
                }

                // Divider 1
                Item {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    Rectangle {
                        width: 1
                        height: parent.height * 0.70
                        anchors.centerIn: parent
                        color: Qt.rgba(0.10, 0.25, 0.25, 0.50)
                    }
                }

                // ── CENTER (30%): road + car silhouette + telltales + gear
                Item {
                    Layout.preferredWidth: root.width * 0.30
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors { fill: parent; margins: 8 }
                        spacing: 6

                        // Road behind car (stacked z-order)
                        Item {
                            Layout.fillWidth:  true
                            Layout.fillHeight: true

                            AnimatedRoad {
                                anchors.fill: parent
                                z: 0
                                accentColor: root.cCyan
                            }

                            CarSilhouette {
                                anchors.centerIn: parent
                                width:  parent.width * 0.45
                                height: width * 1.38
                                z: 1
                                fallbackColor: root.cCyan
                            }
                        }

                        WarningTelltales {
                            Layout.alignment: Qt.AlignHCenter
                            iconSize: 28
                            spacing:  4
                        }

                        GearIndicator {
                            Layout.alignment: Qt.AlignHCenter
                            currentGear: VehicleDataProvider.pseudoGear
                            accentColor: root.cCyan
                        }
                    }
                }

                // Divider 2
                Item {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    Rectangle {
                        width: 1
                        height: parent.height * 0.70
                        anchors.centerIn: parent
                        color: Qt.rgba(0.10, 0.25, 0.25, 0.50)
                    }
                }

                // ── RIGHT (≈35%): RPM gauge + 2x2 mini metrics ───────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors { fill: parent; margins: 18 }
                        spacing: 8

                        GaugeRing {
                            Layout.fillWidth:  true
                            Layout.fillHeight: true
                            min: 0; max: 8000
                            value:  root._zeroGauges ? 0 : VehicleDataProvider.rpm
                            unit:   "rpm"
                            label:  ""
                            accent: root.cGreen
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            rowSpacing:    6
                            columnSpacing: 6

                            MiniMetric {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 52
                                label:  "COOLANT"
                                val:    (root._zeroGauges ? 0.0 : VehicleDataProvider.coolantC).toFixed(1)
                                unit:   "°C"
                                alert:  !root._zeroGauges && VehicleDataProvider.warnCoolantHigh
                                accent: VehicleDataProvider.warnCoolantHigh ? root.cWarn : root.cCyan
                            }

                            MiniMetric {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 52
                                label:  "BATTERY"
                                val:    (root._zeroGauges ? 0.0 : VehicleDataProvider.batteryV).toFixed(1)
                                unit:   "V"
                                alert:  !root._zeroGauges && VehicleDataProvider.warnLowBattery
                                accent: VehicleDataProvider.warnLowBattery ? root.cWarn : "#47FF9A"
                            }

                            MiniMetric {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 52
                                label:  "FUEL"
                                val:    (root._zeroGauges ? 0.0 : VehicleDataProvider.fuelLevel).toFixed(0)
                                unit:   "%"
                                alert:  !root._zeroGauges && VehicleDataProvider.warnLowFuel
                                accent: VehicleDataProvider.warnLowFuel ? root.cAmber : "#47FF9A"
                            }

                            MiniMetric {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 52
                                label:  "INTAKE"
                                val:    (root._zeroGauges ? 0.0 : VehicleDataProvider.intakeTempC).toFixed(1)
                                unit:   "°C"
                                alert:  false
                                accent: root.cCyan
                            }
                        }
                    }
                }
            }
        }

        // ── BOTTOM STRIP (~5%): text-based warning fallback ───────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: VehicleDataProvider.anyWarning ? 32 : 0
            radius: 8
            color: Qt.rgba(1, 0.30, 0.43, 0.10)
            border.color: root.cWarn; border.width: 1
            clip: true
            visible: VehicleDataProvider.anyWarning
            Behavior on Layout.preferredHeight { NumberAnimation { duration: 200 } }

            Row {
                anchors {
                    left: parent.left; leftMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                spacing: 10

                Rectangle {
                    width: 7; height: 7; radius: 4
                    color: root.cWarn
                    anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite; running: true
                        NumberAnimation { to: 0.2; duration: 500 }
                        NumberAnimation { to: 1.0; duration: 500 }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        let w = []
                        if (VehicleDataProvider.warnCoolantHigh) w.push("COOLANT HIGH")
                        if (VehicleDataProvider.warnOverspeed)   w.push("OVERSPEED")
                        if (VehicleDataProvider.warnLowFuel)     w.push("LOW FUEL")
                        if (VehicleDataProvider.warnLowBattery)  w.push("LOW BATTERY")
                        return w.join("   ·   ")
                    }
                    color: root.cWarn
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 1.4
                    font.family: "DejaVu Sans"
                }
            }
        }
    }
}
