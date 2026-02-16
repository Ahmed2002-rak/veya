import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: win
    visible: true
    visibility: Window.FullScreen
    title: "VEYA"
    color: "#0B0F14"
    flags: Qt.FramelessWindowHint
    font.family: "DejaVu Sans"

    // Key-catcher (reliable)
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Q &&
                (event.modifiers & Qt.ControlModifier) &&
                (event.modifiers & Qt.ShiftModifier)) {
                Qt.quit()
                event.accepted = true
            }
        }
    }

    // Background
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0B0F14" }
            GradientStop { position: 1.0; color: "#070A0E" }
        }
        Repeater {
            model: 70
            Rectangle {
                width: 2; height: 2; radius: 1
                color: Qt.rgba(1,1,1,0.08)
                x: Math.random() * parent.width
                y: Math.random() * parent.height
            }
        }
    }

    StackView {
        id: stack
        anchors.fill: parent

        // IMPORTANT: pass nav reference explicitly
        initialItem: Home { nav: stack }
    }
}
