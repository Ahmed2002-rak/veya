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

        // ── Content area ──────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // No-data placeholder
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

            // Scrollable report
            Flickable {
                id: mainFlickable
                anchors.fill: parent
                visible: reportData !== null
                contentWidth: width
                contentHeight: contentColumn.implicitHeight + 16
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Component.onCompleted: contentY = 0

                Column {
                    id: contentColumn
                    width: mainFlickable.width
                    spacing: 14
                    topPadding: 8
                    bottomPadding: 8

                    // ── HEADER CARD ──────────────────────────────────────
                    Rectangle {
                        width: parent.width
                        implicitHeight: headerInner.implicitHeight + 24
                        radius: 14
                        visible: reportData !== null
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.color: {
                            const sev = reportData ? (reportData.severity || "") : ""
                            return root.severityColor(sev)
                        }
                        border.width: 1

                        Column {
                            id: headerInner
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 18
                            anchors.topMargin: 12
                            spacing: 8

                            Row {
                                width: parent.width
                                Text {
                                    id: hdrIdText
                                    text: reportData ? (reportData.report_id || "—") : "—"
                                    color: root.cDim
                                    font.pixelSize: 11; font.family: "DejaVu Sans Mono"
                                }
                                Item {
                                    width: parent.width - hdrIdText.implicitWidth - hdrTsText.implicitWidth
                                    height: 1
                                }
                                Text {
                                    id: hdrTsText
                                    text: reportData ? (reportData.ts_iso || reportData.timestamp || "") : ""
                                    color: root.cDim
                                    font.pixelSize: 11; font.family: "DejaVu Sans"
                                }
                            }

                            Rectangle {
                                height: 26; width: sevText.implicitWidth + 24
                                radius: 13
                                color: Qt.rgba(0, 0, 0, 0.30)
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

                            Text {
                                width: parent.width
                                text: reportData ? (reportData.summary || "") : ""
                                color: root.cText
                                font.pixelSize: 15; font.family: "DejaVu Sans"
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // ── NO FAULTS CARD ───────────────────────────────────
                    Rectangle {
                        width: parent.width
                        implicitHeight: noFaultsInner.implicitHeight + 24
                        radius: 14
                        color: Qt.rgba(0.28, 1, 0.60, 0.05)
                        border.color: Qt.rgba(0.28, 1, 0.60, 0.30)
                        border.width: 1
                        visible: reportData !== null && (reportData.dtc_analyses || []).length === 0

                        Column {
                            id: noFaultsInner
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 18
                            anchors.topMargin: 12
                            spacing: 6
                            Text {
                                width: parent.width
                                text: "✓"
                                color: root.cGreen
                                font.pixelSize: 32; font.family: "DejaVu Sans"
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                width: parent.width
                                text: "Aucun défaut détecté"
                                color: root.cGreen
                                font.pixelSize: 16; font.bold: true
                                font.family: "DejaVu Sans"
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                width: parent.width
                                text: "Le véhicule ne présente aucun code défaut actif."
                                color: root.cDim
                                font.pixelSize: 13; font.family: "DejaVu Sans"
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // ── DTC ANALYSIS CARDS ───────────────────────────────
                    Repeater {
                        model: reportData ? (reportData.dtc_analyses || []) : []

                        delegate: Rectangle {
                            required property var modelData

                            width: contentColumn.width
                            implicitHeight: dtcInner.implicitHeight + 24
                            radius: 14
                            color: {
                                const sev = modelData.severity || ""
                                if (sev === "critical") return Qt.rgba(1, 0.30, 0.43, 0.05)
                                if (sev === "warning")  return Qt.rgba(1, 0.85, 0.30, 0.05)
                                return Qt.rgba(0.30, 0.82, 1, 0.05)
                            }
                            border.color: root.severityColor(modelData.severity || "")
                            border.width: 1

                            Column {
                                id: dtcInner
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                anchors.margins: 18
                                anchors.topMargin: 12
                                spacing: 8

                                Row {
                                    width: parent.width
                                    spacing: 8
                                    Rectangle {
                                        height: 28; width: codeText.implicitWidth + 16
                                        radius: 6
                                        color: Qt.rgba(0, 0, 0, 0.30)
                                        border.color: root.severityColor(modelData.severity || "")
                                        border.width: 1
                                        Text {
                                            id: codeText
                                            anchors.centerIn: parent
                                            text: modelData.code || "???"
                                            color: root.severityColor(modelData.severity || "")
                                            font.pixelSize: 14; font.bold: true
                                            font.family: "DejaVu Sans Mono"
                                        }
                                    }
                                    Rectangle {
                                        height: 28; width: statusBadgeText.implicitWidth + 16
                                        radius: 6
                                        color: Qt.rgba(1, 1, 1, 0.05)
                                        border.color: Qt.rgba(1, 1, 1, 0.20)
                                        border.width: 1
                                        visible: (modelData.status || "").length > 0
                                        Text {
                                            id: statusBadgeText
                                            anchors.centerIn: parent
                                            text: (modelData.status || "").toUpperCase()
                                            color: root.cDim
                                            font.pixelSize: 11; font.bold: true
                                            font.letterSpacing: 1; font.family: "DejaVu Sans"
                                        }
                                    }
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.title || ""
                                    color: root.cText
                                    font.pixelSize: 15; font.bold: true
                                    font.family: "DejaVu Sans"
                                    wrapMode: Text.WordWrap
                                    visible: text.length > 0
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.description || ""
                                    color: root.cDim
                                    font.pixelSize: 13; font.family: "DejaVu Sans"
                                    wrapMode: Text.WordWrap
                                    visible: text.length > 0
                                }

                                Column {
                                    width: parent.width
                                    spacing: 3
                                    visible: (modelData.probable_causes || modelData.causes || []).length > 0
                                    Text {
                                        width: parent.width
                                        text: "● CAUSES PROBABLES"
                                        color: root.cAmber
                                        font.pixelSize: 11; font.bold: true
                                        font.letterSpacing: 1.2; font.family: "DejaVu Sans"
                                    }
                                    Repeater {
                                        model: modelData.probable_causes || modelData.causes || []
                                        Text {
                                            required property string modelData
                                            width: parent.width
                                            text: "  · " + modelData
                                            color: root.cDim
                                            font.pixelSize: 13; font.family: "DejaVu Sans"
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: 3
                                    visible: (modelData.symptoms || []).length > 0
                                    Text {
                                        width: parent.width
                                        text: "● SYMPTÔMES"
                                        color: root.cAmber
                                        font.pixelSize: 11; font.bold: true
                                        font.letterSpacing: 1.2; font.family: "DejaVu Sans"
                                    }
                                    Repeater {
                                        model: modelData.symptoms || []
                                        Text {
                                            required property string modelData
                                            width: parent.width
                                            text: "  · " + modelData
                                            color: root.cDim
                                            font.pixelSize: 13; font.family: "DejaVu Sans"
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: 3
                                    visible: (modelData.recommended_actions || []).length > 0
                                    Text {
                                        width: parent.width
                                        text: "● ACTIONS RECOMMANDÉES"
                                        color: root.cCyan
                                        font.pixelSize: 11; font.bold: true
                                        font.letterSpacing: 1.2; font.family: "DejaVu Sans"
                                    }
                                    Repeater {
                                        model: modelData.recommended_actions || []
                                        Text {
                                            required property string modelData
                                            width: parent.width
                                            text: "  · " + modelData
                                            color: root.cDim
                                            font.pixelSize: 13; font.family: "DejaVu Sans"
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── FOOTER RECOMMENDATIONS CARD ──────────────────────
                    Rectangle {
                        width: parent.width
                        implicitHeight: footerInner.implicitHeight + 24
                        radius: 14
                        color: Qt.rgba(1, 1, 1, 0.04)
                        border.color: Qt.rgba(0.30, 0.82, 1, 0.30)
                        border.width: 1
                        visible: {
                            const recs = reportData
                                ? (reportData.recommendations || reportData.overall_recommendations || [])
                                : []
                            return recs.length > 0
                        }

                        Column {
                            id: footerInner
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 18
                            anchors.topMargin: 12
                            spacing: 4

                            Text {
                                width: parent.width
                                text: "● RECOMMANDATIONS GÉNÉRALES"
                                color: root.cGreen
                                font.pixelSize: 11; font.bold: true
                                font.letterSpacing: 1.2; font.family: "DejaVu Sans"
                            }

                            Repeater {
                                model: reportData
                                       ? (reportData.recommendations || reportData.overall_recommendations || [])
                                       : []
                                Text {
                                    required property string modelData
                                    width: parent.width
                                    text: "  · " + modelData
                                    color: root.cDim
                                    font.pixelSize: 13; font.family: "DejaVu Sans"
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
