pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config

PanelWindow {
    id: controlPanel

    required property ShellScreen modelData
    screen: modelData

    anchors {
        top: true
        bottom: true
        left: true
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ambxst:sidenotch"
    exclusionMode: ExclusionMode.Ignore

    // Reservar bar
    readonly property int barReserved: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "top" ? base : 0;
    }

    // Tamaños
    readonly property int pillWidth: 56
    readonly property int hoverRegionWidth: 4
    readonly property int sidePadding: 8

    // Hover state controla la reveal
    readonly property bool reveal: hoverArea.containsMouse

    implicitWidth: pillWidth + sidePadding + 32   // espacio + shadow

    mask: Region {
        item: hoverArea
    }

    // Hover hitbox: pequeña cuando está oculto, crece al revelarse
    MouseArea {
        id: hoverArea
        hoverEnabled: true
        anchors.top: parent.top
        anchors.topMargin: controlPanel.barReserved
        anchors.bottom: parent.bottom

        x: 0
        width: controlPanel.reveal ? (controlPanel.pillWidth + controlPanel.sidePadding + 16)
                                   : controlPanel.hoverRegionWidth

        Behavior on width {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration / 4
                easing.type: Easing.OutCubic
            }
        }

        // Container del pill
        StyledRect {
            id: pill
            variant: "bg"
            width: controlPanel.pillWidth
            height: iconColumn.implicitHeight + 16

            anchors.verticalCenter: parent.verticalCenter

            // Slide-in animado: cuando oculto x = -pillWidth, cuando reveal x = sidePadding
            x: controlPanel.reveal ? controlPanel.sidePadding : -width

            radius: Styling.radius(20)

            layer.enabled: true
            layer.effect: Shadow {}

            Behavior on x {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: controlPanel.reveal ? Easing.OutBack : Easing.OutQuart
                    easing.overshoot: controlPanel.reveal ? 1.15 : 1.0
                }
            }

            ColumnLayout {
                id: iconColumn
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                // Lista de iconos — por ahora visual
                Repeater {
                    model: [
                        { icon: Icons.robot,     label: "Chat" },
                        { icon: Icons.note,      label: "Audio" },
                        { icon: Icons.wifiHigh,  label: "Red" },
                        { icon: Icons.bluetooth, label: "Bluetooth" },
                        { icon: Icons.sun,       label: "Brillo" },
                        { icon: Icons.gear,      label: "Sistema" }
                    ]

                    delegate: Item {
                        required property var modelData
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40

                        Rectangle {
                            anchors.fill: parent
                            radius: Styling.radius(10)
                            color: iconMouse.containsMouse
                                   ? Qt.alpha(Colors.primary, 0.18)
                                   : "transparent"
                            Behavior on color {
                                enabled: Config.animDuration > 0
                                ColorAnimation { duration: Config.animDuration / 2 }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.icon
                            font.family: Icons.font
                            font.pixelSize: 20
                            color: Colors.overBackground
                        }

                        MouseArea {
                            id: iconMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // TODO: cada icono dispara su acción
                                console.log("SideNotch click:", parent.modelData.label);
                            }
                        }
                    }
                }
            }
        }
    }
}
