import QtQuick
import Veya 1.0

Rectangle {
    id: root

    property color accentColor: "#FFD84D"
    property string labelText:  "DEMO MODE"

    visible: VehicleDataProvider.dataMode === "mock"

    implicitWidth:  label.implicitWidth + 22
    implicitHeight: 22
    radius: height / 2
    color:  Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.16)
    border.color: accentColor
    border.width: 1

    Text {
        id: label
        anchors.centerIn: parent
        text: root.labelText
        color: root.accentColor
        font.family:    "DejaVu Sans"
        font.pixelSize: 10
        font.bold:      true
        font.letterSpacing: 1.6
    }

    SequentialAnimation on opacity {
        loops: Animation.Infinite
        running: root.visible
        NumberAnimation { from: 1.0; to: 0.7; duration: 1500; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.7; to: 1.0; duration: 1500; easing.type: Easing.InOutSine }
    }
}
