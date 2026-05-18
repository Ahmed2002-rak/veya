import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Veya 1.0

Page {
    id: root
    clip: true

    property var nav:        null
    property var reportData: null

    background: Rectangle { color: "transparent" }

    readonly property color cBorder: "#1A4040"
    readonly property color cCyan:   "#4DD2FF"
    readonly property color cAmber:  "#FFD84D"
    readonly property color cWarn:   "#FF4D6D"
    readonly property color cGreen:  "#47FF9A"
    readonly property color cText:   "white"
    readonly property color cDim:    Qt.rgba(1, 1, 1, 0.55)
    readonly property color cBg:     "#0B0F14"

    function severityColor(sev) {
        if (sev === "critical") return cWarn
        if (sev === "warning")  return cAmber
        return cCyan
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

            // Connection badge
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredHeight: 28
                Layout.preferredWidth: Math.min(rBadgeRow.implicitWidth + 22, root.width * 0.28)
                radius: 14
                color: VehicleDataProvider.connected
                       ? Qt.rgba(0.30, 0.82, 1, 0.10)
                       : Qt.rgba(1, 0.30, 0.43, 0.12)
                border.color: VehicleDataProvider.connected ? root.cCyan : root.cWarn
                border.width: 1

                Row {
                    id: rBadgeRow
                    anchors.centerIn: parent
                    spacing: 7

                    Rectangle {
                        width: 7; height: 7; radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: VehicleDataProvider.connected ? root.cCyan : root.cWarn
                    }
                    Text {
                        text: VehicleDataProvider.connected ? "CONNECTED" : "OFFLINE"
                        color: root.cText
                        font.pixelSize: 11; font.bold: true
                        font.letterSpacing: 1.4; font.family: "DejaVu Sans"
                    }
                }
            }
        }

        // ── Content ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ── No data placeholder ───────────────────────────────────────
            ColumnLayout {
                anchors.centerIn: parent
                visible: reportData === null
                spacing: 16

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No report data"
                    color: root.cDim
                    font.pixelSize: 24; font.bold: true
                    font.family: "DejaVu Sans"
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Generate a report from the Diagnostic screen."
                    color: Qt.rgba(1,1,1,0.35)
                    font.pixelSize: 14; font.family: "DejaVu Sans"
                }
            }

            // ── Scrollable report ─────────────────────────────────────────
            ScrollView {
                anchors.fill: parent
                visible: reportData !== null
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: parent.width
                    spacing: 14

                    // ── HEADER CARD ──────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        height: headerCol.implicitHeight + 28
                        radius: 14
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.color: {
                            const sev = reportData ? (reportData.severity || "") : ""
                            return root.severityColor(sev)
                        }
                        border.width: 1

                        ColumnLayout {
                            id: headerCol
                            anchors { left: parent.left; right: parent.right; margins: 18 }
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            // report_id + timestamp row
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: reportData ? (reportData.report_id || "—") : "—"
                                    color: root.cDim
                                    font.pixelSize: 11; font.family: "DejaVu Sans Mono"
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: reportData ? (reportData.timestamp || "") : ""
                                    color: root.cDim
                                    font.pixelSize: 11; font.family: "DejaVu Sans"
                                }
                            }

                            // Severity badge
                            Rectangle {
                                height: 26; width: sevText.implicitWidth + 24
                                radius: 13
                                color: Qt.rgba(0,0,0,0.30)
                                border.color: {
                                    const sev = reportData ? (reportData.severity || "") : ""
                                    return root.severityColor(sev)
                                }
                                border.width: 1

                                Text {
                                    id: sevText
                                    anchors.centerIn: parent
                                    text: reportData ? (reportData.severity || "info").toUpperCase() : "—"
                                    color: {
                                        const sev = reportData ? (reportData.severity || "") : ""
                                        return root.severityColor(sev)
                                    }
                                    font.pixelSize: 12; font.bold: true
                                    font.letterSpacing: 1.4; font.family: "DejaVu Sans"
                                }
                            }

                            // Summary
                            Text {
                                Layout.fillWidth: true
                                text: reportData ? (reportData.summary || "") : ""
                                color: root.cText
                                font.pixelSize: 15; font.family: "DejaVu Sans"
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // ── DTC ANALYSIS CARDS ──────────────────────────────
                    Repeater {
                        model: reportData ? (reportData.dtc_analyses || []) : []

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: dtcCol.implicitHeight + 28
                            radius: 14
                            color: Qt.rgba(1, 0.30, 0.43, 0.05)
                            border.color: Qt.rgba(1, 0.30, 0.43, 0.30)
                            border.width: 1

                            required property var modelData

                            ColumnLayout {
                                id: dtcCol
                                anchors { left: parent.left; right: parent.right; margins: 18 }
                                anchors.top: parent.top; anchors.topMargin: 14
                                spacing: 8

                                // Code badge + title row
                                RowLayout {
                                    spacing: 12
                                    Rectangle {
                                        height: 28; width: codeText.implicitWidth + 16
                                        radius: 6
                                        color: Qt.rgba(1, 0.30, 0.43, 0.15)
                                        border.color: root.cWarn; border.width: 1
                                        Text {
                                            id: codeText
                                            anchors.centerIn: parent
                                            text: modelData.code || "???"
                                            color: root.cWarn
                                            font.pixelSize: 14; font.bold: true
                                            font.family: "DejaVu Sans Mono"
                                        }
                                    }
                                    Text {
                                        text: modelData.title || ""
                                        color: root.cText
                                        font.pixelSize: 15; font.bold: true
                                        font.family: "DejaVu Sans"
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }

                                // Description
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.description || ""
                                    color: root.cDim
                                    font.pixelSize: 13; font.family: "DejaVu Sans"
                                    wrapMode: Text.WordWrap
                                    visible: text.length > 0
                                }

                                // Causes
                                Column {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    visible: (modelData.causes || []).length > 0
                                    Text {
                                        text: "● CAUSES"
                                        color: root.cAmber
                                        font.pixelSize: 11; font.bold: true
                                        font.letterSpacing: 1.2; font.family: "DejaVu Sans"
                                    }
                                    Repeater {
                                        model: modelData.causes || []
                                        Text {
                                            required property string modelData
                                            text: "  · " + modelData
                                            color: root.cDim
                                            font.pixelSize: 13; font.family: "DejaVu Sans"
                                            wrapMode: Text.WordWrap
                                            width: parent.width
                                        }
                                    }
                                }

                                // Symptoms
                                Column {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    visible: (modelData.symptoms || []).length > 0
                                    Text {
                                        text: "● SYMPTOMS"
                                        color: root.cAmber
                                        font.pixelSize: 11; font.bold: true
                                        font.letterSpacing: 1.2; font.family: "DejaVu Sans"
                                    }
                                    Repeater {
                                        model: modelData.symptoms || []
                                        Text {
                                            required property string modelData
                                            text: "  · " + modelData
                                            color: root.cDim
                                            font.pixelSize: 13; font.family: "DejaVu Sans"
                                            wrapMode: Text.WordWrap
                                            width: parent.width
                                        }
                                    }
                                }

                                // Recommended actions
                                Column {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    visible: (modelData.recommended_actions || []).length > 0
                                    Text {
                                        text: "● RECOMMENDED ACTIONS"
                                        color: root.cCyan
                                        font.pixelSize: 11; font.bold: true
                                        font.letterSpacing: 1.2; font.family: "DejaVu Sans"
                                    }
                                    Repeater {
                                        model: modelData.recommended_actions || []
                                        Text {
                                            required property string modelData
                                            text: "  · " + modelData
                                            color: root.cDim
                                            font.pixelSize: 13; font.family: "DejaVu Sans"
                                            wrapMode: Text.WordWrap
                                            width: parent.width
                                        }
                                    }
                                }

                                Item { height: 4 }
                            }
                        }
                    }

                    // ── FOOTER CARD ──────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 8
                        height: footerCol.implicitHeight + 28
                        radius: 14
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(0.30, 0.82, 1, 0.30)
                        border.width: 1
                        visible: (reportData && (reportData.overall_recommendations || []).length > 0)

                        Column {
                            id: footerCol
                            anchors { left: parent.left; right: parent.right; margins: 18 }
                            anchors.top: parent.top; anchors.topMargin: 14
                            spacing: 4

                            Text {
                                text: "● OVERALL RECOMMENDATIONS"
                                color: root.cGreen
                                font.pixelSize: 11; font.bold: true
                                font.letterSpacing: 1.2; font.family: "DejaVu Sans"
                            }

                            Repeater {
                                model: reportData ? (reportData.overall_recommendations || []) : []
                                Text {
                                    required property string modelData
                                    text: "  · " + modelData
                                    color: root.cDim
                                    font.pixelSize: 13; font.family: "DejaVu Sans"
                                    wrapMode: Text.WordWrap
                                    width: parent.width
                                }
                            }

                            Item { height: 4 }
                        }
                    }
                }
            }
        }
    }
}
