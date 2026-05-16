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

    readonly property color cBg:     "#0B0F14"
    readonly property color cBorder: "#1A4040"
    readonly property color cCyan:   "#4DD2FF"
    readonly property color cText:   "white"
    readonly property color cWarn:   "#FF4D6D"
    readonly property color cGreen:  "#47FF9A"

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
        anchors.fill: parent; anchors.margins: 8
        color: "transparent"
        border.color: root.cBorder; border.width: 2; radius: 24
    }

    // ── Layout ───────────────────────────────────────────────────────────
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
                text: "SETTINGS"; color: root.cText
                font.pixelSize: 18; font.bold: true
                font.letterSpacing: 4; font.family: "DejaVu Sans"
            }

            Item { Layout.fillWidth: true }

            // Mode + DEMO badges (right cluster, capped at 30%)
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: root.width * 0.28
                Layout.maximumWidth:   root.width * 0.30
                spacing: 4
                Rectangle {
                    Layout.alignment: Qt.AlignRight
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: Math.min(modeBadgeRow.implicitWidth + 16, root.width * 0.28)
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
                        id: modeBadgeRow
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

        Item { Layout.preferredHeight: 16 }

        // ── Settings rows ─────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            // Wi-Fi row
            SettingsRow {
                Layout.fillWidth: true
                title: "Wi-Fi"
                subtitle: wifiSubtitle()
                iconSource: "qrc:/qt/qml/Veya/qml/assets/icon_settings.svg"
                iconColor: root.cCyan
                enabled: true
                onRowClicked: {
                    if (root.nav)
                        root.nav.push(Qt.resolvedUrl("WifiManager.qml"), { nav: root.nav })
                }

                function wifiSubtitle() {
                    if (!VehicleDataProvider.connected) return "No backend connection"
                    return "Manage Wi-Fi networks"
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1,1,1,0.07) }

            // Driver Profile row (placeholder)
            SettingsRow {
                Layout.fillWidth: true
                title: "Driver Profile"
                subtitle: UserProfile.profileExists
                          ? UserProfile.driverName + " · " + UserProfile.carMake + " " + UserProfile.carModel
                          : "Not set up"
                iconSource: "qrc:/qt/qml/Veya/qml/assets/icon_car.svg"
                iconColor: Qt.rgba(1, 1, 1, 0.40)
                enabled: false
                subtitle2: "Coming soon"
                onRowClicked: {}
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1,1,1,0.07) }

            // About row (placeholder)
            SettingsRow {
                Layout.fillWidth: true
                title: "About VEYA"
                subtitle: "Phase 2.2b · Qt 6.8.2 · Python asyncio"
                iconSource: "qrc:/qt/qml/Veya/qml/assets/icon_menu.svg"
                iconColor: Qt.rgba(1, 1, 1, 0.40)
                enabled: false
                subtitle2: "Coming soon"
                onRowClicked: {}
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(1,1,1,0.07) }
        }

        Item { Layout.fillHeight: true }
    }

    // ── Inline SettingsRow component ─────────────────────────────────────
    component SettingsRow: Rectangle {
        id: sRow
        property string title:       ""
        property string subtitle:    ""
        property string subtitle2:   ""
        property string iconSource:  ""
        property color  iconColor:   "white"
        property bool   enabled:     true
        signal rowClicked()

        height: 68
        color: (enabled && rowMouse.containsMouse)
               ? Qt.rgba(0.30, 0.82, 1, 0.06)
               : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }

        RowLayout {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            anchors.leftMargin: 8; anchors.rightMargin: 12
            spacing: 14

            // Icon
            Item {
                width: 36; height: 36
                Image {
                    id: rowIcon
                    anchors.fill: parent
                    source: sRow.iconSource
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(72, 72)
                    smooth: true
                    visible: false
                }
                MultiEffect {
                    source: rowIcon; anchors.fill: rowIcon
                    colorization: 1.0; colorizationColor: sRow.iconColor
                    opacity: sRow.enabled ? 1.0 : 0.40
                }
            }

            // Text
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                Text {
                    text: sRow.title; color: sRow.enabled ? root.cText : Qt.rgba(1,1,1,0.40)
                    font.pixelSize: 16; font.bold: true; font.family: "DejaVu Sans"
                }
                Text {
                    visible: sRow.subtitle.length > 0
                    text: sRow.subtitle
                    color: Qt.rgba(1,1,1,0.50)
                    font.pixelSize: 12; font.family: "DejaVu Sans"
                    elide: Text.ElideRight; Layout.fillWidth: true
                }
                Text {
                    visible: !sRow.enabled && sRow.subtitle2.length > 0
                    text: sRow.subtitle2
                    color: Qt.rgba(1,0.82,0,0.60)
                    font.pixelSize: 11; font.family: "DejaVu Sans"
                }
            }

            // Arrow
            Text {
                visible: sRow.enabled
                text: "›"; color: root.cCyan
                font.pixelSize: 24; font.family: "DejaVu Sans"
            }
        }

        MouseArea {
            id: rowMouse; anchors.fill: parent; hoverEnabled: true
            cursorShape: sRow.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (sRow.enabled) sRow.rowClicked()
        }
    }
}
