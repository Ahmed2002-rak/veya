import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Veya 1.0

Page {
    id: root

    property var nav: null
    background: Rectangle { color: "transparent" }

    function clamp(x, a, b) { return Math.max(a, Math.min(b, x)) }

    // ── Palette ───────────────────────────────────────────────────────────
    readonly property color cBg:      "#0B0F14"
    readonly property color cBorder:  "#1A4040"
    readonly property color cCyan:    "#4DD2FF"
    readonly property color cGreen:   "#7CFF4A"
    readonly property color cWarn:    "#FF4D6D"
    readonly property color cAmber:   "#FFD84D"
    readonly property color cText:    "white"
    readonly property color cDim:     Qt.rgba(1, 1, 1, 0.55)

    // ── Inline glass card ────────────────────────────────────────────────
    component GlassCard: Rectangle {
        radius: 16
        color:  Qt.rgba(1, 1, 1, 0.04)
        border.color: Qt.rgba(1, 1, 1, 0.09)
        border.width: 1
    }

    // ── Inline mini metric (2x2 grid in right column) ────────────────────
    component MiniMetric: Rectangle {
        id: mm
        property string label:  "LABEL"
        property string val:    "0"
        property string unit:   ""
        property bool   alert:  false
        property color  accent: root.cCyan

        radius: 12
        color:  mm.alert ? Qt.rgba(1, 0.30, 0.43, 0.12) : Qt.rgba(1, 1, 1, 0.04)
        border.color: mm.alert ? root.cWarn : Qt.rgba(1, 1, 1, 0.08)
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
    //  ROOT BACKGROUND  (kept consistent with Main.qml star-field theme)
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

    // Cyan-tinted bezel frame (the "modern hybrid cluster" look)
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

        // ── TOP STRIP (~10%) ──────────────────────────────────────────────
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

            // CENTER: Status icon strip
            Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }

            StatusIconBar {
                Layout.alignment: Qt.AlignVCenter
                iconSize: 22
                accentColor: root.cCyan
            }

            Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }

            // RIGHT: connection/mode badge stacked with DemoBadge
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: badgeRow.implicitWidth + 22
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
                }

                // Mode error toast (Phase 1 lastModeError surface)
                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    visible: VehicleDataProvider.lastModeError.length > 0
                    Layout.preferredHeight: 18
                    Layout.preferredWidth: errLbl.implicitWidth + 14
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

        // ── MAIN AREA: 3 columns ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            // ── LEFT (35%): SPEED gauge + speed bar ───────────────────────
            GlassCard {
                Layout.fillHeight: true
                Layout.preferredWidth: root.width * 0.35

                ColumnLayout {
                    anchors { fill: parent; margins: 18 }
                    spacing: 10

                    Text {
                        text: "SPEED"
                        color: root.cDim
                        font.pixelSize: 11
                        font.letterSpacing: 3
                        font.family: "DejaVu Sans"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    GaugeRing {
                        Layout.fillWidth:  true
                        Layout.fillHeight: true
                        min: 0
                        max: 200
                        value:  VehicleDataProvider.speedKph
                        unit:   "km/h"
                        label:  ""
                        accent: root.cCyan
                    }

                    SpeedBar {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 14
                        value: clamp(VehicleDataProvider.speedKph / 200.0, 0, 1)
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

            // ── CENTER (30%): Car silhouette + gear indicator ─────────────
            GlassCard {
                Layout.fillHeight: true
                Layout.preferredWidth: root.width * 0.30

                ColumnLayout {
                    anchors { fill: parent; margins: 18 }
                    spacing: 8

                    Text {
                        text: "VEHICLE"
                        color: root.cDim
                        font.pixelSize: 11
                        font.letterSpacing: 3
                        font.family: "DejaVu Sans"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    CarSilhouette {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        imageSource: Qt.resolvedUrl("assets/car_silhouette.png")
                        fallbackColor: root.cCyan
                    }

                    GearIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        currentGear: VehicleDataProvider.pseudoGear
                        accentColor: root.cCyan
                    }
                }
            }

            // ── RIGHT (35%): RPM gauge + 2x2 mini metrics ─────────────────
            GlassCard {
                Layout.fillHeight: true
                Layout.preferredWidth: root.width * 0.35

                ColumnLayout {
                    anchors { fill: parent; margins: 18 }
                    spacing: 10

                    Text {
                        text: "ENGINE"
                        color: root.cDim
                        font.pixelSize: 11
                        font.letterSpacing: 3
                        font.family: "DejaVu Sans"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    GaugeRing {
                        Layout.fillWidth:  true
                        Layout.fillHeight: true
                        min: 0
                        max: 8000
                        value:  VehicleDataProvider.rpm
                        unit:   "rpm"
                        label:  "RPM"
                        accent: root.cGreen
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 8
                        columnSpacing: 8

                        MiniMetric {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            label:  "COOLANT"
                            val:    VehicleDataProvider.coolantC.toFixed(1)
                            unit:   "°C"
                            alert:  VehicleDataProvider.warnCoolantHigh
                            accent: VehicleDataProvider.warnCoolantHigh ? root.cWarn : root.cCyan
                        }

                        MiniMetric {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            label:  "BATTERY"
                            val:    VehicleDataProvider.batteryV.toFixed(1)
                            unit:   "V"
                            alert:  VehicleDataProvider.warnLowBattery
                            accent: VehicleDataProvider.warnLowBattery ? root.cWarn : "#47FF9A"
                        }

                        MiniMetric {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            label:  "FUEL"
                            val:    VehicleDataProvider.fuelLevel.toFixed(0)
                            unit:   "%"
                            alert:  VehicleDataProvider.warnLowFuel
                            accent: VehicleDataProvider.warnLowFuel ? root.cAmber : "#47FF9A"
                        }

                        MiniMetric {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            label:  "INTAKE"
                            val:    VehicleDataProvider.intakeTempC.toFixed(1)
                            unit:   "°C"
                            alert:  false
                            accent: root.cCyan
                        }
                    }
                }
            }
        }

        // ── BOTTOM STRIP (~5%): warnings ──────────────────────────────────
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
