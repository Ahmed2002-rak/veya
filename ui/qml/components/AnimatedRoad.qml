import QtQuick
import QtQuick.Shapes
import Veya 1.0

Item {
    id: root

    property real  speedKph:   VehicleDataProvider.speedKph
    property color accentColor: "#4DD2FF"

    clip: true

    // Road surface — perspective trapezoid (top narrow, bottom wide)
    Shape {
        anchors.fill: parent
        antialiasing: true

        ShapePath {
            strokeColor: "#1A2530"
            strokeWidth: 1
            fillColor:   "#0A0F14"

            // top-left, top-right (narrow), bottom-right, bottom-left (wide)
            startX: root.width * 0.35; startY: 0
            PathLine { x: root.width * 0.65; y: 0 }
            PathLine { x: root.width * 1.00; y: root.height }
            PathLine { x: root.width * 0.00; y: root.height }
            PathLine { x: root.width * 0.35; y: 0 }
        }
    }

    // Left lane marking (dashed, scrolling)
    Item {
        x: root.width * 0.42
        width: 3
        height: root.height
        clip: true

        property real dashH:    root.height * 0.12
        property real gapH:     root.height * 0.08
        property real totalH:   dashH + gapH
        property real scrollY:  0

        // Duration inversely proportional to speed; effectively stopped below 1 km/h
        NumberAnimation on scrollY {
            from: 0
            to:   parent.totalH
            duration: root.speedKph > 1 ? Math.max(40, 2000 / root.speedKph) : 999999
            loops: Animation.Infinite
            running: true
        }

        Repeater {
            model: Math.ceil(root.height / parent.totalH) + 2
            Rectangle {
                x: 0
                y: (index * parent.totalH) + parent.scrollY - parent.totalH
                width: 3
                height: parent.dashH
                color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                               root.accentColor.b, 0.45)
                radius: 1
            }
        }
    }

    // Right lane marking (dashed, scrolling — mirrors left)
    Item {
        x: root.width * 0.555
        width: 3
        height: root.height
        clip: true

        property real dashH:    root.height * 0.12
        property real gapH:     root.height * 0.08
        property real totalH:   dashH + gapH
        property real scrollY:  0

        NumberAnimation on scrollY {
            from: 0
            to:   parent.totalH
            duration: root.speedKph > 1 ? Math.max(40, 2000 / root.speedKph) : 999999
            loops: Animation.Infinite
            running: true
        }

        Repeater {
            model: Math.ceil(root.height / parent.totalH) + 2
            Rectangle {
                x: 0
                y: (index * parent.totalH) + parent.scrollY - parent.totalH
                width: 3
                height: parent.dashH
                color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                               root.accentColor.b, 0.45)
                radius: 1
            }
        }
    }
}
