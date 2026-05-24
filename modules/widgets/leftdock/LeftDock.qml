pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.modules.corners
import qs.config

PanelWindow {
    id: dock

    anchors {
        top: true
        bottom: true
        left: true
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ambxst:leftdock"
    exclusionMode: ExclusionMode.Ignore

    readonly property bool isOpen: GlobalStates.newsPanelOpen
    // Ocultar PanelWindow cuando cerrado para no bloquear clicks del sistema.
    visible: isOpen || dockContainer.opacity > 0.001

    readonly property int dockWidth: 420
    readonly property int hPadding: 16
    readonly property int sectionSpacing: 12
    readonly property int headerHeight: 110

    // Tab activa: 0=Tech News, 1=CVEs
    property int currentTab: 0

    // Accent dinámico por tab — define el color del border + active pill
    readonly property color tabAccent: {
        switch (currentTab) {
            case 0: return Colors.primary;        // tech news: matugen primary
            case 1: return "#E07556";             // CVEs: Alert orange/tomato
        }
        return Colors.primary;
    }

    readonly property int barReserved: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "top" ? base : 0;
    }

    implicitWidth: dockWidth + 32

    // Patrón ChatPanel: cerrado → emptyMask (no intercepta), abierto → fullMask.
    mask: Region { item: dock.visible ? fullMask : emptyMask }
    Item {
        id: fullMask
        x: 0
        y: dock.barReserved
        width: dock.dockWidth
        height: dock.height - dock.barReserved
    }
    Item { id: emptyMask; width: 0; height: 0 }

    readonly property int dockContainerWidth: dock.dockWidth

    // Mock Data para Noticias Tech
    readonly property var techNews: [
        {
            title: "Gemini 2.0 Ultra de Google revoluciona la codificación de agentes autónomos",
            source: "Hacker News · Hace 2h",
            tag: "AI",
            tagColor: "#5dadeb",
            excerpt: "La nueva arquitectura de agentes autónomos logra resolver tareas complejas de desarrollo de software con razonamiento secuencial de nivel experto."
        },
        {
            title: "Kernel Linux 6.15 introduce optimizaciones de scheduler para CPUs AMD Zen 5",
            source: "Phoronix · Hace 4h",
            tag: "Kernel",
            tagColor: "#E07556",
            excerpt: "Las mejoras reducen la latencia de hilos y aumentan el rendimiento de compilación hasta en un 12% en procesadores de última generación."
        },
        {
            title: "Hyprland lanza v0.48 con soporte experimental de sincronización por hardware",
            source: "GitHub Changelog · Hace 1d",
            tag: "Wayland",
            tagColor: "#9fd0ec",
            excerpt: "La nueva entrega reduce significativamente el consumo de GPU al sincronizar directamente los búferes de renderizado de la pantalla."
        },
        {
            title: "Rust consolida su adopción en componentes de seguridad crítica del sistema operativo",
            source: "Tech Crunch · Hace 1d",
            tag: "Security",
            tagColor: "#7a4a8a",
            excerpt: "Varias distros principales de Linux anuncian planes para migrar submódulos críticos a librerías escritas nativamente en Rust."
        }
    ]

    // Mock Data para CVEs
    readonly property var cveFeed: [
        {
            cve: "CVE-2026-12345",
            severity: "CRITICAL",
            score: "9.8",
            color: "#E07556",
            description: "Vulnerabilidad de ejecución remota de código (RCE) en el subsistema XFRM del kernel Linux. Permite a atacantes no autenticados saltarse las protecciones de IPsec."
        },
        {
            cve: "CVE-2026-98765",
            severity: "HIGH",
            score: "8.2",
            color: "#ff8a4a",
            description: "Desbordamiento de búfer en el daemon de OpenSSH al procesar paquetes de autenticación personalizados a través de módulos PAM específicos."
        },
        {
            cve: "CVE-2026-45678",
            severity: "MEDIUM",
            score: "6.5",
            color: "#ffe57a",
            description: "Denegación de servicio (DoS) en el compositor Hyprland. Paquetes maliciosos de IPC pueden inducir un ciclo infinito en el despachador de eventos."
        },
        {
            cve: "CVE-2026-11111",
            severity: "LOW",
            score: "3.1",
            color: "#7f8fa6",
            description: "Divulgación de información de permisos insuficientes en el socket de comunicación UNIX local de axctl. Usuarios locales pueden leer metadatos básicos."
        }
    ]

    Item {
        id: dockContainer
        width: dock.dockContainerWidth
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: dock.barReserved
        anchors.bottom: parent.bottom
        opacity: dock.isOpen ? 1 : 0
        visible: opacity > 0.001

        transform: Translate {
            id: slideTransform
            x: dock.isOpen ? 0 : -dock.dockContainerWidth
            Behavior on x {
                NumberAnimation {
                    duration: Config.animDuration > 0 ? Config.animDuration : 220
                    easing.type: dock.isOpen ? Easing.OutCubic : Easing.InCubic
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Config.animDuration > 0 ? Config.animDuration : 220
                easing.type: Easing.OutCubic
            }
        }

        // Dock body — bg matugen sólido, sin border.
        StyledRect {
            id: dockBg
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: dock.dockWidth
            variant: "bg"
            enableShadow: true
            radius: 0
            topLeftRadius: 0
            bottomLeftRadius: 0
            topRightRadius: Styling.radius(16)
            bottomRightRadius: Styling.radius(16)
            clip: true
        }

        // Header fijo
        Item {
            id: dockHeader
            anchors.top: dockBg.top
            anchors.left: dockBg.left
            anchors.right: dockBg.right
            height: dock.headerHeight
            clip: true
            z: 5

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: dock.hPadding
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Feed de Noticias"
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(2)
                        font.weight: Font.Bold
                    }

                    Item { Layout.fillWidth: true }

                    // Botón cerrar (X)
                    Item {
                        width: 32
                        height: 32
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.15) : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: Icons.cancel
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: Colors.outline
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.newsPanelOpen = false
                        }
                    }
                }

                Text {
                    text: "Mantente al día con lo último en tecnología y seguridad"
                    color: Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    Layout.fillWidth: true
                }
            }
        }

        // Floating tab pills (debajo del header)
        Row {
            id: tabPills
            z: 100
            anchors.top: dockHeader.bottom
            anchors.horizontalCenter: dockBg.horizontalCenter
            anchors.topMargin: 4
            spacing: 12

            Repeater {
                model: [
                    { ico: Icons.globe, name: "Tech News" },
                    { ico: Icons.shield, name: "Últimos CVEs" }
                ]

                Rectangle {
                    id: pill
                    required property var modelData
                    required property int index
                    readonly property bool isActive: dock.currentTab === index

                    width: 170
                    height: 40
                    radius: 12
                    color: isActive
                        ? dock.tabAccent
                        : (pillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.42))
                    border.color: isActive ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.15)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 220 } }
                    Behavior on border.color { ColorAnimation { duration: 220 } }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: pill.modelData.ico
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: "white"
                        }

                        Text {
                            text: pill.modelData.name
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.Medium
                            color: "white"
                        }
                    }

                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dock.currentTab = pill.index
                    }
                }
            }
        }

        ScrollView {
            id: scroller
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: tabPills.bottom
            anchors.topMargin: 16
            anchors.bottom: parent.bottom
            width: dock.dockWidth
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: scroller.width - 24
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: dock.sectionSpacing

                StackLayout {
                    id: contentStack
                    Layout.fillWidth: true
                    currentIndex: dock.currentTab

                    // TAB 0: Noticias Tech
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Repeater {
                            model: dock.techNews

                            delegate: StyledRect {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: contentCol.implicitHeight + 24
                                variant: "internalbg"
                                radius: 14
                                enableShadow: false

                                ColumnLayout {
                                    id: contentCol
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Rectangle {
                                            width: tagText.implicitWidth + 12
                                            height: 22
                                            radius: 6
                                            color: modelData.tagColor

                                            Text {
                                                id: tagText
                                                anchors.centerIn: parent
                                                text: modelData.tag
                                                color: "white"
                                                font.family: Config.theme.font
                                                font.pixelSize: Styling.fontSize(-2)
                                                font.weight: Font.Bold
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: modelData.source
                                            color: Colors.outline
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-2)
                                        }
                                    }

                                    Text {
                                        text: modelData.title
                                        color: Colors.overBackground
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(0)
                                        font.weight: Font.Bold
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                    }

                                    Text {
                                        text: modelData.excerpt
                                        color: Colors.outline
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        opacity: 0.85
                                    }
                                }
                            }
                        }
                    }

                    // TAB 1: CVE Feed
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Repeater {
                            model: dock.cveFeed

                            delegate: StyledRect {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: cveCol.implicitHeight + 24
                                variant: "internalbg"
                                radius: 14
                                enableShadow: false

                                ColumnLayout {
                                    id: cveCol
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            text: modelData.cve
                                            color: Colors.overBackground
                                            font.family: Config.theme.monoFont
                                            font.pixelSize: Styling.fontSize(0)
                                            font.weight: Font.Bold
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Badge de severidad
                                        Rectangle {
                                            width: sevText.implicitWidth + 14
                                            height: 22
                                            radius: 6
                                            color: modelData.color

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: 4
                                                Text {
                                                    id: sevText
                                                    text: modelData.severity + " (" + modelData.score + ")"
                                                    color: "white"
                                                    font.family: Config.theme.font
                                                    font.pixelSize: Styling.fontSize(-2)
                                                    font.weight: Font.Bold
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        text: modelData.description
                                        color: Colors.outline
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        opacity: 0.9
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
