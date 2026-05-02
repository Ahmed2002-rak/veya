import QtQuick

Item {
    id: root

    property string currentGear: "—"
    property color  accentColor: "#4DD2FF"
    property real   activeSize:   28
    property real   inactiveSize: 18

    implicitHeight: activeSize + 6
    implicitWidth:  row.implicitWidth + 8

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 18

        Repeater {
            model: ["P", "R", "N", "D"]

            delegate: Text {
                required property string modelData

                readonly property bool isActive:
                    root.currentGear !== "—" && modelData === root.currentGear

                anchors.verticalCenter: parent.verticalCenter
                text:  modelData
                color: isActive ? root.accentColor : Qt.rgba(1, 1, 1, 0.30)
                font.family:    "DejaVu Sans"
                font.pixelSize: isActive ? root.activeSize : root.inactiveSize
                font.bold:      isActive
                font.letterSpacing: 1

                Behavior on color { ColorAnimation  { duration: 200 } }
                Behavior on font.pixelSize { NumberAnimation { duration: 200 } }
            }
        }
    }
}
