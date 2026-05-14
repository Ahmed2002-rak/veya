import QtQuick
import Veya 1.0

Item {
    id: root

    property real iconSize: 32
    property real spacing:   4

    // TODO: VehicleDataProvider.warnEngine does not exist yet (Phase 2.2 scope).
    // Bound to debugForceWarnings as placeholder so the icon lights up during
    // debug forced-warning tests. Remove/replace in Phase 2.2.
    readonly property bool warnEngine: VehicleDataProvider.debugForceWarnings

    readonly property bool _anyActive: warnEngine
                                    || VehicleDataProvider.warnCoolantHigh
                                    || VehicleDataProvider.warnOverspeed
                                    || VehicleDataProvider.warnLowFuel
                                    || VehicleDataProvider.warnLowBattery

    implicitWidth:  iconRow.implicitWidth
    implicitHeight: _anyActive ? root.iconSize : 0

    Row {
        id: iconRow
        anchors.centerIn: parent
        spacing: root.spacing

        // ── ENGINE CHECK (red) ────────────────────────────────────────────
        Canvas {
            width:  root.iconSize
            height: root.iconSize
            visible: root.warnEngine
            antialiasing: true

            onVisibleChanged: if (visible) requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var s = width / 32.0
                ctx.strokeStyle = "#FF4D6D"
                ctx.fillStyle   = "#FF4D6D"
                ctx.lineWidth   = 2 * s
                ctx.lineJoin    = "round"
                // Engine block body
                ctx.strokeRect(7*s, 13*s, 18*s, 13*s)
                // Four cylinder heads on top
                for (var i = 0; i < 4; i++) {
                    ctx.fillRect((8 + i*4)*s, 8*s, 3*s, 6*s)
                }
                // Exhaust/crankshaft stub at bottom-center
                ctx.fillRect(13*s, 26*s, 6*s, 3*s)
            }

            SequentialAnimation on opacity {
                running: root.warnEngine
                loops: Animation.Infinite
                NumberAnimation { to: 0.7; duration: 1500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 1500; easing.type: Easing.InOutSine }
            }
        }

        // ── TEMPERATURE (amber) ───────────────────────────────────────────
        Canvas {
            width:  root.iconSize
            height: root.iconSize
            visible: VehicleDataProvider.warnCoolantHigh
            antialiasing: true

            onVisibleChanged: if (visible) requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var s = width / 32.0
                ctx.fillStyle = "#FFB347"
                // Thermometer stem (rounded rectangle via rect + arcs)
                ctx.beginPath()
                ctx.rect(13*s, 4*s, 6*s, 18*s)
                ctx.fill()
                // Bulb at bottom
                ctx.beginPath()
                ctx.arc(16*s, 24*s, 6*s, 0, Math.PI * 2)
                ctx.fill()
                // White center detail
                ctx.fillStyle = "rgba(0,0,0,0.30)"
                ctx.beginPath()
                ctx.arc(16*s, 24*s, 3*s, 0, Math.PI * 2)
                ctx.fill()
            }

            SequentialAnimation on opacity {
                running: VehicleDataProvider.warnCoolantHigh
                loops: Animation.Infinite
                NumberAnimation { to: 0.7; duration: 1500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 1500; easing.type: Easing.InOutSine }
            }
        }

        // ── FUEL (amber) ──────────────────────────────────────────────────
        Canvas {
            width:  root.iconSize
            height: root.iconSize
            visible: VehicleDataProvider.warnLowFuel
            antialiasing: true

            onVisibleChanged: if (visible) requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var s = width / 32.0
                ctx.strokeStyle = "#FFB347"
                ctx.fillStyle   = "#FFB347"
                ctx.lineWidth   = 2 * s
                ctx.lineJoin    = "round"
                // Tank body
                ctx.strokeRect(5*s, 10*s, 14*s, 18*s)
                // Pump head cap
                ctx.fillRect(7*s, 6*s, 10*s, 5*s)
                // Nozzle arm
                ctx.beginPath()
                ctx.moveTo(19*s, 14*s)
                ctx.lineTo(25*s, 14*s)
                ctx.lineTo(25*s, 8*s)
                ctx.lineTo(22*s, 8*s)
                ctx.stroke()
                // Nozzle tip
                ctx.fillRect(20*s, 7*s, 5*s, 3*s)
            }

            SequentialAnimation on opacity {
                running: VehicleDataProvider.warnLowFuel
                loops: Animation.Infinite
                NumberAnimation { to: 0.7; duration: 1500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 1500; easing.type: Easing.InOutSine }
            }
        }

        // ── BATTERY (amber) ───────────────────────────────────────────────
        Canvas {
            width:  root.iconSize
            height: root.iconSize
            visible: VehicleDataProvider.warnLowBattery
            antialiasing: true

            onVisibleChanged: if (visible) requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var s = width / 32.0
                ctx.strokeStyle = "#FFB347"
                ctx.fillStyle   = "#FFB347"
                ctx.lineWidth   = 2 * s
                // Battery body
                ctx.strokeRect(3*s, 11*s, 23*s, 13*s)
                // Terminals (top nubs)
                ctx.fillRect(8*s,  8*s, 4*s, 4*s)
                ctx.fillRect(19*s, 8*s, 4*s, 4*s)
                // "!" inside battery
                ctx.lineWidth = 2.5 * s
                ctx.beginPath()
                ctx.moveTo(14.5*s, 15*s)
                ctx.lineTo(14.5*s, 20*s)
                ctx.stroke()
                ctx.beginPath()
                ctx.arc(14.5*s, 22*s, 1.5*s, 0, Math.PI * 2)
                ctx.fill()
            }

            SequentialAnimation on opacity {
                running: VehicleDataProvider.warnLowBattery
                loops: Animation.Infinite
                NumberAnimation { to: 0.7; duration: 1500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 1500; easing.type: Easing.InOutSine }
            }
        }
    }
}
