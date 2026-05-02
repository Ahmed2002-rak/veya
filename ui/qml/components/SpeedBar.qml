import QtQuick

Item {
    id: root

    property real  value:        0     // 0..1
    property int   segmentCount: 8
    property color accentColor:  "#4DD2FF"
    property real  segmentSpacing: 4
    property real  segmentRadius:  3

    function clamp(x, a, b) { return Math.max(a, Math.min(b, x)) }

    readonly property real _filled: clamp(value, 0, 1) * segmentCount

    implicitHeight: 14

    Row {
        id: row
        anchors.fill: parent
        spacing: root.segmentSpacing

        Repeater {
            model: root.segmentCount

            delegate: Rectangle {
                required property int index

                readonly property bool active: index < Math.ceil(root._filled)

                width:  (row.width - (root.segmentCount - 1) * root.segmentSpacing) / root.segmentCount
                height: parent.height
                radius: root.segmentRadius
                color:  active ? root.accentColor
                              : Qt.rgba(root.accentColor.r,
                                        root.accentColor.g,
                                        root.accentColor.b,
                                        0.15)

                Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
        }
    }
}
