import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Veya 1.0

// Phase 3.0a: WifiStatusProvider singleton drives the WIFI dot in the top-left.

Page {
    id: root

    property var nav: null

    background: Rectangle { color: "transparent" }

    component GlassCard: Rectangle {
        radius: 22
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
    }

    // ── Main layout (identical to original) ──────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        spacing: 50

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Text {
                text: "Welcome to VEYA"
                color: "white"
                font.pixelSize: 52; font.bold: true; font.family: "DejaVu Sans"
                Layout.alignment: Qt.AlignHCenter
                style: Text.Raised; styleColor: Qt.rgba(0.3, 0.85, 1.0, 0.3)
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 180; height: 4; radius: 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(0.3, 0.85, 1.0, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(0.3, 0.85, 1.0, 0.8) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.3, 0.85, 1.0, 0.0) }
                }
            }

            Text {
                text: "Select Your Profile"
                color: Qt.rgba(1, 1, 1, 0.65); font.pixelSize: 18; font.family: "DejaVu Sans"
                Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 8
            }
        }

        Item { Layout.fillHeight: true; Layout.preferredHeight: 20 }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 80

            component CircleProfileButton: Item {
                id: circleButton
                property string profileName: ""
                property string iconText:    ""
                property color  accentColor: "#4DD2FF"
                property color  glowColor:   Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.3)
                signal clicked()

                width: 220; height: 280
                property bool isHovered: false
                property bool isPressed: false

                scale: isPressed ? 0.95 : (isHovered ? 1.05 : 1.0)
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                ColumnLayout {
                    anchors.fill: parent; spacing: 20

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        width: 180; height: 180

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + 20; height: parent.height + 20; radius: width / 2
                            color: "transparent"
                            border.color: circleButton.glowColor; border.width: 3
                            opacity: circleButton.isHovered ? 0.8 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            RotationAnimator on rotation {
                                from: 0; to: 360; duration: 4000
                                loops: Animation.Infinite; running: circleButton.isHovered
                            }
                        }

                        Rectangle {
                            id: mainCircle
                            anchors.centerIn: parent; width: 180; height: 180; radius: width / 2
                            color: Qt.rgba(1, 1, 1, 0.08)
                            border.color: Qt.rgba(circleButton.accentColor.r, circleButton.accentColor.g, circleButton.accentColor.b, 0.5)
                            border.width: 2

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(circleButton.accentColor.r, circleButton.accentColor.g, circleButton.accentColor.b, 0.15) }
                                    GradientStop { position: 1.0; color: Qt.rgba(circleButton.accentColor.r, circleButton.accentColor.g, circleButton.accentColor.b, 0.05) }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: circleButton.iconText; font.pixelSize: 64; color: "white"
                                style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.5)
                            }

                            Rectangle {
                                id: ripple; anchors.centerIn: parent
                                width: 0; height: 0; radius: width / 2
                                color: Qt.rgba(1, 1, 1, 0.3); opacity: 0
                                PropertyAnimation { id: rippleAnim;        target: ripple; property: "width";   from: 0; to: mainCircle.width;  duration: 400; easing.type: Easing.OutQuad }
                                PropertyAnimation { id: rippleHeightAnim;  target: ripple; property: "height";  from: 0; to: mainCircle.height; duration: 400; easing.type: Easing.OutQuad }
                                PropertyAnimation { id: rippleOpacityAnim; target: ripple; property: "opacity"; from: 0.5; to: 0;               duration: 400; easing.type: Easing.OutQuad }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered:  circleButton.isHovered = true
                            onExited:   circleButton.isHovered = false
                            onPressed:  { circleButton.isPressed = true; rippleAnim.start(); rippleHeightAnim.start(); rippleOpacityAnim.start() }
                            onReleased: circleButton.isPressed = false
                            onClicked:  circleButton.clicked()
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 160; Layout.preferredHeight: 50
                        radius: 25
                        color: circleButton.isHovered
                               ? Qt.rgba(circleButton.accentColor.r, circleButton.accentColor.g, circleButton.accentColor.b, 0.15)
                               : Qt.rgba(1, 1, 1, 0.05)
                        border.color: Qt.rgba(circleButton.accentColor.r, circleButton.accentColor.g, circleButton.accentColor.b, 0.4)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Text {
                            anchors.centerIn: parent; text: circleButton.profileName
                            color: "white"; font.pixelSize: 20; font.bold: true; font.family: "DejaVu Sans"
                        }
                    }
                }
            }

            CircleProfileButton {
                profileName: "Drive"; iconText: "⟡"; accentColor: "#4DD2FF"
                onClicked: if (root.nav) root.nav.push(Qt.resolvedUrl("Drive.qml"), { nav: root.nav })
            }
            CircleProfileButton {
                profileName: "Media"; iconText: "♪"; accentColor: "#B788FF"
                onClicked: comingSoon.open()
            }
            CircleProfileButton {
                profileName: "Diagnostic"; iconText: "⚙"; accentColor: "#47FF9A"
                onClicked: if (root.nav) root.nav.push(Qt.resolvedUrl("Diagnostic.qml"), { nav: root.nav })
            }
        }

        Item { Layout.fillHeight: true; Layout.preferredHeight: 30 }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 300; Layout.preferredHeight: 45
            radius: 22; color: Qt.rgba(1,1,1,0.04)
            border.color: Qt.rgba(1,1,1,0.08); border.width: 1
            RowLayout {
                anchors.fill: parent; anchors.margins: 12; spacing: 10
                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: VehicleDataProvider.connected ? "#47FF9A" : "#FF4D6D"
                    Behavior on color { ColorAnimation { duration: 300 } }
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.3; duration: 1000 }
                        NumberAnimation { from: 0.3; to: 1.0; duration: 1000 }
                    }
                }
                Text {
                    text: VehicleDataProvider.connected ? "Backend Connected" : "Backend Offline"
                    color: Qt.rgba(1,1,1,0.7); font.pixelSize: 14; font.family: "DejaVu Sans"
                }
                Item { Layout.fillWidth: true }
                Text { text: "Pi 5"; color: Qt.rgba(1,1,1,0.5); font.pixelSize: 12; font.family: "DejaVu Sans" }
            }
        }
    }

    // ── DemoBadge — floating, sits to the left of the mode toggle ────────
    DemoBadge {
        id: demoBadge
        anchors.verticalCenter: modeToggle.verticalCenter
        anchors.right:          modeToggle.left
        anchors.rightMargin:    10
    }

    // ── Top-left indicator cluster — Wi-Fi and Bluetooth dots ────────────
    Column {
        anchors { top: parent.top; left: parent.left; topMargin: 16; leftMargin: 16 }
        spacing: 4

        // Wi-Fi indicator
        Item {
            id: wifiIndicator
            width: 48; height: 48

            readonly property color dotColor: {
                if (!VehicleDataProvider.connected)  return "#6B7785"
                if (WifiStatusProvider.connected)    return "#47FF9A"
                return "#FFB347"
            }

            scale: wifiMouse.pressed ? 0.95 : (wifiMouse.containsMouse ? 1.05 : 1.0)
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "WIFI"
                    color: Qt.rgba(1, 1, 1, 0.80)
                    font.pixelSize: 11; font.bold: true
                    font.letterSpacing: 1.2; font.family: "DejaVu Sans"
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 8; height: 8; radius: 4
                    color: wifiIndicator.dotColor
                    Behavior on color { ColorAnimation { duration: 400 } }
                }
            }

            MouseArea {
                id: wifiMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.nav)
                        root.nav.push(Qt.resolvedUrl("WifiManager.qml"), { nav: root.nav })
                }
            }
        }

        // Bluetooth indicator
        Item {
            id: btIndicator
            width: 48; height: 48

            // Colour states:
            // Green  #47FF9A — ESP32 connected and streaming
            // Cyan   #4DD2FF — paired but bridge not running / no telemetry yet
            // Amber  #FFB347 — BT adapter on, no paired device
            // Grey   #6B7785 — adapter off or status unknown
            readonly property color dotColor: {
                if (!VehicleDataProvider.connected)                              return "#6B7785"
                if (BluetoothStatusProvider.esp32Connected)                     return "#47FF9A"
                if (BluetoothStatusProvider.bridgeRunning)                      return "#4DD2FF"
                if (BluetoothStatusProvider.pairedDevices.length > 0)           return "#4DD2FF"
                if (BluetoothStatusProvider.adapterPowered)                     return "#FFB347"
                return "#6B7785"
            }

            scale: btMouse.pressed ? 0.95 : (btMouse.containsMouse ? 1.05 : 1.0)
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "BT"
                    color: Qt.rgba(1, 1, 1, 0.80)
                    font.pixelSize: 11; font.bold: true
                    font.letterSpacing: 1.2; font.family: "DejaVu Sans"
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 8; height: 8; radius: 4
                    color: btIndicator.dotColor
                    Behavior on color { ColorAnimation { duration: 400 } }
                }
            }

            MouseArea {
                id: btMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (root.nav)
                        root.nav.push(Qt.resolvedUrl("BluetoothManager.qml"), { nav: root.nav })
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  MODE TOGGLE — floating pill, top-right corner
    //  Overlaid on existing layout. Sends WS command to obd_service.py.
    //  Backend hot-swaps provider; dataMode updates on next JSON frame.
    // ════════════════════════════════════════════════════════════════════
    Item {
        id: modeToggle
        anchors { top: parent.top; right: parent.right; topMargin: 16; rightMargin: 16 }
        width:  toggleRow.implicitWidth + 28
        height: 36

        readonly property bool isReal: VehicleDataProvider.dataMode === "elm"

        // Pill background
        Rectangle {
            anchors.fill: parent
            radius: parent.height / 2
            color: modeToggle.isReal ? Qt.rgba(0.28, 1, 0.60, 0.12)
                                     : Qt.rgba(0.30, 0.82, 1,   0.10)
            border.color: modeToggle.isReal ? "#47FF9A" : "#4DD2FF"
            border.width: 1
            Behavior on color        { ColorAnimation { duration: 350 } }
            Behavior on border.color { ColorAnimation { duration: 350 } }
        }

        Row {
            id: toggleRow
            anchors.centerIn: parent
            spacing: 8

            // "TEST" label
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "TEST"
                color: modeToggle.isReal ? Qt.rgba(1,1,1,0.28) : "#4DD2FF"
                font.pixelSize: 11; font.bold: true
                font.letterSpacing: 1.5; font.family: "DejaVu Sans"
                Behavior on color { ColorAnimation { duration: 250 } }
            }

            // Track + sliding knob
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 22

                Rectangle {
                    anchors.fill: parent; radius: height / 2
                    color: modeToggle.isReal ? Qt.rgba(0.28, 1, 0.60, 0.22)
                                             : Qt.rgba(0.30, 0.82, 1, 0.18)
                    Behavior on color { ColorAnimation { duration: 250 } }
                }

                Rectangle {
                    width: 18; height: 18; radius: width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    x: modeToggle.isReal ? parent.width - width - 2 : 2
                    color: modeToggle.isReal ? "#47FF9A" : "#4DD2FF"
                    Behavior on x     { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation  { duration: 250 } }
                    // Glow halo
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 8; height: parent.height + 8; radius: width / 2
                        color: parent.color; opacity: 0.22
                    }
                }
            }

            // "REAL" label
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "REAL"
                color: modeToggle.isReal ? "#47FF9A" : Qt.rgba(1,1,1,0.28)
                font.pixelSize: 11; font.bold: true
                font.letterSpacing: 1.5; font.family: "DejaVu Sans"
                Behavior on color { ColorAnimation { duration: 250 } }
            }
        }

        // "switching…" / error toast — bound to provider state
        Rectangle {
            readonly property bool hasError: VehicleDataProvider.lastModeError.length > 0
            anchors { top: parent.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
            width: switchLabel.implicitWidth + 16; height: 22; radius: 11
            color: hasError ? Qt.rgba(0.5, 0.05, 0.10, 0.85) : Qt.rgba(0, 0, 0, 0.65)
            border.color: hasError ? "#FF4D6D" : Qt.rgba(1,1,1,0.12)
            border.width: 1
            visible: VehicleDataProvider.connected
                     && (VehicleDataProvider.switching || hasError)
            Text {
                id: switchLabel; anchors.centerIn: parent
                text: parent.hasError ? VehicleDataProvider.lastModeError : "switching…"
                color: parent.hasError ? "#FFB0B8" : Qt.rgba(1,1,1,0.65)
                font.pixelSize: 10; font.family: "DejaVu Sans"
            }
        }

        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (!VehicleDataProvider.connected) return
                VehicleDataProvider.sendModeCommand(modeToggle.isReal ? "mock" : "elm")
            }
        }
    }

    // ── Coming Soon popup (unchanged) ────────────────────────────────────
    Popup {
        id: comingSoon
        modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        width: 420; height: 220
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        background: Rectangle { radius: 16; color: "#1a1f26"; border.color: Qt.rgba(1,1,1,0.15); border.width: 1 }
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 18; spacing: 12
            Text { text: "Media Profile"; color: "white"; font.pixelSize: 16; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Text { text: "🎵 Coming Soon"; color: "white"; font.pixelSize: 24; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Text { text: "Android Auto and media features\nwill be available in a future update."; color: Qt.rgba(1,1,1,0.7); font.pixelSize: 14; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter }
            Item { Layout.fillHeight: true }
            Button { text: "OK"; Layout.alignment: Qt.AlignHCenter; onClicked: comingSoon.close() }
        }
    }
}
