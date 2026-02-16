import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Use Page for StackView (best practice), avoids anchor conflicts (conflits d’ancrage)
Page {
    id: page
    title: "Diagnostic"
    property var nav: null

    // OLD (kept):
    // Item { anchors.fill: parent ... }

    background: Rectangle {
        color: "transparent"
    }

    component GlassCard: Rectangle {
        radius: 22
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
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
                onClicked: {
                    if (nav) nav.pop()
                    // old (kept): StackView.view.pop()
                }
            }

            Text {
                text: "Profile 3 – Diagnostic"
                color: "white"
                font.pixelSize: 20
                font.bold: true
            }

            Item { Layout.fillWidth: true }
        }

        GlassCard {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                Text {
                    text: "Diagnostic Controls (mock for now)"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }

                Text {
                    text: "No car connected yet. We will add real ELM327 logic later.\nFor now, UI + services + networking are validated."
                    color: Qt.rgba(1,1,1,0.65)
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Button { text: "Read DTC"; onClicked: console.text += "Read DTC clicked (placeholder)\n" }
                    Button { text: "Send to server"; onClicked: console.text += "Send clicked (placeholder)\n" }
                    Button { text: "Start live scan"; onClicked: console.text += "Start scan clicked (placeholder)\n" }
                    Button { text: "Stop"; onClicked: console.text += "Stop clicked (placeholder)\n" }
                }

                TextArea {
                    id: console
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readOnly: true
                    text: "Console:\n"
                }
            }
        }
    }
}
