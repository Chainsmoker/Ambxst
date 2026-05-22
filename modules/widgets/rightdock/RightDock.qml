pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.config
import "../../bar/clock"
import "../dashboard/widgets"

PanelWindow {
    id: dock

    anchors {
        top: true
        bottom: true
        right: true
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ambxst:rightdock"
    exclusionMode: ExclusionMode.Ignore

    readonly property bool isOpen: GlobalStates.rightDockOpen
    // CRÍTICO: PanelWindow se oculta cuando cerrado para no interceptar clicks.
    visible: isOpen || dockContainer.opacity > 0.001

    // ── Geometría ─────────────────────────────────────────────────
    readonly property int dockWidth: 360
    readonly property int tabStripWidth: 56
    readonly property int topStripWidth: 240
    readonly property int shoulderR: 22
    readonly property int bottomLeftR: Styling.radius(8)

    readonly property int hPadding: 10
    readonly property int headerHeight: 130
    readonly property int sectionSpacing: 8

    readonly property int barHeight: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "top" ? base : 0;
    }

    // Tab activa (0=calendar, 1=weather, 2=pomodoro, 3=picker)
    property int activeTab: 0

    implicitWidth: dockWidth + 32

    mask: Region { item: dock.visible ? fullMask : emptyMask }
    Item {
        id: fullMask
        x: dock.width - dock.dockWidth
        y: 0
        width: dock.dockWidth
        height: dock.height
    }
    Item { id: emptyMask; width: 0; height: 0 }

    Item {
        id: dockContainer
        width: dock.dockWidth
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        opacity: dock.isOpen ? 1 : 0
        visible: opacity > 0.001

        readonly property int shoulderInset: dock.dockWidth - dock.topStripWidth

        transform: Translate {
            x: dock.isOpen ? 0 : dock.dockWidth
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

        // ── FONDO ── tres piezas que arman la L:
        // 1) Tira angosta arriba (a la derecha)
        // 2) Parte ancha abajo (full width + bottom-left rounded)
        // 3) Pieza curva en el hombro (fillet)

        // 1) Tira angosta — desde y=0 hasta y=barHeight, sólo a la derecha
        Rectangle {
            id: topStripBg
            x: dockContainer.shoulderInset
            y: 0
            width: dock.topStripWidth
            height: dock.barHeight
            color: Colors.surfaceDim
        }

        // 2) Parte ancha — desde y=barHeight hasta abajo, ancho completo
        Rectangle {
            id: bottomBg
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.top: parent.top
            anchors.topMargin: dock.barHeight
            color: Colors.surfaceDim
            bottomLeftRadius: dock.bottomLeftR
            topLeftRadius: 0
            topRightRadius: 0
            bottomRightRadius: 0
        }

        // 3) Hombro fillet — Canvas que rellena la curva en la esquina interna
        Canvas {
            id: shoulderFiller
            x: dockContainer.shoulderInset - dock.shoulderR
            y: dock.barHeight
            width: dock.shoulderR
            height: dock.shoulderR
            antialiasing: true

            Component.onCompleted: requestPaint()
            Connections {
                target: Colors
                function onSurfaceDimChanged() { shoulderFiller.requestPaint(); }
            }

            onPaint: {
                var ctx = getContext("2d");
                var r = width;
                ctx.clearRect(0, 0, width, height);
                // Rellenamos la esquina BOTTOM-RIGHT del cuadrante con un arco
                // que excluye el cuarto-de-disco TOP-LEFT (creando un fillet cóncavo
                // visto desde afuera, suavizando la inside corner de la L).
                // Path:
                //   start (r, 0)        top-right
                //   arc ↻ to (0, r)     curve bulges hacia (r, r) [inside dock]
                //   line to (r, r)      bottom-right (cierra via right edge)
                ctx.beginPath();
                ctx.moveTo(r, 0);
                // Arc centered at (r, r) with radius r, from angle 3π/2 (up) to π (left),
                // anticlockwise → traza el cuarto curvado por el lado del exterior.
                ctx.arc(r, r, r, 3 * Math.PI / 2, Math.PI, true);
                ctx.lineTo(r, r);
                ctx.closePath();
                ctx.fillStyle = Colors.surfaceDim;
                ctx.fill();
            }
        }

        // ── TAB STRIP ── columna vertical de iconos a la izquierda ───
        Column {
            id: tabStrip
            x: 0
            y: dock.barHeight + dock.shoulderR + 8
            width: dock.tabStripWidth
            spacing: 4

            Repeater {
                model: [
                    { ico: "", name: "Calendario" },   // calendar_today
                    { ico: "", name: "Clima" },        // cloud
                    { ico: "", name: "Trabajo" },      // timer
                    { ico: "", name: "Colores" }       // palette
                ]

                Item {
                    id: tabItem
                    required property var modelData
                    required property int index
                    width: dock.tabStripWidth
                    height: 48

                    readonly property bool active: dock.activeTab === tabItem.index

                    Rectangle {
                        id: tabPill
                        anchors.centerIn: parent
                        width: tabItem.active ? 44 : 40
                        height: 40
                        radius: 14
                        color: tabItem.active
                               ? Styling.srItem("primary")
                               : (tabMa.containsMouse ? Styling.srItem("focus") : "transparent")

                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: tabItem.modelData.ico
                        font.family: "MaterialSymbolsRounded"
                        font.pixelSize: 22
                        color: tabItem.active ? Colors.background : Colors.overBackground
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }

                    MouseArea {
                        id: tabMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dock.activeTab = tabItem.index
                    }

                    StyledToolTip {
                        visible: tabMa.containsMouse
                        tooltipText: tabItem.modelData.name
                    }
                }
            }
        }

        // ── ÁREA DE CONTENIDO ── header + tab activa ───────────────
        Item {
            id: contentArea
            x: dock.tabStripWidth
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: dock.barHeight + dock.shoulderR
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12

            // Header en la parte de arriba del área de contenido
            DistroHeader {
                id: header
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: dock.headerHeight
            }

            // StackLayout con la tab activa
            StackLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: header.bottom
                anchors.topMargin: dock.sectionSpacing
                anchors.bottom: parent.bottom
                currentIndex: dock.activeTab

                // Tab 0: Calendar
                StyledRect {
                    id: calendarPane
                    variant: "pane"
                    radius: Styling.radius(6)
                    enableShadow: false
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    property date currentDate: new Date()
                    property date viewDate: new Date()

                    Timer {
                        interval: 60000
                        running: dock.isOpen && dock.activeTab === 0
                        repeat: true
                        onTriggered: calendarPane.currentDate = new Date()
                    }

                    Column {
                        id: calendarCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        Item {
                            width: parent.width
                            height: 24
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    var m = calendarPane.viewDate.toLocaleDateString(Qt.locale(), "MMMM yyyy");
                                    return m.charAt(0).toUpperCase() + m.slice(1);
                                }
                                color: Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                                font.weight: Font.Medium
                            }
                        }

                        Row {
                            id: weekRow
                            spacing: 2
                            property real cellW: (calendarCol.width - 6 * spacing) / 7
                            Repeater {
                                model: ["L", "M", "M", "J", "V", "S", "D"]
                                Item {
                                    required property var modelData
                                    width: weekRow.cellW
                                    height: 16
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        color: Colors.outline
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                    }
                                }
                            }
                        }

                        Grid {
                            id: monthGrid
                            columns: 7
                            spacing: 2
                            property real cellW: (calendarCol.width - 6 * spacing) / 7

                            property var cells: {
                                var view = calendarPane.viewDate;
                                var first = new Date(view.getFullYear(), view.getMonth(), 1);
                                var startWeekday = (first.getDay() + 6) % 7;
                                var start = new Date(first);
                                start.setDate(first.getDate() - startWeekday);
                                var arr = [];
                                for (var i = 0; i < 42; i++) {
                                    var d = new Date(start);
                                    d.setDate(start.getDate() + i);
                                    arr.push({
                                        day: d.getDate(),
                                        inMonth: d.getMonth() === view.getMonth(),
                                        isToday: d.getFullYear() === calendarPane.currentDate.getFullYear()
                                            && d.getMonth() === calendarPane.currentDate.getMonth()
                                            && d.getDate() === calendarPane.currentDate.getDate()
                                    });
                                }
                                return arr;
                            }

                            Repeater {
                                model: monthGrid.cells
                                Item {
                                    required property var modelData
                                    width: monthGrid.cellW
                                    height: monthGrid.cellW
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        radius: width / 2
                                        color: parent.modelData.isToday
                                               ? Styling.srItem("overprimary")
                                               : "transparent"
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData.day
                                        color: parent.modelData.isToday
                                               ? Colors.background
                                               : (parent.modelData.inMonth ? Colors.overBackground : Colors.outline)
                                        opacity: parent.modelData.inMonth ? 1 : 0.45
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(0)
                                        font.weight: parent.modelData.isToday ? Font.Bold : Font.Normal
                                    }
                                }
                            }
                        }
                    }
                }

                // Tab 1: Weather
                StyledRect {
                    variant: "pane"
                    radius: Styling.radius(6)
                    enableShadow: false
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Item {
                        anchors.fill: parent
                        anchors.margins: 8

                        WeatherWidget {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 140
                            showDebugControls: false
                            animationsEnabled: dock.isOpen && dock.activeTab === 1
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !WeatherService.dataAvailable
                            text: "Cargando clima..."
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                        }
                    }
                }

                // Tab 2: Pomodoro / Trabajo
                StyledRect {
                    variant: "pane"
                    radius: Styling.radius(6)
                    enableShadow: false
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Item {
                        anchors.fill: parent
                        anchors.margins: 8

                        Pomodoro {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                        }
                    }
                }

                // Tab 3: Color picker
                StyledRect {
                    variant: "pane"
                    radius: Styling.radius(6)
                    enableShadow: false
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        ColorPicker {
                            width: parent.width
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onRightDockOpenChanged() {
            if (GlobalStates.rightDockOpen && !WeatherService.dataAvailable) {
                WeatherService.updateWeather();
            }
        }
    }
}
