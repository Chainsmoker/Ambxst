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
    visible: isOpen || panel.opacity > 0.001

    // Layout
    readonly property int barReserved: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "top" ? base : 0;
    }
    readonly property int sideNotchOffset: 76
    readonly property int panelWidth: 400

    // Tabs
    property string activeTab: "chat"
    readonly property var tabs: [
        { id: "chat",    label: "Chat",     icon: Icons.robot },
        { id: "history", label: "History",  icon: Icons.note },
        { id: "models",  label: "Modelos",  icon: Icons.sparkle },
        { id: "config",  label: "Config",   icon: Icons.gear }
    ]

    mask: Region { item: chatPanel.visible ? fullMask : emptyMask }
    Item { id: fullMask; anchors.fill: parent }
    Item { id: emptyMask; width: 0; height: 0 }

    FocusGrab {
        windows: [chatPanel]
        active: chatPanel.isOpen
        onCleared: Qt.callLater(() => {
            if (chatPanel.isOpen) GlobalStates.chatPanelOpen = false;
        })
    }

    // Backdrop muy sutil
    Rectangle {
        anchors.fill: parent
        color: Colors.scrim
        opacity: chatPanel.isOpen ? 0.30 : 0
        visible: opacity > 0.001

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: GlobalStates.chatPanelOpen = false
        }
    }

    // =================================================================
    // Panel principal — alto, anclado a la izquierda detrás del side notch
    // Animación notch-style desde un punto chico
    // =================================================================
    StyledRect {
        id: panel
        variant: "bg"
        width: chatPanel.panelWidth

        anchors {
            top: parent.top
            bottom: parent.bottom
            topMargin: chatPanel.barReserved + 12
            bottomMargin: 12
        }

        x: chatPanel.sideNotchOffset

        scale: chatPanel.isOpen ? 1.0 : 0.0
        opacity: chatPanel.isOpen ? 1.0 : 0.0
        transformOrigin: Item.Left

        radius: Styling.radius(20)

        layer.enabled: true
        layer.effect: Shadow {}
        clip: true

        Behavior on scale {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration * 1.2
                easing.type: chatPanel.isOpen ? Easing.OutBack : Easing.OutQuart
                easing.overshoot: chatPanel.isOpen ? 1.15 : 1.0
            }
        }
        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ============================================================
            // TAB BAR (top)
            // ============================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: Colors.surfaceContainerLow

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 4

                    Repeater {
                        model: chatPanel.tabs
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredHeight: 40

                            readonly property bool isActive: chatPanel.activeTab === modelData.id

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 6
                                radius: Styling.radius(12)
                                color: parent.isActive
                                       ? Colors.primary
                                       : (tabMouse.containsMouse
                                          ? Qt.alpha(Colors.primary, 0.15)
                                          : "transparent")
                                Behavior on color {
                                    enabled: Config.animDuration > 0
                                    ColorAnimation { duration: Config.animDuration / 2 }
                                }
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: parent.parent.modelData.icon
                                    font.family: Icons.font
                                    font.pixelSize: 16
                                    color: parent.parent.isActive
                                           ? Styling.srItem("overprimary")
                                           : Colors.overBackground
                                }

                                Text {
                                    text: parent.parent.modelData.label
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.bold: parent.parent.isActive
                                    color: parent.parent.isActive
                                           ? Styling.srItem("overprimary")
                                           : Colors.overBackground
                                    visible: chatPanel.panelWidth > 320
                                }
                            }

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: chatPanel.activeTab = parent.modelData.id
                            }
                        }
                    }
                }
            }

            // ============================================================
            // MODEL SELECTOR (under tabs, only for chat)
            // ============================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: chatPanel.activeTab === "chat" ? 44 : 0
                visible: chatPanel.activeTab === "chat"
                color: Colors.surfaceContainer
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8

                    Text {
                        text: Icons.sparkle
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: Colors.primary
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Claude 3.7 Sonnet"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.bold: true
                        color: Colors.overBackground
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "▼"
                        font.pixelSize: 10
                        color: Colors.overSurfaceVariant
                    }
                }
            }

            // ============================================================
            // CONTENIDO DEL TAB ACTIVO
            // ============================================================
            StackLayout {
                id: contentStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: {
                    switch (chatPanel.activeTab) {
                        case "chat":    return 0;
                        case "history": return 1;
                        case "models":  return 2;
                        case "config":  return 3;
                    }
                    return 0;
                }

                // -------- TAB CHAT --------
                ScrollView {
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    ColumnLayout {
                        width: parent.width
                        spacing: 10

                        Item { Layout.preferredHeight: 24 }

                        // Bienvenida grande tipo end-4
                        ColumnLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 16
                            spacing: 12

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                width: 72
                                height: 72
                                radius: 36
                                color: Colors.primaryContainer

                                Text {
                                    anchors.centerIn: parent
                                    text: Icons.robot
                                    font.family: Icons.font
                                    font.pixelSize: 36
                                    color: Colors.primary
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "Ambxst Assistant"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(2)
                                font.bold: true
                                color: Colors.overBackground
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.maximumWidth: panel.width - 60
                                text: "Configurá tu API key para empezar"
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: Colors.overSurfaceVariant
                            }
                        }

                        // Action chips
                        Flow {
                            Layout.fillWidth: true
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            Layout.topMargin: 16
                            spacing: 8

                            Repeater {
                                model: ["Saludá", "Resumí algo", "Explicame...", "Tradúceme"]
                                delegate: Rectangle {
                                    required property string modelData
                                    width: chipText.implicitWidth + 24
                                    height: 30
                                    radius: 15
                                    color: chipMouse.containsMouse
                                           ? Qt.alpha(Colors.primary, 0.18)
                                           : Colors.surfaceContainer
                                    Behavior on color {
                                        enabled: Config.animDuration > 0
                                        ColorAnimation { duration: Config.animDuration / 2 }
                                    }

                                    Text {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                        color: Colors.overBackground
                                    }

                                    MouseArea {
                                        id: chipMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }
                            }
                        }

                        Item { Layout.preferredHeight: 24 }

                        // Bubbles de ejemplo
                        Row {
                            Layout.leftMargin: 12
                            Layout.maximumWidth: panel.width - 40
                            Rectangle {
                                width: Math.min(botMsg.implicitWidth + 28, panel.width - 60)
                                height: botMsg.implicitHeight + 18
                                radius: Styling.radius(14)
                                topLeftRadius: 4
                                color: Colors.surfaceContainer

                                Text {
                                    id: botMsg
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    text: "Hola, ¿en qué puedo ayudarte?"
                                    wrapMode: Text.WordWrap
                                    color: Colors.overBackground
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                }
                            }
                        }

                        Row {
                            Layout.alignment: Qt.AlignRight
                            Layout.rightMargin: 12
                            Rectangle {
                                width: Math.min(userMsg.implicitWidth + 28, panel.width - 60)
                                height: userMsg.implicitHeight + 18
                                radius: Styling.radius(14)
                                topRightRadius: 4
                                color: Colors.primary

                                Text {
                                    id: userMsg
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    text: "Testing la UI"
                                    wrapMode: Text.WordWrap
                                    color: Styling.srItem("overprimary")
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // -------- TAB HISTORY --------
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Item { Layout.preferredHeight: 24 }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Sin conversaciones aún"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        color: Colors.overSurfaceVariant
                    }

                    Item { Layout.fillHeight: true }
                }

                // -------- TAB MODELS --------
                ColumnLayout {
                    spacing: 8

                    Item { Layout.preferredHeight: 16 }

                    Repeater {
                        model: ["Claude 3.7 Sonnet", "Claude 3.5 Haiku", "GPT-4o", "Llama 3.3 70B"]
                        delegate: Rectangle {
                            required property string modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            Layout.preferredHeight: 44
                            radius: Styling.radius(12)
                            color: index === 0
                                   ? Qt.alpha(Colors.primary, 0.15)
                                   : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 10

                                Text {
                                    text: Icons.sparkle
                                    font.family: Icons.font
                                    font.pixelSize: 14
                                    color: parent.parent.index === 0 ? Colors.primary : Colors.overSurfaceVariant
                                }

                                Text {
                                    text: parent.parent.modelData
                                    Layout.fillWidth: true
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.bold: parent.parent.index === 0
                                    color: Colors.overBackground
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // -------- TAB CONFIG --------
                ColumnLayout {
                    spacing: 8

                    Item { Layout.preferredHeight: 16 }

                    Text {
                        Layout.leftMargin: 20
                        text: "API Keys"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        font.bold: true
                        color: Colors.overBackground
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        Layout.preferredHeight: 44
                        radius: Styling.radius(12)
                        color: Colors.surfaceContainer

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            verticalAlignment: Text.AlignVCenter
                            text: "Anthropic: no configurada"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.overSurfaceVariant
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ============================================================
            // INPUT BAR (solo para chat)
            // ============================================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: chatPanel.activeTab === "chat" ? 64 : 0
                visible: chatPanel.activeTab === "chat"
                color: Colors.surfaceContainerLow
                clip: true

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    anchors.topMargin: 10
                    anchors.bottomMargin: 10
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Styling.radius(22)
                        color: Colors.surfaceContainerHigh

                        TextInput {
                            id: chatInput
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.overBackground
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            clip: true
                            selectByMouse: true

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "Escribí un mensaje..."
                                color: Colors.overSurfaceVariant
                                opacity: chatInput.text.length === 0 ? 0.55 : 0
                                font: chatInput.font
                            }
                        }
                    }

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
