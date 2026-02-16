import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: root

    // navigation reference (StackView instance)
    property var nav: null

    // Avoid white default background of Page
    background: Rectangle { color: "transparent" }

    // Reusable "glass" card
    component GlassCard: Rectangle {
        radius: 22
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 40
        spacing: 50

        // Top - Welcome Title
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Text {
                text: "Welcome to VEYA"
                color: "white"
                font.pixelSize: 52
                font.bold: true
                font.family: "DejaVu Sans"
                Layout.alignment: Qt.AlignHCenter
                style: Text.Raised
                styleColor: Qt.rgba(0.3, 0.85, 1.0, 0.3)
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 180
                height: 4
                radius: 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Qt.rgba(0.3, 0.85, 1.0, 0.0) }
                    GradientStop { position: 0.5; color: Qt.rgba(0.3, 0.85, 1.0, 0.8) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.3, 0.85, 1.0, 0.0) }
                }
            }

            Text {
                text: "Select Your Profile"
                color: Qt.rgba(1, 1, 1, 0.65)
                font.pixelSize: 18
                font.family: "DejaVu Sans"
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
            }
        }

        // Spacer
        Item { Layout.fillHeight: true; Layout.preferredHeight: 20 }

        // Three Circular Profile Buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 80

            // Profile Button Component (Circular)
            component CircleProfileButton: Item {
                id: circleButton
                property string profileName: ""
                property string iconText: ""
                property color accentColor: "#4DD2FF"
                property color glowColor: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.3)
                signal clicked()

                width: 220
                height: 280

                // Hover and press states
                property bool isHovered: false
                property bool isPressed: false

                scale: isPressed ? 0.95 : (isHovered ? 1.05 : 1.0)
                Behavior on scale {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 20

                    // Circular Button
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        width: 180
                        height: 180

                        // Outer glow ring (animated)
                        Rectangle {
                            id: outerGlow
                            anchors.centerIn: parent
                            width: parent.width + 20
                            height: parent.height + 20
                            radius: width / 2
                            color: "transparent"
                            border.color: circleButton.glowColor
                            border.width: 3
                            opacity: circleButton.isHovered ? 0.8 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }

                            RotationAnimator on rotation {
                                from: 0
                                to: 360
                                duration: 4000
                                loops: Animation.Infinite
                                running: circleButton.isHovered
                            }
                        }

                        // Main circle with glass effect
                        Rectangle {
                            id: mainCircle
                            anchors.centerIn: parent
                            width: 180
                            height: 180
                            radius: width / 2
                            color: Qt.rgba(1, 1, 1, 0.08)
                            border.color: Qt.rgba(circleButton.accentColor.r,
                                                  circleButton.accentColor.g,
                                                  circleButton.accentColor.b, 0.5)
                            border.width: 2

                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.0
                                        color: Qt.rgba(circleButton.accentColor.r,
                                                       circleButton.accentColor.g,
                                                       circleButton.accentColor.b, 0.15)
                                    }
                                    GradientStop {
                                        position: 1.0
                                        color: Qt.rgba(circleButton.accentColor.r,
                                                       circleButton.accentColor.g,
                                                       circleButton.accentColor.b, 0.05)
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: circleButton.iconText
                                font.pixelSize: 64
                                color: "white"
                                style: Text.Raised
                                styleColor: Qt.rgba(0, 0, 0, 0.5)
                            }

                            // Ripple effect on click
                            Rectangle {
                                id: ripple
                                anchors.centerIn: parent
                                width: 0
                                height: 0
                                radius: width / 2
                                color: Qt.rgba(1, 1, 1, 0.3)
                                opacity: 0

                                PropertyAnimation { id: rippleAnim; target: ripple; property: "width";  from: 0; to: mainCircle.width;  duration: 400; easing.type: Easing.OutQuad }
                                PropertyAnimation { id: rippleHeightAnim; target: ripple; property: "height"; from: 0; to: mainCircle.height; duration: 400; easing.type: Easing.OutQuad }
                                PropertyAnimation { id: rippleOpacityAnim; target: ripple; property: "opacity"; from: 0.5; to: 0; duration: 400; easing.type: Easing.OutQuad }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            onEntered: circleButton.isHovered = true
                            onExited: circleButton.isHovered = false
                            onPressed: {
                                circleButton.isPressed = true
                                rippleAnim.start()
                                rippleHeightAnim.start()
                                rippleOpacityAnim.start()
                            }
                            onReleased: circleButton.isPressed = false
                            onClicked: circleButton.clicked()
                        }
                    }

                    // Profile Name Label
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 160
                        Layout.preferredHeight: 50
                        radius: 25
                        color: circleButton.isHovered ?
                               Qt.rgba(circleButton.accentColor.r,
                                       circleButton.accentColor.g,
                                       circleButton.accentColor.b, 0.15) :
                               Qt.rgba(1, 1, 1, 0.05)
                        border.color: Qt.rgba(circleButton.accentColor.r,
                                              circleButton.accentColor.g,
                                              circleButton.accentColor.b, 0.4)
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 200 } }

                        Text {
                            anchors.centerIn: parent
                            text: circleButton.profileName
                            color: "white"
                            font.pixelSize: 20
                            font.bold: true
                            font.family: "DejaVu Sans"
                        }
                    }
                }
            }

            // Drive Profile
            CircleProfileButton {
                profileName: "Drive"
                iconText: "⟡"
                accentColor: "#4DD2FF"

                onClicked: {
                    // old (kept): StackView.view.push("Drive.qml")
                    if (root.nav) root.nav.push(Qt.resolvedUrl("Drive.qml"), { nav: root.nav })
                }
            }

            // Media Profile
            CircleProfileButton {
                profileName: "Media"
                iconText: "♪"
                accentColor: "#B788FF"
                onClicked: comingSoon.open()
            }

            // Diagnostic Profile
            CircleProfileButton {
                profileName: "Diagnostic"
                iconText: "⚙"
                accentColor: "#47FF9A"

                onClicked: {
                    // old (kept): StackView.view.push("Diagnostic.qml")
                    if (root.nav) root.nav.push(Qt.resolvedUrl("Diagnostic.qml"), { nav: root.nav })
                }
            }
        }

        // Spacer
        Item { Layout.fillHeight: true; Layout.preferredHeight: 30 }

        // Bottom info bar
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 300
            Layout.preferredHeight: 45
            radius: 22
            color: Qt.rgba(1, 1, 1, 0.04)
            border.color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: "#47FF9A"

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.3; duration: 1000 }
                        NumberAnimation { from: 0.3; to: 1.0; duration: 1000 }
                    }
                }

                Text {
                    text: "System Ready"
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.pixelSize: 14
                    font.family: "DejaVu Sans"
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Pi 5"
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: 12
                    font.family: "DejaVu Sans"
                }
            }
        }
    }

    // Coming Soon Dialog
    Popup {
        id: comingSoon
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        width: 420
        height: 220
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        background: Rectangle {
            radius: 16
            color: "#1a1f26"
            border.color: Qt.rgba(1, 1, 1, 0.15)
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            Text {
                text: "Media Profile"
                color: "white"
                font.pixelSize: 16
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "🎵 Coming Soon"
                color: "white"
                font.pixelSize: 24
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Android Auto and media features\nwill be available in a future update."
                color: Qt.rgba(1, 1, 1, 0.7)
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }

            Item { Layout.fillHeight: true }

            Button {
                text: "OK"
                Layout.alignment: Qt.AlignHCenter
                onClicked: comingSoon.close()
            }
        }
    }
}
