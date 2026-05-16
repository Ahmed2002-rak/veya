import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Veya 1.0

Page {
    id: root
    clip: true
    property var nav: null
    background: Rectangle { color: "transparent" }

    readonly property color cCyan:   "#4DD2FF"
    readonly property color cText:   "white"
    readonly property color cBorder: "#1A4040"
    readonly property color cWarn:   "#FF4D6D"

    // ── Validation ───────────────────────────────────────────────────────
    readonly property bool nameValid:    nameField.text.trim().length >= 2
    readonly property bool contactValid: contactField.text.trim().length >= 6
    readonly property bool canProceed:   nameValid && contactValid

    // ── Keyboard shift — when keyboard is up, slide form content up 130px ──
    property bool kbVisible: false
    property real kbOffset:  kbVisible ? 130 : 0
    Behavior on kbOffset { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

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
        transform: Translate { y: -root.kbOffset }

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
                    onClicked: {
                        keyboard.hide()
                        root.kbVisible = false
                        if (root.nav) root.nav.pop()
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "DRIVER INFO"
                color: root.cText; font.pixelSize: 18; font.bold: true
                font.letterSpacing: 4; font.family: "DejaVu Sans"
            }

            Item { Layout.fillWidth: true }

            // Step indicator
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "1 / 2"
                color: Qt.rgba(1, 1, 1, 0.40)
                font.pixelSize: 13; font.family: "DejaVu Sans"
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 1 }

        // Form
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            width: root.width * 0.52
            spacing: 16

            // Name field
            ColumnLayout {
                Layout.fillWidth: true; spacing: 6
                Text {
                    text: "Your Name *"
                    color: Qt.rgba(1, 1, 1, 0.70)
                    font.pixelSize: 13; font.family: "DejaVu Sans"
                }
                TextField {
                    id: nameField
                    Layout.fillWidth: true
                    placeholderText: "e.g. Ahmed Rezig"
                    font.pixelSize: 15; font.family: "DejaVu Sans"
                    color: root.cText
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.30)
                    background: Rectangle {
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.color: nameField.activeFocus
                                      ? root.cCyan
                                      : (root.nameValid || nameField.text.length === 0
                                         ? Qt.rgba(1, 1, 1, 0.15)
                                         : root.cWarn)
                        border.width: 1; radius: 8
                        Behavior on border.color { ColorAnimation { duration: 200 } }
                    }
                    leftPadding: 12; rightPadding: 12
                    readOnly: false
                    onActiveFocusChanged: {
                        if (activeFocus) {
                            root.kbVisible = true
                            keyboard.show(nameField)
                        }
                    }
                    Keys.onReturnPressed: contactField.forceActiveFocus()
                }
                Text {
                    visible: nameField.text.length > 0 && !root.nameValid
                    text: "Name must be at least 2 characters"
                    color: root.cWarn
                    font.pixelSize: 11; font.family: "DejaVu Sans"
                }
            }

            // Emergency contact field
            ColumnLayout {
                Layout.fillWidth: true; spacing: 6
                Text {
                    text: "Emergency Contact *"
                    color: Qt.rgba(1, 1, 1, 0.70)
                    font.pixelSize: 13; font.family: "DejaVu Sans"
                }
                TextField {
                    id: contactField
                    Layout.fillWidth: true
                    placeholderText: "e.g. +213 555 12 34 56"
                    font.pixelSize: 15; font.family: "DejaVu Sans"
                    color: root.cText
                    placeholderTextColor: Qt.rgba(1, 1, 1, 0.30)
                    background: Rectangle {
                        color: Qt.rgba(1, 1, 1, 0.05)
                        border.color: contactField.activeFocus
                                      ? root.cCyan
                                      : (root.contactValid || contactField.text.length === 0
                                         ? Qt.rgba(1, 1, 1, 0.15)
                                         : root.cWarn)
                        border.width: 1; radius: 8
                        Behavior on border.color { ColorAnimation { duration: 200 } }
                    }
                    leftPadding: 12; rightPadding: 12
                    readOnly: false
                    onActiveFocusChanged: {
                        if (activeFocus) {
                            root.kbVisible = true
                            keyboard.show(contactField)
                        }
                    }
                    Keys.onReturnPressed: { if (root.canProceed) nextBtn.clicked() }
                }
                Text {
                    visible: contactField.text.length > 0 && !root.contactValid
                    text: "Contact must be at least 6 characters"
                    color: root.cWarn
                    font.pixelSize: 11; font.family: "DejaVu Sans"
                }
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 1 }

        // Buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            spacing: 16

            Item { Layout.fillWidth: true }

            // Back
            Rectangle {
                width: 120; height: 44; radius: 22
                color: backBtn.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05)
                border.color: Qt.rgba(1, 1, 1, 0.20); border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: "← Back"; color: Qt.rgba(1, 1, 1, 0.60)
                    font.pixelSize: 14; font.family: "DejaVu Sans"
                }
                MouseArea {
                    id: backBtn; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        keyboard.hide()
                        root.kbVisible = false
                        if (root.nav) root.nav.pop()
                    }
                }
            }

            // Next
            Rectangle {
                id: nextBtn
                width: 140; height: 44; radius: 22
                opacity: root.canProceed ? 1.0 : 0.40
                Behavior on opacity { NumberAnimation { duration: 200 } }
                color: nextMouse.containsMouse && root.canProceed
                       ? Qt.rgba(0.30, 0.82, 1, 0.28)
                       : Qt.rgba(0.30, 0.82, 1, 0.14)
                border.color: root.cCyan; border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }

                function clicked() {
                    if (!root.canProceed) return
                    keyboard.hide()
                    root.kbVisible = false
                    UserProfile.driverName       = nameField.text.trim()
                    UserProfile.emergencyContact = contactField.text.trim()
                    if (root.nav)
                        root.nav.push(Qt.resolvedUrl("CarOnboarding.qml"), { nav: root.nav })
                }

                Text {
                    anchors.centerIn: parent
                    text: "Next →"; color: root.cCyan
                    font.pixelSize: 14; font.bold: true
                    font.family: "DejaVu Sans"
                }
                MouseArea {
                    id: nextMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: root.canProceed ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: nextBtn.clicked()
                }
            }

            Item { Layout.fillWidth: true }
        }

        Item { Layout.preferredHeight: 8 }
    }

    // ── On-screen keyboard ───────────────────────────────────────────────
    OnScreenKeyboard {
        id: keyboard
        anchors.fill: parent
        onDoneClicked: {
            root.kbVisible = false
            keyboard.hide()
        }
    }
}
