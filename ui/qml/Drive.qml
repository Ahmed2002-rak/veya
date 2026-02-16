import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Veya 1.0

Page {
    id: root

    property var nav: null
    background: Rectangle { color: "transparent" }

    // Bind to the singleton (NO websocket here)
    property int rpm: Math.round(VehicleDataProvider.rpm)
    property real speed: VehicleDataProvider.speedKph
    property real coolant: VehicleDataProvider.coolantC
    property real throttle: VehicleDataProvider.throttlePct
    property string conn: VehicleDataProvider.statusText

    property string warn: {
        let w = []
        if (VehicleDataProvider.warnCoolantHigh) w.push("coolant_high")
        if (VehicleDataProvider.warnOverspeed) w.push("overspeed")
        return w.length ? w.join(" ") : "none"
    }

    function clamp(x, a, b) { return Math.max(a, Math.min(b, x)); }

    component GlassCard: Rectangle {
        radius: 22
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0B0F14" }
            GradientStop { position: 1.0; color: "#070A0E" }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Button {
                text: "← Back"
                onClicked: if (root.nav) root.nav.pop()
            }

            Text {
                text: "Profile 1 – Drive"
                color: "white"
                font.pixelSize: 20
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            GlassCard {
                height: 38
                width: 190
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: (conn.indexOf("open") !== -1 || conn.indexOf("connected") !== -1) ? "#47FF9A"
                              : (conn.indexOf("connecting") !== -1) ? "#FFD84D"
                              : "#FF4D6D"
                    }
                    Text { text: conn; color: Qt.rgba(1,1,1,0.85); font.pixelSize: 13 }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14

            GlassCard {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 10

                    Text { text: "SPEED"; color: Qt.rgba(1,1,1,0.55); font.pixelSize: 14 }

                    Text {
                        text: Math.round(speed).toString()
                        color: "white"
                        font.pixelSize: 72
                        font.bold: true
                    }
                    Text { text: "km/h"; color: Qt.rgba(1,1,1,0.75); font.pixelSize: 16 }

                    Item { Layout.fillHeight: true }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 16
                        radius: 8
                        color: Qt.rgba(1,1,1,0.08)
                        border.color: Qt.rgba(1,1,1,0.10)
                        border.width: 1

                        Rectangle {
                            height: parent.height
                            radius: 8
                            width: parent.width * clamp(speed / 160.0, 0, 1)
                            color: Qt.rgba(0.30, 0.82, 1.0, 0.65)
                        }
                    }
                }
            }

            GlassCard {
                Layout.preferredWidth: 380
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 14

                    Text { text: "ENGINE"; color: Qt.rgba(1,1,1,0.55); font.pixelSize: 14 }

                    GaugeRing {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 240
                        min: 0
                        max: 8000
                        value: rpm
                        unit: "rpm"
                        label: "RPM"
                        accent: "#7CFF4A"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        GlassCard {
                            Layout.fillWidth: true
                            height: 78
                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Text { text: "Coolant"; color: Qt.rgba(1,1,1,0.6); font.pixelSize: 12 }
                                Text { text: coolant.toFixed(1) + " °C"; color: "white"; font.pixelSize: 20; font.bold: true }
                            }
                        }

                        GlassCard {
                            Layout.fillWidth: true
                            height: 78
                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Text { text: "Throttle"; color: Qt.rgba(1,1,1,0.6); font.pixelSize: 12 }
                                Text { text: throttle.toFixed(1) + " %"; color: "white"; font.pixelSize: 20; font.bold: true }
                            }
                        }
                    }

                    GlassCard {
                        Layout.fillWidth: true
                        height: 54
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10
                            Text { text: "Warnings:"; color: Qt.rgba(1,1,1,0.6); font.pixelSize: 12 }
                            Text { text: warn; color: (warn === "none") ? "#47FF9A" : "#FF4D6D"; font.pixelSize: 13; font.bold: true }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
    }
}
