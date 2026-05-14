import QtQuick

Item {
    id: g
    width: 320
    height: 320

    property real min: 0
    property real max: 240
    property real value: 0
    property string unit: "km/h"
    property string label: "SPEED"
    property color accent: "#22E6B8"

    property real startDeg: -210
    property real spanDeg: 240
    property real thickness: 18

    function clamp(x, a, b) { return Math.max(a, Math.min(b, x)); }
    function norm() {
        if (max <= min) return 0;
        return clamp((value - min) / (max - min), 0, 1);
    }

    Canvas {
        id: c
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            // safer than ctx.reset() across Qt versions:
            ctx.clearRect(0, 0, width, height);

            var w = width, h = height;
            var cx = w * 0.5, cy = h * 0.5;
            var r  = Math.min(w, h) * 0.42;
            var t  = g.thickness;

            var a0 = (g.startDeg) * Math.PI / 180.0;
            var a1 = (g.startDeg + g.spanDeg) * Math.PI / 180.0;

            // background arc
            ctx.lineWidth = t;
            ctx.lineCap = "round";
            ctx.strokeStyle = "rgba(255,255,255,0.12)";
            ctx.beginPath();
            ctx.arc(cx, cy, r, a0, a1, false);
            ctx.stroke();

            // value arc
            var p = g.norm();
            ctx.strokeStyle = g.accent; // Canvas accepts css color strings
            ctx.beginPath();
            ctx.arc(cx, cy, r, a0, a0 + (a1 - a0) * p, false);
            ctx.stroke();

            // ticks
            ctx.lineWidth = 2;
            ctx.strokeStyle = "rgba(255,255,255,0.18)";
            var tickCount = 24;
            for (var i = 0; i <= tickCount; i++) {
                var u = i / tickCount;
                var a = a0 + (a1 - a0) * u;
                var r0 = r + t * 0.75;
                var r1 = r + t * 1.25;
                ctx.beginPath();
                ctx.moveTo(cx + Math.cos(a) * r0, cy + Math.sin(a) * r0);
                ctx.lineTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1);
                ctx.stroke();
            }
        }

        // repaint on changes
        Connections {
            target: g
            function onValueChanged() { c.requestPaint(); }
            function onMinChanged() { c.requestPaint(); }
            function onMaxChanged() { c.requestPaint(); }
            function onAccentChanged() { c.requestPaint(); }
            function onThicknessChanged() { c.requestPaint(); }
            function onStartDegChanged() { c.requestPaint(); }
            function onSpanDegChanged() { c.requestPaint(); }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
    }

    Column {
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: Math.round(g.value).toString()
            color: "white"
            font.pixelSize: 52
            font.bold: true
            font.family: "DejaVu Sans"
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            text: g.unit
            color: "white"
            opacity: 0.6
            font.pixelSize: 22
            font.family: "DejaVu Sans"
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            text: g.label
            color: "white"
            opacity: 0.5
            font.pixelSize: 12
            font.letterSpacing: 2
            font.family: "DejaVu Sans"
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
