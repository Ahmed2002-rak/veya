import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

Item {
    id: root

    property string imageSource: "../assets/car_silhouette.png"
    property color  fallbackColor: "#4DD2FF"

    implicitWidth:  260
    implicitHeight: 360

    Image {
        id: img
        anchors.fill: parent
        anchors.margins: 8
        source: Qt.resolvedUrl(root.imageSource)
        fillMode: Image.PreserveAspectFit
        smooth: true
        sourceSize: Qt.size(width * 2, height * 2)
        visible: img.status === Image.Ready
        opacity: 0.95
    }

    MultiEffect {
        anchors.fill: img
        source: img
        visible: img.status === Image.Ready
        shadowEnabled: true
        shadowColor: "#000000"
        shadowBlur: 0.6
        shadowVerticalOffset: 6
        shadowHorizontalOffset: 0
        shadowOpacity: 0.45
    }

    // Fallback — rendered only when PNG fails to load or imageSource is empty.
    Shape {
        id: svgShape
        anchors.fill: parent
        anchors.margins: 16
        visible: img.status !== Image.Ready
        antialiasing: true
        layer.enabled: true
        layer.smooth: true

        // Main body — dark fill, accent outline at 60% opacity
        ShapePath {
            strokeColor: Qt.rgba(root.fallbackColor.r, root.fallbackColor.g,
                                 root.fallbackColor.b, 0.6)
            strokeWidth: 2
            fillColor:   "#2A3540"
            joinStyle:   ShapePath.RoundJoin
            capStyle:    ShapePath.RoundCap

            startX: svgShape.width * 0.50; startY: svgShape.height * 0.04
            PathQuad {
                x: svgShape.width * 0.86; y: svgShape.height * 0.18
                controlX: svgShape.width * 0.78; controlY: svgShape.height * 0.04
            }
            PathLine { x: svgShape.width * 0.92; y: svgShape.height * 0.42 }
            PathLine { x: svgShape.width * 0.92; y: svgShape.height * 0.78 }
            PathQuad {
                x: svgShape.width * 0.50; y: svgShape.height * 0.96
                controlX: svgShape.width * 0.92; controlY: svgShape.height * 0.96
            }
            PathQuad {
                x: svgShape.width * 0.08; y: svgShape.height * 0.78
                controlX: svgShape.width * 0.08; controlY: svgShape.height * 0.96
            }
            PathLine { x: svgShape.width * 0.08; y: svgShape.height * 0.42 }
            PathLine { x: svgShape.width * 0.14; y: svgShape.height * 0.18 }
            PathQuad {
                x: svgShape.width * 0.50; y: svgShape.height * 0.04
                controlX: svgShape.width * 0.22; controlY: svgShape.height * 0.04
            }
        }

        // Front windshield (hood end) — subtle translucent tint
        ShapePath {
            strokeColor: Qt.rgba(root.fallbackColor.r, root.fallbackColor.g,
                                 root.fallbackColor.b, 0.30)
            strokeWidth: 1
            fillColor:   Qt.rgba(root.fallbackColor.r, root.fallbackColor.g,
                                 root.fallbackColor.b, 0.12)
            startX: svgShape.width * 0.26; startY: svgShape.height * 0.22
            PathLine { x: svgShape.width * 0.74; y: svgShape.height * 0.22 }
            PathLine { x: svgShape.width * 0.70; y: svgShape.height * 0.38 }
            PathLine { x: svgShape.width * 0.30; y: svgShape.height * 0.38 }
            PathLine { x: svgShape.width * 0.26; y: svgShape.height * 0.22 }
        }

        // Rear window — same treatment, slightly narrower
        ShapePath {
            strokeColor: Qt.rgba(root.fallbackColor.r, root.fallbackColor.g,
                                 root.fallbackColor.b, 0.30)
            strokeWidth: 1
            fillColor:   Qt.rgba(root.fallbackColor.r, root.fallbackColor.g,
                                 root.fallbackColor.b, 0.10)
            startX: svgShape.width * 0.28; startY: svgShape.height * 0.62
            PathLine { x: svgShape.width * 0.72; y: svgShape.height * 0.62 }
            PathLine { x: svgShape.width * 0.76; y: svgShape.height * 0.78 }
            PathLine { x: svgShape.width * 0.24; y: svgShape.height * 0.78 }
            PathLine { x: svgShape.width * 0.28; y: svgShape.height * 0.62 }
        }

        // Front-left wheel
        ShapePath {
            strokeColor: Qt.rgba(root.fallbackColor.r, root.fallbackColor.g,
                                 root.fallbackColor.b, 0.40)
            strokeWidth: 1.5; fillColor: "#1A2530"
            startX: svgShape.width * 0.03; startY: svgShape.height * 0.12
            PathLine { x: svgShape.width * 0.17; y: svgShape.height * 0.12 }
            PathLine { x: svgShape.width * 0.17; y: svgShape.height * 0.28 }
            PathLine { x: svgShape.width * 0.03; y: svgShape.height * 0.28 }
            PathLine { x: svgShape.width * 0.03; y: svgShape.height * 0.12 }
        }

        // Front-right wheel
        ShapePath {
            strokeColor: Qt.rgba(root.fallbackColor.r, root.fallbackColor.g,
                                 root.fallbackColor.b, 0.40)
            strokeWidth: 1.5; fillColor: "#1A2530"
            startX: svgShape.width * 0.83; startY: svgShape.height * 0.12
            PathLine { x: svgShape.width * 0.97; y: svgShape.height * 0.12 }
            PathLine { x: svgShape.width * 0.97; y: svgShape.height * 0.28 }
            PathLine { x: svgShape.width * 0.83; y: svgShape.height * 0.28 }
            PathLine { x: svgShape.width * 0.83; y: svgShape.height * 0.12 }
        }

        // Rear-left wheel
        ShapePath {
            strokeColor: Qt.rgba(root.fallbackColor.r, root.fallbackColor.g,
                                 root.fallbackColor.b, 0.40)
            strokeWidth: 1.5; fillColor: "#1A2530"
            startX: svgShape.width * 0.03; startY: svgShape.height * 0.72
            PathLine { x: svgShape.width * 0.17; y: svgShape.height * 0.72 }
            PathLine { x: svgShape.width * 0.17; y: svgShape.height * 0.88 }
            PathLine { x: svgShape.width * 0.03; y: svgShape.height * 0.88 }
            PathLine { x: svgShape.width * 0.03; y: svgShape.height * 0.72 }
        }

        // Rear-right wheel
        ShapePath {
            strokeColor: Qt.rgba(root.fallbackColor.r, root.fallbackColor.g,
                                 root.fallbackColor.b, 0.40)
            strokeWidth: 1.5; fillColor: "#1A2530"
            startX: svgShape.width * 0.83; startY: svgShape.height * 0.72
            PathLine { x: svgShape.width * 0.97; y: svgShape.height * 0.72 }
            PathLine { x: svgShape.width * 0.97; y: svgShape.height * 0.88 }
            PathLine { x: svgShape.width * 0.83; y: svgShape.height * 0.88 }
            PathLine { x: svgShape.width * 0.83; y: svgShape.height * 0.72 }
        }
    }
}
