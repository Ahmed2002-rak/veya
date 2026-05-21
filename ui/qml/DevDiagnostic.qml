import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Veya 1.0

Page {
    id: root
    clip: true

    property var nav: null
    background: Rectangle { color: "transparent" }

    function clamp(x, a, b) { return Math.max(a, Math.min(b, x)) }
    function ts() {
        const d = new Date()
        return ("0" + d.getHours()).slice(-2)   + ":" +
               ("0" + d.getMinutes()).slice(-2) + ":" +
               ("0" + d.getSeconds()).slice(-2)
    }
    function appendLine(line) {
        outputArea.text += "[" + ts() + "] " + line + "\n"
        outputArea.cursorPosition = outputArea.length
    }

    // ── Palette (matches Drive.qml) ──────────────────────────────────────
    readonly property color cBg:     "#0B0F14"
    readonly property color cBorder: "#1A4040"
    readonly property color cCyan:   "#4DD2FF"
    readonly property color cGreen:  "#7CFF4A"
    readonly property color cWarn:   "#FF4D6D"
    readonly property color cAmber:  "#FFD84D"
    readonly property color cText:   "white"
    readonly property color cDim:    Qt.rgba(1, 1, 1, 0.55)

    component GlassCard: Rectangle {
        radius: 16
        color:  Qt.rgba(1, 1, 1, 0.04)
        border.color: Qt.rgba(1, 1, 1, 0.09)
        border.width: 1
    }

    component MetricTile: Rectangle {
        property string label: "LABEL"
        property string val:   "0"
        property string unit:  ""
        property color  accent: root.cCyan

        radius: 12
        color:  Qt.rgba(1, 1, 1, 0.04)
        border.color: Qt.rgba(1, 1, 1, 0.09)
        border.width: 1

        Column {
            anchors {
                left: parent.left; leftMargin: 12
                verticalCenter: parent.verticalCenter
            }
            spacing: 4
            Text {
                text: parent.parent.label
                color: root.cDim
                font.pixelSize: 9
                font.letterSpacing: 1.6
                font.family: "DejaVu Sans"
            }
            Row {
                spacing: 4
                Text {
                    id: vlbl
                    text: parent.parent.parent.val
                    color: parent.parent.parent.accent
                    font.pixelSize: 18
                    font.bold: true
                    font.family: "DejaVu Sans"
                }
                Text {
                    anchors.baseline: vlbl.baseline
                    text: parent.parent.parent.unit
                    color: root.cDim
                    font.pixelSize: 11
                    font.family: "DejaVu Sans"
                }
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

    // ── DTC model (populated in mock mode by "Read DTC") ─────────────────
    ListModel { id: dtcModel }

    // Sync dtcModel with VehicleDataProvider.latestDtcs whenever it changes
    Connections {
        target: VehicleDataProvider
        function onLatestDtcsChanged() {
            dtcModel.clear()
            const dtcs = VehicleDataProvider.latestDtcs
            for (let i = 0; i < dtcs.length; i++) {
                dtcModel.append({
                    code: dtcs[i].code || "???",
                    desc: dtcs[i].status || ""
                })
            }
            if (dtcs.length > 0)
                root.appendLine("[esp32] " + dtcs.length + " DTC(s) received")
        }
    }

    Connections {
        target: VehicleDataProvider
        function onClearDtcResultChanged() {
            const r = VehicleDataProvider.clearDtcResult
            if (r.length > 0)
                root.appendLine("[esp32] Clear result: " + r)
        }
        function onMileageKmChanged() {
            const km = VehicleDataProvider.mileageKm
            if (km >= 0)
                root.appendLine("[esp32] Mileage: " + Math.round(km).toLocaleString() + " km")
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    //  MAIN LAYOUT
    // ══════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 12

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

            // Title
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "DEV DIAGNOSTIC"
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
                Layout.maximumWidth: root.width * 0.30
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
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.4
                            font.family: "DejaVu Sans"
                        }
                    }
                }

                DemoBadge {
                    Layout.alignment: Qt.AlignRight
                    Layout.maximumWidth: root.width * 0.28
                }
            }
        }

        // ── MAIN AREA: 2 panels ───────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumWidth: root.width
            width: root.width
            spacing: 14

            // ── LEFT PANEL (40%): DTC CODES ───────────────────────────────
            GlassCard {
                Layout.fillHeight: true
                Layout.preferredWidth: (root.width - 58) * 0.40
                Layout.maximumWidth:   (root.width - 58) * 0.40
                Layout.minimumWidth:   (root.width - 58) * 0.40
                Layout.fillWidth: false

                ColumnLayout {
                    anchors { fill: parent; margins: 18 }
                    spacing: 12

                    Text {
                        text: "DTC CODES"
                        color: root.cDim
                        font.pixelSize: 12
                        font.letterSpacing: 3
                        font.family: "DejaVu Sans"
                    }

                    // List + empty placeholder
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListView {
                            id: dtcList
                            anchors.fill: parent
                            model: dtcModel
                            spacing: 8
                            clip: true
                            visible: dtcModel.count > 0

                            delegate: Rectangle {
                                width: ListView.view.width
                                height: 56
                                radius: 10
                                color:  Qt.rgba(1, 1, 1, 0.04)
                                border.color: Qt.rgba(1, 0.30, 0.43, 0.40)
                                border.width: 1

                                required property string code
                                required property string desc

                                Column {
                                    anchors {
                                        left: parent.left; leftMargin: 14
                                        verticalCenter: parent.verticalCenter
                                    }
                                    spacing: 4
                                    Text {
                                        text:  parent.parent.code
                                        color: root.cWarn
                                        font.family:    "DejaVu Sans Mono"
                                        font.pixelSize: 18
                                        font.bold:      true
                                    }
                                    Text {
                                        text:  parent.parent.desc
                                        color: root.cDim
                                        font.family:    "DejaVu Sans"
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: dtcModel.count === 0
                            text: "No fault codes"
                            color: root.cDim
                            font.pixelSize: 14
                            font.family: "DejaVu Sans"
                        }
                    }

                    // Read / Clear buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Button {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            text: "Read DTC"
                            font.family: "DejaVu Sans"
                            font.bold: true
                            background: Rectangle {
                                radius: 8
                                color: parent.hovered ? Qt.rgba(0.30, 0.82, 1, 0.18)
                                                      : Qt.rgba(0.30, 0.82, 1, 0.10)
                                border.color: root.cCyan; border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text {
                                text: parent.text
                                color: root.cCyan
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font: parent.font
                            }
                            onClicked: {
                                appendLine("Querying DTC from ESP32...")
                                VehicleDataProvider.sendCommand({ "cmd": "esp32_query_dtc" })
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            text: "Clear DTC"
                            font.family: "DejaVu Sans"
                            font.bold: true
                            background: Rectangle {
                                radius: 8
                                color: parent.hovered ? Qt.rgba(1, 0.30, 0.43, 0.18)
                                                      : Qt.rgba(1, 0.30, 0.43, 0.10)
                                border.color: root.cWarn; border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text {
                                text: parent.text
                                color: root.cWarn
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font: parent.font
                            }
                            onClicked: {
                                appendLine("Clearing DTCs on ESP32...")
                                VehicleDataProvider.sendCommand({ "cmd": "esp32_clear_dtc" })
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 38
                            text: "Read Mileage"
                            font.family: "DejaVu Sans"
                            font.bold: true
                            background: Rectangle {
                                radius: 8
                                color: parent.hovered ? Qt.rgba(1, 0.851, 0.298, 0.18)
                                                      : Qt.rgba(1, 0.851, 0.298, 0.10)
                                border.color: "#FFD84D"; border.width: 1
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            contentItem: Text {
                                text: parent.text
                                color: "#FFD84D"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font: parent.font
                            }
                            onClicked: {
                                root.appendLine("Querying mileage from ESP32...")
                                VehicleDataProvider.sendCommand({ "cmd": "esp32_query_mileage" })
                            }
                        }
                    }
                }
            }

            // ── RIGHT PANEL (60%): LIVE DATA ──────────────────────────────
            GlassCard {
                Layout.fillHeight: true
                Layout.preferredWidth: (root.width - 58) * 0.60
                Layout.maximumWidth:   (root.width - 58) * 0.60
                Layout.minimumWidth:   (root.width - 58) * 0.60
                Layout.fillWidth: false

                ColumnLayout {
                    anchors { fill: parent; margins: 18 }
                    spacing: 12

                    Text {
                        text: "LIVE DATA"
                        color: root.cDim
                        font.pixelSize: 12
                        font.letterSpacing: 3
                        font.family: "DejaVu Sans"
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.maximumWidth: parent.width
                        columns: 2
                        rowSpacing: 8
                        columnSpacing: 8

                        MetricTile {
                            Layout.fillWidth: true
                            Layout.preferredWidth: ((root.width - 58) * 0.60 - 36 - 8) / 2
                            Layout.preferredHeight: 56
                            label: "RPM"
                            val:   Math.round(VehicleDataProvider.rpm).toString()
                            unit:  ""
                            accent: root.cGreen
                        }
                        MetricTile {
                            Layout.fillWidth: true
                            Layout.preferredWidth: ((root.width - 58) * 0.60 - 36 - 8) / 2
                            Layout.preferredHeight: 56
                            label: "SPEED"
                            val:   VehicleDataProvider.speedKph.toFixed(1)
                            unit:  "km/h"
                            accent: root.cCyan
                        }
                        MetricTile {
                            Layout.fillWidth: true
                            Layout.preferredWidth: ((root.width - 58) * 0.60 - 36 - 8) / 2
                            Layout.preferredHeight: 56
                            label: "COOLANT"
                            val:   VehicleDataProvider.coolantC.toFixed(1)
                            unit:  "°C"
                            accent: VehicleDataProvider.warnCoolantHigh ? root.cWarn : root.cCyan
                        }
                        MetricTile {
                            Layout.fillWidth: true
                            Layout.preferredWidth: ((root.width - 58) * 0.60 - 36 - 8) / 2
                            Layout.preferredHeight: 56
                            label: "BATTERY"
                            val:   VehicleDataProvider.batteryV.toFixed(1)
                            unit:  "V"
                            accent: VehicleDataProvider.warnLowBattery ? root.cWarn : "#47FF9A"
                        }
                        MetricTile {
                            Layout.fillWidth: true
                            Layout.preferredWidth: ((root.width - 58) * 0.60 - 36 - 8) / 2
                            Layout.preferredHeight: 56
                            label: "FUEL"
                            val:   VehicleDataProvider.fuelLevel.toFixed(0)
                            unit:  "%"
                            accent: VehicleDataProvider.warnLowFuel ? root.cAmber : "#47FF9A"
                        }
                        MetricTile {
                            Layout.fillWidth: true
                            Layout.preferredWidth: ((root.width - 58) * 0.60 - 36 - 8) / 2
                            Layout.preferredHeight: 56
                            label: "THROTTLE"
                            val:   VehicleDataProvider.throttlePct.toFixed(0)
                            unit:  "%"
                            accent: root.cCyan
                        }
                        MetricTile {
                            Layout.fillWidth: true
                            Layout.preferredWidth: ((root.width - 58) * 0.60 - 36 - 8) / 2
                            Layout.preferredHeight: 56
                            label: "ENGINE LOAD"
                            val:   VehicleDataProvider.engineLoad.toFixed(0)
                            unit:  "%"
                            accent: VehicleDataProvider.engineLoad > 80 ? root.cWarn
                                  : VehicleDataProvider.engineLoad > 60 ? root.cAmber
                                  :                                       root.cGreen
                        }
                        MetricTile {
                            Layout.fillWidth: true
                            Layout.preferredWidth: ((root.width - 58) * 0.60 - 36 - 8) / 2
                            Layout.preferredHeight: 56
                            label: "INTAKE"
                            val:   VehicleDataProvider.intakeTempC.toFixed(1)
                            unit:  "°C"
                            accent: root.cCyan
                        }
                    }

                    // ESP32 result strip (shows latest DTC count, clear result, mileage)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: "DTCs: " + (VehicleDataProvider.latestDtcs.length > 0
                                  ? VehicleDataProvider.latestDtcs.length + " code(s)"
                                  : "—")
                            color: VehicleDataProvider.latestDtcs.length > 0 ? "#FF4D6D" : Qt.rgba(1,1,1,0.45)
                            font.pixelSize: 12
                            font.family: "DejaVu Sans"
                        }

                        Text { text: "·"; color: Qt.rgba(1,1,1,0.3); font.pixelSize: 12; font.family: "DejaVu Sans" }

                        Text {
                            text: "Clear: " + (VehicleDataProvider.clearDtcResult.length > 0
                                  ? VehicleDataProvider.clearDtcResult : "—")
                            color: VehicleDataProvider.clearDtcResult.length > 0 ? "#7CFF4A" : Qt.rgba(1,1,1,0.45)
                            font.pixelSize: 12
                            font.family: "DejaVu Sans"
                        }

                        Text { text: "·"; color: Qt.rgba(1,1,1,0.3); font.pixelSize: 12; font.family: "DejaVu Sans" }

                        Text {
                            text: "Mileage: " + (VehicleDataProvider.mileageKm >= 0
                                  ? Math.round(VehicleDataProvider.mileageKm).toLocaleString() + " km" : "—")
                            color: VehicleDataProvider.mileageKm >= 0 ? "#4DD2FF" : Qt.rgba(1,1,1,0.45)
                            font.pixelSize: 12
                            font.family: "DejaVu Sans"
                        }

                        Item { Layout.fillWidth: true }
                    }

                    // Console output area (was id: console — now id: outputArea)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 10
                        color: Qt.rgba(0, 0, 0, 0.40)
                        border.color: Qt.rgba(1, 1, 1, 0.10)
                        border.width: 1

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 1
                            clip: true

                            TextArea {
                                id: outputArea
                                readOnly: true
                                wrapMode: TextEdit.Wrap
                                color: root.cText
                                font.family: "DejaVu Sans Mono"
                                font.pixelSize: 12
                                background: null
                                text: "Diagnostic console ready.\n"
                            }
                        }
                    }

                    // "Send to server" — disabled (Phase 3)
                    Button {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        text: "Send to server"
                        font.family: "DejaVu Sans"
                        font.bold: true
                        enabled: false
                        ToolTip.visible: hovered
                        ToolTip.text: "Server not configured (Phase 3)"
                        background: Rectangle {
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.04)
                            border.color: Qt.rgba(1, 1, 1, 0.10); border.width: 1
                        }
                        contentItem: Text {
                            text: parent.text
                            color: root.cDim
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font: parent.font
                        }
                    }
                }
            }
        }
    }
}
