import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: root
    clip: true
    property var nav: null
    background: Rectangle { color: "transparent" }

    readonly property color cCyan:  "#4DD2FF"
    readonly property color cText:  "white"

    // ── Background (matches app palette) ─────────────────────────────────
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
        border.color: "#1A4040"; border.width: 2
        radius: 24
    }

    // ── Content ───────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.centerIn: parent
        width: root.width * 0.62
        spacing: 0

        // Logo / title
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "VEYA"
            color: root.cCyan
            font.pixelSize: 56
            font.bold: true
            font.letterSpacing: 10
            font.family: "DejaVu Sans"
        }

        Item { Layout.preferredHeight: 8 }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Welcome to VEYA"
            color: root.cText
            font.pixelSize: 28
            font.bold: true
            font.family: "DejaVu Sans"
        }

        Item { Layout.preferredHeight: 10 }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Your in-car diagnostic companion"
            color: Qt.rgba(1, 1, 1, 0.60)
            font.pixelSize: 16
            font.family: "DejaVu Sans"
        }

        Item { Layout.preferredHeight: 28 }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(0.30, 0.82, 1, 0.20)
        }

        Item { Layout.preferredHeight: 24 }

        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            text: "Let's set up your profile so VEYA can generate personalised\nreports for your car. This takes about 1 minute."
            color: Qt.rgba(1, 1, 1, 0.70)
            font.pixelSize: 15
            font.family: "DejaVu Sans"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Item { Layout.preferredHeight: 36 }

        // Get Started button
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: root.width * 0.30
            height: 46
            radius: 23
            color: startMouse.containsMouse
                   ? Qt.rgba(0.30, 0.82, 1, 0.25)
                   : Qt.rgba(0.30, 0.82, 1, 0.14)
            border.color: root.cCyan
            border.width: 1
            Behavior on color { ColorAnimation { duration: 150 } }
            scale: startMouse.pressed ? 0.97 : 1.0
            Behavior on scale { NumberAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: "Get Started →"
                color: root.cCyan
                font.pixelSize: 16
                font.bold: true
                font.family: "DejaVu Sans"
            }
            MouseArea {
                id: startMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.nav)
                        root.nav.push(Qt.resolvedUrl("DriverOnboarding.qml"), { nav: root.nav })
                }
            }
        }
    }
}
