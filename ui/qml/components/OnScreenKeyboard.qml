import QtQuick
import QtQuick.Controls

// ─────────────────────────────────────────────────────────────────────────────
// OnScreenKeyboard — custom QWERTY keyboard for linuxfb kiosk (no X11).
//
// Usage (instantiate once per page, near the bottom of the item tree so z-order
// puts it above everything):
//
//   OnScreenKeyboard {
//       id: keyboard
//       anchors.left:  parent.left
//       anchors.right: parent.right
//       onDoneClicked: keyboard.hide()
//   }
//
//   // In a TextField:
//   onActiveFocusChanged: if (activeFocus) keyboard.show(this)
//
// The keyboard slides up from below. Call show(textField) to display it and
// set the active target; hide() to dismiss.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: kbRoot

    // ── Public API ────────────────────────────────────────────────────────
    property var    target:  null    // active TextField receiving keystrokes
    property bool   shifted: false   // uppercase state

    signal doneClicked()

    function show(tf) {
        if (tf) target = tf
        kbRect.visible = true
        kbRect.y = kbRoot.height - kbRect.height
    }

    function hide() {
        kbRect.y = kbRoot.height
        // Delay visibility=false until slide is done
        hideTimer.restart()
    }

    // ── Geometry ──────────────────────────────────────────────────────────
    // The parent page should give kbRoot anchors that span the full page
    // width and height (so kbRect can slide up from the very bottom).
    height: parent ? parent.height : 600
    width:  parent ? parent.width  : 1024
    // Don't consume touch events when hidden
    enabled: kbRect.visible

    Timer {
        id: hideTimer
        interval: 210
        repeat: false
        onTriggered: kbRect.visible = false
    }

    // ── Keyboard rectangle ────────────────────────────────────────────────
    Rectangle {
        id: kbRect
        width:   kbRoot.width
        height:  280
        y:       kbRoot.height    // starts off-screen below
        visible: false
        z:       100

        color: "#0E1418"
        border.color: "#1A4040"
        border.width: 2

        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // ── Internal helpers ──────────────────────────────────────────────

        function insertChar(c) {
            if (!kbRoot.target) return
            kbRoot.target.text = kbRoot.target.text + (kbRoot.shifted ? c.toUpperCase() : c.toLowerCase())
        }

        function doBackspace() {
            if (!kbRoot.target || kbRoot.target.text.length === 0) return
            kbRoot.target.text = kbRoot.target.text.slice(0, -1)
        }

        function doSpace() {
            if (!kbRoot.target) return
            kbRoot.target.text = kbRoot.target.text + " "
        }

        // ── Reusable key component ─────────────────────────────────────────
        component KeyBtn: Rectangle {
            id: kb
            property string label: ""
            property int    kw:    88   // key width override
            property int    kh:    46   // key height override
            property bool   isSpecial: false

            signal tapped()

            width:  kw; height: kh
            radius: 6
            color: kbPress.pressed
                   ? Qt.rgba(0.30, 0.82, 1, 0.30)
                   : (isSpecial ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.06))
            border.color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: kb.label
                color: "white"
                font.pixelSize: kb.isSpecial ? 12 : 16
                font.family: "DejaVu Sans"
                font.bold: kb.isSpecial
            }

            MouseArea {
                id: kbPress
                anchors.fill: parent
                onClicked: kb.tapped()
            }
        }

        // ── Layout ─────────────────────────────────────────────────────────
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 8
            spacing: 5

            // ── Row 1: digits ──────────────────────────────────────────────
            Row {
                spacing: 5
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: ["1","2","3","4","5","6","7","8","9","0"]
                    delegate: KeyBtn {
                        label: modelData
                        onTapped: kbRect.insertChar(modelData)
                    }
                }
            }

            // ── Row 2: qwertyuiop ──────────────────────────────────────────
            Row {
                spacing: 5
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: ["q","w","e","r","t","y","u","i","o","p"]
                    delegate: KeyBtn {
                        label: kbRoot.shifted ? modelData.toUpperCase() : modelData
                        onTapped: kbRect.insertChar(modelData)
                    }
                }
            }

            // ── Row 3: asdfghjkl ───────────────────────────────────────────
            Row {
                spacing: 5
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: ["a","s","d","f","g","h","j","k","l"]
                    delegate: KeyBtn {
                        kw: 99
                        label: kbRoot.shifted ? modelData.toUpperCase() : modelData
                        onTapped: kbRect.insertChar(modelData)
                    }
                }
            }

            // ── Row 4: SHIFT + zxcvbnm + BACKSPACE ────────────────────────
            Row {
                spacing: 5
                anchors.horizontalCenter: parent.horizontalCenter

                KeyBtn {
                    kw: 120; label: kbRoot.shifted ? "⇧ ON" : "⇧"
                    isSpecial: true
                    color: kbRoot.shifted ? Qt.rgba(0.30, 0.82, 1, 0.22) : Qt.rgba(1,1,1,0.09)
                    onTapped: kbRoot.shifted = !kbRoot.shifted
                }

                Repeater {
                    model: ["z","x","c","v","b","n","m"]
                    delegate: KeyBtn {
                        label: kbRoot.shifted ? modelData.toUpperCase() : modelData
                        onTapped: kbRect.insertChar(modelData)
                    }
                }

                KeyBtn {
                    kw: 120; label: "⌫ Del"; isSpecial: true
                    onTapped: kbRect.doBackspace()
                }
            }

            // ── Row 5: special keys ────────────────────────────────────────
            Row {
                spacing: 5
                anchors.horizontalCenter: parent.horizontalCenter

                KeyBtn { kw: 300; label: "SPACE"; isSpecial: true; onTapped: kbRect.doSpace() }
                KeyBtn { kw: 88;  label: ",";  onTapped: kbRect.insertChar(",") }
                KeyBtn { kw: 88;  label: ".";  onTapped: kbRect.insertChar(".") }
                KeyBtn { kw: 88;  label: "@";  onTapped: kbRect.insertChar("@") }
                KeyBtn { kw: 88;  label: "-";  onTapped: kbRect.insertChar("-") }

                // DONE button — dismisses keyboard
                Rectangle {
                    width: 140; height: 46; radius: 6
                    color: doneMouse.pressed
                           ? Qt.rgba(0.30, 0.82, 1, 0.40)
                           : Qt.rgba(0.30, 0.82, 1, 0.18)
                    border.color: "#4DD2FF"; border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "Done ✓"; color: "#4DD2FF"
                        font.pixelSize: 14; font.bold: true
                        font.family: "DejaVu Sans"
                    }
                    MouseArea {
                        id: doneMouse; anchors.fill: parent
                        onClicked: {
                            kbRoot.shifted = false
                            kbRoot.doneClicked()
                        }
                    }
                }
            }
        }
    }
}
