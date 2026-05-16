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
    readonly property bool makeValid:     makeField.text.trim().length >= 1
    readonly property bool modelValid:    modelField.text.trim().length >= 1
    readonly property bool yearValid:     yearField.text.trim().length === 4 &&
                                          !isNaN(parseInt(yearField.text.trim()))
    readonly property bool vinValid:      vinField.text.trim().length === 0 ||
                                          /^[A-HJ-NPR-Z0-9]{17}$/i.test(vinField.text.trim())
    readonly property bool canFinish:     makeValid && modelValid && yearValid && vinValid

    // ── Keyboard shift ────────────────────────────────────────────────────
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
                text: "CAR INFO"
                color: root.cText; font.pixelSize: 18; font.bold: true
                font.letterSpacing: 4; font.family: "DejaVu Sans"
            }

            Item { Layout.fillWidth: true }

            Text {
                Layout.alignment: Qt.AlignVCenter
                text: "2 / 2"
                color: Qt.rgba(1, 1, 1, 0.40)
                font.pixelSize: 13; font.family: "DejaVu Sans"
            }
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 1 }

        // Form (two columns: Make/Model + Year/Fuel)
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            width: root.width * 0.62
            spacing: 14

            // Row 1: Make + Model
            RowLayout {
                Layout.fillWidth: true; spacing: 14

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 5
                    Text { text: "Make *"; color: Qt.rgba(1,1,1,0.70); font.pixelSize: 13; font.family: "DejaVu Sans" }
                    TextField {
                        id: makeField
                        Layout.fillWidth: true
                        placeholderText: "e.g. Renault"
                        font.pixelSize: 14; font.family: "DejaVu Sans"
                        color: root.cText
                        placeholderTextColor: Qt.rgba(1,1,1,0.30)
                        background: Rectangle {
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: makeField.activeFocus ? root.cCyan
                                          : (root.makeValid || makeField.text.length === 0 ? Qt.rgba(1,1,1,0.15) : root.cWarn)
                            border.width: 1; radius: 8
                            Behavior on border.color { ColorAnimation { duration: 200 } }
                        }
                        leftPadding: 12; rightPadding: 12
                        readOnly: false
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                root.kbVisible = true
                                keyboard.show(makeField)
                            }
                        }
                        Keys.onReturnPressed: modelField.forceActiveFocus()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 5
                    Text { text: "Model *"; color: Qt.rgba(1,1,1,0.70); font.pixelSize: 13; font.family: "DejaVu Sans" }
                    TextField {
                        id: modelField
                        Layout.fillWidth: true
                        placeholderText: "e.g. Symbol"
                        font.pixelSize: 14; font.family: "DejaVu Sans"
                        color: root.cText
                        placeholderTextColor: Qt.rgba(1,1,1,0.30)
                        background: Rectangle {
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: modelField.activeFocus ? root.cCyan
                                          : (root.modelValid || modelField.text.length === 0 ? Qt.rgba(1,1,1,0.15) : root.cWarn)
                            border.width: 1; radius: 8
                            Behavior on border.color { ColorAnimation { duration: 200 } }
                        }
                        leftPadding: 12; rightPadding: 12
                        readOnly: false
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                root.kbVisible = true
                                keyboard.show(modelField)
                            }
                        }
                        Keys.onReturnPressed: yearField.forceActiveFocus()
                    }
                }
            }

            // Row 2: Year + Fuel Type
            RowLayout {
                Layout.fillWidth: true; spacing: 14

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 5
                    Text { text: "Year *"; color: Qt.rgba(1,1,1,0.70); font.pixelSize: 13; font.family: "DejaVu Sans" }
                    TextField {
                        id: yearField
                        Layout.fillWidth: true
                        placeholderText: "e.g. 2010"
                        font.pixelSize: 14; font.family: "DejaVu Sans"
                        color: root.cText
                        placeholderTextColor: Qt.rgba(1,1,1,0.30)
                        inputMethodHints: Qt.ImhDigitsOnly
                        maximumLength: 4
                        background: Rectangle {
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: yearField.activeFocus ? root.cCyan
                                          : (root.yearValid || yearField.text.length === 0 ? Qt.rgba(1,1,1,0.15) : root.cWarn)
                            border.width: 1; radius: 8
                            Behavior on border.color { ColorAnimation { duration: 200 } }
                        }
                        leftPadding: 12; rightPadding: 12
                        readOnly: false
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                root.kbVisible = true
                                keyboard.show(yearField)
                            }
                        }
                        Keys.onReturnPressed: vinField.forceActiveFocus()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 5
                    Text { text: "Fuel Type *"; color: Qt.rgba(1,1,1,0.70); font.pixelSize: 13; font.family: "DejaVu Sans" }
                    ComboBox {
                        id: fuelCombo
                        Layout.fillWidth: true
                        model: ["Gasoline", "Diesel", "Hybrid", "Electric"]
                        font.pixelSize: 14; font.family: "DejaVu Sans"
                        // Tapping ComboBox dismisses the keyboard
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                keyboard.hide()
                                root.kbVisible = false
                            }
                        }
                        contentItem: Text {
                            leftPadding: 10
                            text: fuelCombo.displayText
                            font: fuelCombo.font
                            color: root.cText
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: Qt.rgba(1,1,1,0.05)
                            border.color: fuelCombo.activeFocus ? root.cCyan : Qt.rgba(1,1,1,0.15)
                            border.width: 1; radius: 8
                        }
                        popup.background: Rectangle {
                            color: "#111922"
                            border.color: root.cCyan; border.width: 1; radius: 8
                        }
                        delegate: ItemDelegate {
                            width: fuelCombo.width
                            contentItem: Text {
                                text: modelData
                                color: root.cText
                                font: fuelCombo.font
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 10
                            }
                            background: Rectangle {
                                color: hovered ? Qt.rgba(0.30, 0.82, 1, 0.12) : "transparent"
                            }
                        }
                    }
                }
            }

            // VIN (optional, full width)
            ColumnLayout {
                Layout.fillWidth: true; spacing: 5
                Text { text: "VIN (optional)"; color: Qt.rgba(1,1,1,0.70); font.pixelSize: 13; font.family: "DejaVu Sans" }
                TextField {
                    id: vinField
                    Layout.fillWidth: true
                    placeholderText: "17 characters — leave blank to add later"
                    font.pixelSize: 13; font.family: "DejaVu Sans"
                    color: root.cText
                    placeholderTextColor: Qt.rgba(1,1,1,0.30)
                    maximumLength: 17
                    background: Rectangle {
                        color: Qt.rgba(1,1,1,0.05)
                        border.color: vinField.activeFocus ? root.cCyan
                                      : (!root.vinValid && vinField.text.length > 0 ? root.cWarn : Qt.rgba(1,1,1,0.15))
                        border.width: 1; radius: 8
                        Behavior on border.color { ColorAnimation { duration: 200 } }
                    }
                    leftPadding: 12; rightPadding: 12
                    readOnly: false
                    onActiveFocusChanged: {
                        if (activeFocus) {
                            root.kbVisible = true
                            keyboard.show(vinField)
                        }
                    }
                }
                Text {
                    visible: vinField.text.length > 0 && !root.vinValid
                    text: "VIN must be exactly 17 alphanumeric characters (excluding I, O, Q)"
                    color: root.cWarn
                    font.pixelSize: 11; font.family: "DejaVu Sans"
                    wrapMode: Text.WordWrap
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

            Rectangle {
                width: 120; height: 44; radius: 22
                color: backBtn2.containsMouse ? Qt.rgba(1,1,1,0.10) : Qt.rgba(1,1,1,0.05)
                border.color: Qt.rgba(1,1,1,0.20); border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: "← Back"; color: Qt.rgba(1,1,1,0.60)
                    font.pixelSize: 14; font.family: "DejaVu Sans"
                }
                MouseArea {
                    id: backBtn2; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        keyboard.hide()
                        root.kbVisible = false
                        if (root.nav) root.nav.pop()
                    }
                }
            }

            Rectangle {
                width: 140; height: 44; radius: 22
                opacity: root.canFinish ? 1.0 : 0.40
                Behavior on opacity { NumberAnimation { duration: 200 } }
                color: finishMouse.containsMouse && root.canFinish
                       ? Qt.rgba(0.30, 0.82, 1, 0.28)
                       : Qt.rgba(0.30, 0.82, 1, 0.14)
                border.color: root.cCyan; border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }
                scale: finishMouse.pressed && root.canFinish ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "Finish ✓"; color: root.cCyan
                    font.pixelSize: 14; font.bold: true
                    font.family: "DejaVu Sans"
                }
                MouseArea {
                    id: finishMouse; anchors.fill: parent; hoverEnabled: true
                    cursorShape: root.canFinish ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (!root.canFinish) return
                        keyboard.hide()
                        root.kbVisible = false
                        UserProfile.carMake     = makeField.text.trim()
                        UserProfile.carModel    = modelField.text.trim()
                        UserProfile.carYear     = yearField.text.trim()
                        UserProfile.carFuelType = fuelCombo.currentText
                        UserProfile.carVIN      = vinField.text.trim()
                        UserProfile.saveProfile()
                        if (root.nav) {
                            root.nav.replace(null, Qt.resolvedUrl("../Home.qml"), { nav: root.nav })
                        }
                    }
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
