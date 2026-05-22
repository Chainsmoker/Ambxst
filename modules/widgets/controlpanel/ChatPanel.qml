pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config

PanelWindow {
    id: chatPanel

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst:chatpanel"
    WlrLayershell.keyboardFocus: GlobalStates.chatPanelOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    readonly property bool isOpen: GlobalStates.chatPanelOpen

    visible: isOpen || (panel.scale > 0.001)

    // Reservar altura del bar y ancho del side notch
    readonly property int barReserved: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "top" ? base : 0;
    }
    readonly property int sideNotchOffset: 80   // ancho del side notch + margin
    readonly property int panelWidth: 380
    readonly property int panelHeight: 560

    mask: Region {
        item: chatPanel.visible ? fullMask : emptyMask
    }
    Item { id: fullMask; anchors.fill: parent }
    Item { id: emptyMask; width: 0; height: 0 }

    FocusGrab {
        windows: [chatPanel]
        active: chatPanel.isOpen
        onCleared: Qt.callLater(() => {
            if (chatPanel.isOpen) GlobalStates.chatPanelOpen = false;
        })
    }

    // Backdrop sutil
    Rectangle {
        anchors.fill: parent
        color: Colors.scrim
        opacity: chatPanel.isOpen ? 0.25 : 0
        visible: opacity > 0.001

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: GlobalStates.chatPanelOpen = false
        }
    }

    // ChatPanel — anclado a la izquierda, después del side notch.
    // Anima growing desde el centro vertical (donde sale el icono).
    StyledRect {
        id: panel
        variant: "bg"
        width: chatPanel.panelWidth
        height: chatPanel.panelHeight

        x: chatPanel.sideNotchOffset
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: chatPanel.barReserved / 2

        // Animación notch-style: scale + opacity desde un punto pequeño
        scale: chatPanel.isOpen ? 1.0 : 0.6
        opacity: chatPanel.isOpen ? 1.0 : 0.0

        transformOrigin: Item.Left   // sale "desde la izquierda" hacia la derecha

        radius: Styling.radius(20)

        layer.enabled: true
        layer.effect: Shadow {}

        clip: true

        Behavior on scale {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration * 1.2
                easing.type: chatPanel.isOpen ? Easing.OutBack : Easing.OutQuart
                easing.overshoot: chatPanel.isOpen ? 1.2 : 1.0
            }
        }

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        // Tragador de clicks
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
        }

        // =================================================================
        // UI: Header / Messages / Input
        // =================================================================
        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ===== HEADER =====
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: Colors.surfaceContainerLow

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 12
                    spacing: 12

                    // Avatar circular del bot
                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 18
                        color: Colors.primary

                        Text {
                            anchors.centerIn: parent
                            text: Icons.robot
                            font.family: Icons.font
                            font.pixelSize: 18
                            color: Styling.srItem("overprimary")
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Assistant"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(1)
                            font.bold: true
                            color: Colors.overBackground
                        }

                        Text {
                            text: "online"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.primary
                        }
                    }

                    // Botón cerrar
                    Item {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: closeMouse.containsMouse
                                   ? Qt.alpha(Colors.overBackground, 0.10)
                                   : "transparent"
                            Behavior on color {
                                enabled: Config.animDuration > 0
                                ColorAnimation { duration: Config.animDuration / 2 }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: 14
                            color: Colors.overBackground
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.chatPanelOpen = false
                        }
                    }
                }
            }

            // ===== MESSAGES =====
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: parent.width
                    spacing: 8

                    // Espaciado superior
                    Item { Layout.preferredHeight: 12 }

                    // Mensaje del bot (izquierda)
                    Row {
                        Layout.leftMargin: 12
                        Layout.maximumWidth: panel.width - 70

                        Rectangle {
                            width: Math.min(botMsg1.implicitWidth + 24, panel.width - 90)
                            height: botMsg1.implicitHeight + 16
                            radius: Styling.radius(14)
                            topLeftRadius: 4
                            color: Colors.surfaceContainer

                            Text {
                                id: botMsg1
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 14
                                anchors.rightMargin: 10
                                text: "Hola! Soy tu asistente. ¿En qué te puedo ayudar?"
                                wrapMode: Text.WordWrap
                                color: Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                            }
                        }
                    }

                    // Mensaje del user (derecha) — alineado a la derecha
                    Row {
                        Layout.alignment: Qt.AlignRight
                        Layout.rightMargin: 12

                        Rectangle {
                            width: Math.min(userMsg1.implicitWidth + 28, panel.width - 90)
                            height: userMsg1.implicitHeight + 16
                            radius: Styling.radius(14)
                            topRightRadius: 4
                            color: Colors.primary

                            Text {
                                id: userMsg1
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                text: "Estoy probando esta UI"
                                wrapMode: Text.WordWrap
                                color: Styling.srItem("overprimary")
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                            }
                        }
                    }

                    // Bot otra vez
                    Row {
                        Layout.leftMargin: 12

                        Rectangle {
                            width: Math.min(botMsg2.implicitWidth + 28, panel.width - 90)
                            height: botMsg2.implicitHeight + 16
                            radius: Styling.radius(14)
                            topLeftRadius: 4
                            color: Colors.surfaceContainer

                            Text {
                                id: botMsg2
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                text: "Listo, esto es solo un mock — todavía no hay backend."
                                wrapMode: Text.WordWrap
                                color: Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                            }
                        }
                    }

                    Item { Layout.preferredHeight: 12 }
                }
            }

            // ===== INPUT =====
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                color: Colors.surfaceContainerLow

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 8
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 8

                    // TextInput container
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Styling.radius(20)
                        color: Colors.surfaceContainerHigh

                        TextInput {
                            id: chatInput
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.overBackground
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            clip: true
                            selectByMouse: true

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "Escribí un mensaje..."
                                color: Colors.overSurfaceVariant
                                opacity: chatInput.text.length === 0 ? 0.6 : 0
                                font: chatInput.font
                            }
                        }
                    }

                    // Send button
                    Item {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44

                        Rectangle {
                            anchors.fill: parent
                            radius: 22
                            color: sendMouse.containsMouse
                                   ? Qt.lighter(Colors.primary, 1.1)
                                   : Colors.primary
                            Behavior on color {
                                enabled: Config.animDuration > 0
                                ColorAnimation { duration: Config.animDuration / 2 }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: Icons.arrowUp
                            font.family: Icons.font
                            font.pixelSize: 20
                            color: Styling.srItem("overprimary")
                        }

                        MouseArea {
                            id: sendMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                // TODO: enviar el mensaje
                                console.log("ChatPanel: send", chatInput.text);
                                chatInput.text = "";
                            }
                        }
                    }
                }
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: chatPanel.isOpen
        onActivated: GlobalStates.chatPanelOpen = false
    }
}
