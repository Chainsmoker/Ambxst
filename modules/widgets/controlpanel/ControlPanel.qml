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
    id: controlPanel

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst:controlpanel"
    WlrLayershell.keyboardFocus: controlPanelOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var screenVisibilities: Visibilities.getForScreen(screen.name)
    readonly property bool controlPanelOpen: screenVisibilities ? screenVisibilities.controlpanel : false

    visible: controlPanelOpen
    exclusionMode: ExclusionMode.Ignore

    // Ancho del panel (slide-in)
    property int panelWidth: 380

    // Reservar el espacio del bar para no taparlo
    readonly property int barReserved: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "top" ? base : 0;
    }
    readonly property int barReservedBottom: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "bottom" ? base : 0;
    }

    mask: Region {
        item: controlPanelOpen ? fullMask : emptyMask
    }

    Item {
        id: fullMask
        anchors.fill: parent
    }

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    FocusGrab {
        id: focusGrab
        windows: [controlPanel]
        active: controlPanelOpen

        onCleared: {
            Qt.callLater(() => {
                if (controlPanelOpen) {
                    Visibilities.setActiveModule("");
                }
            });
        }
    }

    // Backdrop semi-transparente
    Rectangle {
        anchors.fill: parent
        color: Colors.scrim
        opacity: controlPanelOpen ? 0.4 : 0

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Visibilities.setActiveModule("")
        }
    }

    // Panel deslizable desde la izquierda — pegado al borde, debajo del bar
    StyledRect {
        id: panel
        variant: "bg"
        width: controlPanel.panelWidth
        anchors {
            top: parent.top
            bottom: parent.bottom
            topMargin: controlPanel.barReserved
            bottomMargin: controlPanel.barReservedBottom
        }

        // Slide: cuando está cerrado, x = -width; abierto, x = 0 (pegado al borde)
        x: controlPanelOpen ? 0 : -width

        // Solo redondeado en el lado derecho (estilo notch sticky)
        topLeftRadius: 0
        bottomLeftRadius: 0
        topRightRadius: Styling.radius(20)
        bottomRightRadius: Styling.radius(20)

        layer.enabled: true
        layer.effect: Shadow {}

        // Animación notch-style: snappy con overshoot suave
        Behavior on x {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration * 1.2
                easing.type: Easing.OutBack
                easing.overshoot: 0.6
            }
        }

        // Atrapar clicks dentro del panel (no cerrarlo)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: {}  // swallow
        }

        // Contenido placeholder — acá iteramos
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            Text {
                text: "Control Panel"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(3)
                font.bold: true
                color: Colors.overBackground
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Placeholder — acá van los controles"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(0)
                color: Colors.overSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 8
            }

            // Spacer + footer botón cerrar
            Item { Layout.fillHeight: true }

            Text {
                text: "Click fuera del panel o ESC para cerrar"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overSurfaceVariant
                opacity: 0.6
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    // ESC para cerrar
    Shortcut {
        sequence: "Escape"
        enabled: controlPanelOpen
        onActivated: Visibilities.setActiveModule("")
    }
}
