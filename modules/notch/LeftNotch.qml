pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config

Item {
    id: root

    required property ShellScreen screen
    property bool unifiedEffectActive: false
    readonly property Item hitbox: hoverArea

    readonly property bool activeWindowFullscreen: ToplevelManager.activeToplevel ? (ToplevelManager.activeToplevel.activated && ToplevelManager.activeToplevel.fullscreen === true) : false

    // Disable the hover trigger in fullscreen unless the bar is configured to show in fullscreen
    readonly property bool enabled: !activeWindowFullscreen || (Config.bar && Config.bar.availableOnFullscreen === true)

    // Hover state controls the slide-out reveal
    readonly property bool reveal: enabled && (hoverArea.containsMouse || GlobalStates.newsPanelOpen)

    // The dimensions of the visual pill
    readonly property int pillSize: 48

    MouseArea {
        id: hoverArea
        hoverEnabled: true
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        x: 0
        width: root.reveal ? (root.pillSize + 16) : 10

        Behavior on width {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration / 2
                easing.type: Easing.OutCubic
            }
        }

        // Visual pill
        StyledRect {
            id: pill
            variant: "bg"
            width: root.pillSize
            height: root.pillSize
            anchors.verticalCenter: parent.verticalCenter
            
            // Slide in animation: x is -width (hidden offscreen) when closed, 8px padding when revealed
            x: root.reveal ? 8 : -width

            Behavior on x {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: root.reveal ? Easing.OutBack : Easing.OutQuart
                    easing.overshoot: root.reveal ? 1.15 : 1.0
                }
            }

            radius: width / 2 // fully rounded circle
            enableBorder: !root.unifiedEffectActive

            layer.enabled: true
            layer.effect: Shadow {}

            // Toggle button
            MouseArea {
                id: clickArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onClicked: {
                    GlobalStates.newsPanelOpen = !GlobalStates.newsPanelOpen;
                }

                Text {
                    text: Icons.globe
                    font.family: Icons.font
                    font.pixelSize: 18
                    anchors.centerIn: parent
                    color: GlobalStates.newsPanelOpen ? Colors.primary : (clickArea.containsMouse ? Colors.primary : Colors.text)
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }
            }
        }
    }
}
