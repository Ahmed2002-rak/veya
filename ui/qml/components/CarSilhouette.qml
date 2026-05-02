import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

Item {
    id: root

    property string imageSource: ""
    property color  fallbackColor: "#4DD2FF"

    implicitWidth:  260
    implicitHeight: 360

    // Real image path (preferred)
    Image {
        id: img
        anchors.fill: parent
        anchors.margins: 8
        source: root.imageSource
        fillMode: Image.PreserveAspectFit
        smooth: true
        sourceSize: Qt.size(width * 2, height * 2)
        visible: status === Image.Ready
        opacity: 0.95
    }

    // Soft drop shadow for the photo
    MultiEffect {
        anchors.fill: img
        source: img
        visible: img.visible
        shadowEnabled: true
        shadowColor: "#000000"
        shadowBlur: 0.6
        shadowVerticalOffset: 6
        shadowHorizontalOffset: 0
        shadowOpacity: 0.45
    }

    // Inline SVG-style fallback (top-down silhouette) — rendered only when
    // the image source is empty or fails to load. Uses Qt Quick Shapes so
    // there is no missing-asset failure mode.
    Shape {
        id: fallback
        anchors.fill: parent
        anchors.margins: 16
        visible: !img.visible
        antialiasing: true
        layer.enabled: true
        layer.smooth: true

        ShapePath {
            strokeColor: root.fallbackColor
            strokeWidth: 2
            fillColor:   Qt.rgba(root.fallbackColor.r,
                                 root.fallbackColor.g,
                                 root.fallbackColor.b,
                                 0.18)
            joinStyle:   ShapePath.RoundJoin
            capStyle:    ShapePath.RoundCap

            // Stylized top-down car body, normalized 0..1 then scaled.
            startX: fallback.width * 0.50
            startY: fallback.height * 0.04

            PathQuad {
                x: fallback.width * 0.86; y: fallback.height * 0.18
                controlX: fallback.width * 0.78; controlY: fallback.height * 0.04
            }
            PathLine { x: fallback.width * 0.92; y: fallback.height * 0.42 }
            PathLine { x: fallback.width * 0.92; y: fallback.height * 0.78 }
            PathQuad {
                x: fallback.width * 0.50; y: fallback.height * 0.96
                controlX: fallback.width * 0.92; controlY: fallback.height * 0.96
            }
            PathQuad {
                x: fallback.width * 0.08; y: fallback.height * 0.78
                controlX: fallback.width * 0.08; controlY: fallback.height * 0.96
            }
            PathLine { x: fallback.width * 0.08; y: fallback.height * 0.42 }
            PathLine { x: fallback.width * 0.14; y: fallback.height * 0.18 }
            PathQuad {
                x: fallback.width * 0.50; y: fallback.height * 0.04
                controlX: fallback.width * 0.22; controlY: fallback.height * 0.04
            }
        }

        // Inner windshield/roof line for visual depth
        ShapePath {
            strokeColor: Qt.rgba(root.fallbackColor.r,
                                 root.fallbackColor.g,
                                 root.fallbackColor.b,
                                 0.5)
            strokeWidth: 1.5
            fillColor: "transparent"
            startX: fallback.width * 0.22; startY: fallback.height * 0.30
            PathLine { x: fallback.width * 0.78; y: fallback.height * 0.30 }
            PathLine { x: fallback.width * 0.74; y: fallback.height * 0.55 }
            PathLine { x: fallback.width * 0.26; y: fallback.height * 0.55 }
            PathLine { x: fallback.width * 0.22; y: fallback.height * 0.30 }
        }
    }
}
