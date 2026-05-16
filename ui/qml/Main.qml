import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Veya 1.0

ApplicationWindow {
    id: win
    visible: true
    visibility: Window.FullScreen
    title: "VEYA"
    color: "#0B0F14"
    flags: Qt.FramelessWindowHint
    font.family: "DejaVu Sans"

    // Key-catcher (reliable)
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Q &&
                (event.modifiers & Qt.ControlModifier) &&
                (event.modifiers & Qt.ShiftModifier)) {
                Qt.quit()
                event.accepted = true
            }
        }
    }

    // Background
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0B0F14" }
            GradientStop { position: 1.0; color: "#070A0E" }
        }
        Repeater {
            model: 70
            Rectangle {
                width: 2; height: 2; radius: 1
                color: Qt.rgba(1,1,1,0.08)
                x: Math.random() * parent.width
                y: Math.random() * parent.height
            }
        }
    }

    // PHASE-2.1.1-DEBUG: Force all warnings ON for 10 seconds.
    // Remove this block in Phase 2.2 when real warning UX is finalized.
    Shortcut {
        sequence: "Ctrl+Shift+W"
        context: Qt.ApplicationShortcut
        onActivated: {
            VehicleDataProvider.debugForceWarnings = true
            debugWarningTimer.restart()
        }
    }
    Timer {
        id: debugWarningTimer
        interval: 10000
        repeat: false
        onTriggered: VehicleDataProvider.debugForceWarnings = false
    }

    StackView {
        id: stack
        anchors.fill: parent

        // IMPORTANT: pass nav reference explicitly
        initialItem: SplashScreen { nav: stack }
    }

    // ── Splash / routing page (inline) ───────────────────────────────────
    // Shown for ≤ 1 s while UserProfile loads from disk, then replaced
    // by either WelcomeOnboarding (first launch) or Home (returning user).
    component SplashScreen: Item {
        property var nav: null

        Rectangle {
            anchors.fill: parent
            color: "transparent"
        }

        // Centered loading indicator
        Column {
            anchors.centerIn: parent
            spacing: 16

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "VEYA"
                color: "#4DD2FF"
                font.pixelSize: 48; font.bold: true
                font.letterSpacing: 10; font.family: "DejaVu Sans"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: UserProfile.loading ? "Loading…" : ""
                color: Qt.rgba(1,1,1,0.40)
                font.pixelSize: 14; font.family: "DejaVu Sans"
            }
        }

        // Route once UserProfile finishes loading
        Connections {
            target: UserProfile
            function onLoadingChanged() {
                if (UserProfile.loading) return
                Qt.callLater(function() {
                    if (UserProfile.profileExists) {
                        nav.replace(null, Qt.resolvedUrl("Home.qml"), { nav: nav })
                    } else {
                        nav.replace(null, Qt.resolvedUrl("onboarding/WelcomeOnboarding.qml"), { nav: nav })
                    }
                })
            }
        }

        // Safety net: if profile was already loaded synchronously before
        // Connections was ready, route immediately on component completion.
        Component.onCompleted: {
            if (!UserProfile.loading) {
                Qt.callLater(function() {
                    if (UserProfile.profileExists) {
                        nav.replace(null, Qt.resolvedUrl("Home.qml"), { nav: nav })
                    } else {
                        nav.replace(null, Qt.resolvedUrl("onboarding/WelcomeOnboarding.qml"), { nav: nav })
                    }
                })
            }
        }

        // Hard timeout: if UserProfile.loading is still true after 5 s,
        // force-route to onboarding so a future bug never hangs the boot.
        Timer {
            interval: 5000
            running: true
            repeat: false
            onTriggered: {
                if (UserProfile.loading) {
                    console.warn("[Main] UserProfile load timeout — forcing onboarding")
                    nav.replace(null, Qt.resolvedUrl("onboarding/WelcomeOnboarding.qml"), { nav: nav })
                }
            }
        }
    }
}
