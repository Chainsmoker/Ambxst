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
    readonly property int dockWidth: 380
    readonly property int hPadding: 12
    readonly property int vPadding: 0          // header come hasta el borde
    readonly property int headerHeight: 150
    readonly property int sectionSpacing: 10

    // Altura del bar superior (para overlap visual con la barra)
    readonly property int barHeight: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "top" ? base : 0;
    }
    // Margen externo del bar (gap del bar al borde de pantalla)
    readonly property int barOuterMargin: 4
    readonly property int notchCurveSize: Math.max(Styling.radius(8), 12)
    // El dock arranca desde arriba — el bar (layer Overlay) flota encima
    readonly property int barReserved: 0

    implicitWidth: dockWidth + 32

    mask: Region {
        item: panelMask
    }

    Item {
        id: panelMask
        // Incluir el curve-notch a la izquierda del dock
        x: dock.width - dock.dockWidth - dock.notchCurveSize
        y: 0
        width: dock.isOpen ? (dock.dockWidth + dock.notchCurveSize) : 0
        height: dock.isOpen ? dock.height : 0
        visible: false
    }

    Item {
        id: dockContainer
        width: dock.dockWidth
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: dock.barReserved
        anchors.bottom: parent.bottom
        opacity: dock.isOpen ? 1 : 0
        visible: opacity > 0.001

        transform: Translate {
            id: slideTransform
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

        // Fondo único: arranca desde y=0 para fundirse con el bar superior.
        // Usa "barbg" para matchear EXACTAMENTE el color del bar (surfaceDim vs background).
        StyledRect {
            id: dockBg
            anchors.fill: parent
            variant: "barbg"
            enableShadow: true
            radius: 0
            topLeftRadius: 0
            bottomLeftRadius: Styling.radius(8)
            topRightRadius: 0
            bottomRightRadius: 0
            clip: true
        }

        // ── Curva tipo dashboard donde el bar se conecta al dock ──
        // A la izquierda del dock, justo bajo el bar: extiende el fondo del dock
        // hacia la izquierda con un arco cóncavo, simulando un notch que sale del bar.
        Item {
            id: notchCurveLeft
            width: dock.notchCurveSize
            height: dock.notchCurveSize
            x: -dock.notchCurveSize
            y: dock.barHeight - dock.barOuterMargin
            visible: dock.barHeight > 0

            Canvas {
                id: notchCanvas
                anchors.fill: parent
                antialiasing: true

                function paintCorner() { requestPaint(); }
                Component.onCompleted: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    var w = width;
                    ctx.clearRect(0, 0, w, height);
                    // L sólida en bottom-right; arco cóncavo desde top-right → bottom-left
                    // centrado en (0,0): "muerde" el cuadrante top-left
                    ctx.beginPath();
                    ctx.moveTo(w, w);
                    ctx.lineTo(w, 0);
                    ctx.arc(0, 0, w, 0, Math.PI / 2, false);
                    ctx.closePath();
                    ctx.fillStyle = Colors.surfaceDim;
                    ctx.fill();
                }
            }
            Connections {
                target: Colors
                function onSurfaceDimChanged() { notchCanvas.requestPaint(); }
            }
        }

        ScrollView {
            id: scroller
            anchors.fill: parent
            anchors.topMargin: dock.barHeight
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: scroller.width
                spacing: dock.sectionSpacing

                // ── HEADER (full-bleed) ─────────────────────────
                DistroHeader {
                    Layout.fillWidth: true
                    Layout.preferredHeight: dock.headerHeight
                    Layout.topMargin: 0
                }

                // ── CALENDAR (full month) ──────────────────────
                StyledRect {
                    id: calendarPane
                    Layout.fillWidth: true
                    Layout.leftMargin: dock.hPadding
                    Layout.rightMargin: dock.hPadding
                    variant: "pane"
                    radius: Styling.radius(6)
                    enableShadow: false
                    Layout.preferredHeight: calendarColumn.implicitHeight + 24

                    property date currentDate: new Date()
                    property date viewDate: new Date()

                    Timer {
                        interval: 60000
                        running: dock.isOpen
                        repeat: true
                        onTriggered: calendarPane.currentDate = new Date()
                    }

                    function isSameDay(a, b) {
                        return a.getFullYear() === b.getFullYear()
                            && a.getMonth() === b.getMonth()
                            && a.getDate() === b.getDate();
                    }

                    Column {
                        id: calendarColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.topMargin: 12
                        spacing: 8

                        // Month header con nav
                        Item {
                            width: parent.width
                            height: 28

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: {
                                        var m = calendarPane.viewDate.toLocaleDateString(Qt.locale(), "MMMM yyyy");
                                        return m.charAt(0).toUpperCase() + m.slice(1);
                                    }
                                    color: Colors.overBackground
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(1)
                                    font.weight: Font.Medium
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Repeater {
                                    model: [
                                        { ico: "", delta: -1 },
                                        { ico: "", delta:  0 },
                                        { ico: "", delta:  1 }
                                    ]
                                    Item {
                                        id: navBtn
                                        required property var modelData
                                        width: 26
                                        height: 26
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 13
                                            color: navMa.containsMouse ? Styling.srItem("focus") : "transparent"
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: navBtn.modelData.ico
                                            font.family: "MaterialSymbolsRounded"
                                            font.pixelSize: 16
                                            color: Colors.overBackground
                                        }
                                        MouseArea {
                                            id: navMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (navBtn.modelData.delta === 0) {
                                                    calendarPane.viewDate = new Date();
                                                } else {
                                                    var d = new Date(calendarPane.viewDate);
                                                    d.setMonth(d.getMonth() + navBtn.modelData.delta);
                                                    calendarPane.viewDate = d;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Día headers
                        Row {
                            id: weekHeaderRow
                            spacing: 2
                            property real cellW: (calendarColumn.width - 6 * spacing) / 7

                            Repeater {
                                model: ["L", "M", "M", "J", "V", "S", "D"]
                                Item {
                                    required property var modelData
                                    required property int index
                                    width: weekHeaderRow.cellW
                                    height: 18
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        color: Colors.outline
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }

                        // Grid del mes (42 celdas)
                        Grid {
                            id: monthGrid
                            columns: 7
                            spacing: 2
                            property real cellW: (calendarColumn.width - 6 * spacing) / 7

                            property var monthCells: {
                                var view = calendarPane.viewDate;
                                var first = new Date(view.getFullYear(), view.getMonth(), 1);
                                var startWeekday = (first.getDay() + 6) % 7;  // Mon = 0
                                var start = new Date(first);
                                start.setDate(first.getDate() - startWeekday);
                                var cells = [];
                                for (var i = 0; i < 42; i++) {
                                    var d = new Date(start);
                                    d.setDate(start.getDate() + i);
                                    cells.push({
                                        date: d,
                                        day: d.getDate(),
                                        inMonth: d.getMonth() === view.getMonth(),
                                        isToday: calendarPane.isSameDay(d, calendarPane.currentDate)
                                    });
                                }
                                return cells;
                            }

                            Repeater {
                                model: monthGrid.monthCells

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
                                               : (cellHover.containsMouse ? Styling.srItem("focus") : "transparent")
                                        Behavior on color { ColorAnimation { duration: 100 } }
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

                                    MouseArea {
                                        id: cellHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                }
                            }
                        }
                    }
                }

                // ── WEATHER ─────────────────────────────────────
                StyledRect {
                    Layout.fillWidth: true
                    Layout.leftMargin: dock.hPadding
                    Layout.rightMargin: dock.hPadding
                    variant: "pane"
                    radius: Styling.radius(6)
                    enableShadow: false
                    visible: WeatherService.dataAvailable
                    Layout.preferredHeight: visible ? (weatherCol.implicitHeight + 12) : 0

                    Column {
                        id: weatherCol
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 6
                        spacing: 4

                        WeatherWidget {
                            width: parent.width
                            height: 130
                            showDebugControls: false
                            animationsEnabled: dock.isOpen
                        }
                    }
                }

                // ── POMODORO / START WORK ───────────────────────
                StyledRect {
                    Layout.fillWidth: true
                    Layout.leftMargin: dock.hPadding
                    Layout.rightMargin: dock.hPadding
                    variant: "pane"
                    radius: Styling.radius(6)
                    enableShadow: false
                    Layout.preferredHeight: pomo.implicitHeight + 12

                    Pomodoro {
                        id: pomo
                        anchors.centerIn: parent
                        width: parent.width - 12
                    }
                }

                // ── COLOR PICKER ────────────────────────────────
                StyledRect {
                    Layout.fillWidth: true
                    Layout.leftMargin: dock.hPadding
                    Layout.rightMargin: dock.hPadding
                    variant: "pane"
                    radius: Styling.radius(6)
                    enableShadow: false
                    Layout.preferredHeight: pickerCol.implicitHeight + 20

                    Column {
                        id: pickerCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 10
                        spacing: 6

                        Text {
                            text: "Color picker"
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                        }

                        ColorPicker {
                            width: parent.width
                        }
                    }
                }

                Item {
                    Layout.preferredHeight: 12
                    Layout.fillWidth: true
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
