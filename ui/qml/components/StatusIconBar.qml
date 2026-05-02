import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Decorative icons — interactivity reserved for future profiles
Item {
    id: bar

    property real  iconSize:    24
    property color accentColor: "#4DD2FF"
    property color dimColor:    Qt.rgba(1, 1, 1, 0.55)

    implicitHeight: iconSize * 1.4 + 8
    implicitWidth:  row.implicitWidth + 8

    Row {
        id: row
        anchors.centerIn: parent
        spacing: bar.iconSize * 1.0

        Repeater {
            model: [
                { src: "../assets/icon_music.svg",    centerIcon: false },
                { src: "../assets/icon_menu.svg",     centerIcon: false },
                { src: "../assets/icon_car.svg",      centerIcon: true  },
                { src: "../assets/icon_phone.svg",    centerIcon: false },
                { src: "../assets/icon_settings.svg", centerIcon: false }
            ]
            delegate: Item {
                id: cell
                required property var modelData
                width:  bar.iconSize * (modelData.centerIcon ? 1.45 : 1.0)
                height: bar.iconSize * (modelData.centerIcon ? 1.45 : 1.0)
                anchors.verticalCenter: parent.verticalCenter

                property bool hovered: false
                scale: hovered ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                Image {
                    id: img
                    anchors.fill: parent
                    source: Qt.resolvedUrl(cell.modelData.src)
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(width * 2, height * 2)
                    smooth: true
                    visible: false  // shown via MultiEffect
                }

                MultiEffect {
                    anchors.fill: img
                    source: img
                    colorization: 1.0
                    colorizationColor: cell.modelData.centerIcon ? bar.accentColor : bar.dimColor
                    brightness: cell.modelData.centerIcon ? 0.0 : -0.1
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: cell.hovered = true
                    onExited:  cell.hovered = false
                }
            }
        }
    }
}
