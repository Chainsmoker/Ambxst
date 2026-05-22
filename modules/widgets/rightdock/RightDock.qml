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
    readonly property int dockWidth: 360
    readonly property int hPadding: 14
    readonly property int vPadding: 16

    // Reservar espacio para el bar superior
    readonly property int barReserved: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "top" ? base : 0;
    }

    implicitWidth: dockWidth + 32

    mask: Region {
        item: panelMask
    }

    Item {
        id: panelMask
        x: dock.width - dock.dockWidth
        y: dock.barReserved
        width: dock.isOpen ? dock.dockWidth : 0
        height: dock.isOpen ? (dock.height - dock.barReserved) : 0
        visible: false
    }

    // Contenedor animado
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

        // Fondo único que engloba todo
        StyledRect {
            id: dockBg
            anchors.fill: parent
            variant: "bg"
            enableShadow: true
            radius: 0
            topLeftRadius: Styling.radius(8)
            bottomLeftRadius: Styling.radius(8)
            topRightRadius: 0
            bottomRightRadius: 0
        }

        ScrollView {
            id: scroller
            anchors.fill: parent
            anchors.leftMargin: dock.hPadding
            anchors.rightMargin: dock.hPadding
            anchors.topMargin: dock.vPadding
            anchors.bottomMargin: dock.vPadding
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: scroller.width
                spacing: 14

                // ── HEADER ──────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: Qt.formatDateTime(headerClock.now, "dddd, d MMM")
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(2)
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }

                    Item {
                        id: headerClock
                        property var now: new Date()
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28

                        Timer {
                            interval: 60000
                            running: dock.isOpen
                            repeat: true
                            onTriggered: headerClock.now = new Date()
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            color: closeHover.containsMouse ? Styling.srItem("focus") : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: ""
                            font.family: "MaterialSymbolsRounded"
                            font.pixelSize: 18
                            color: Colors.overBackground
                        }
                        MouseArea {
                            id: closeHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: GlobalStates.rightDockOpen = false
                        }
                    }
                }

                // ── CALENDAR ────────────────────────────────────
                StyledRect {
                    id: calendarPane
                    Layout.fillWidth: true
                    variant: "pane"
                    radius: Styling.radius(6)
                    enableShadow: false
                    Layout.preferredHeight: calendarColumn.implicitHeight + 24

                    property date currentDate: new Date()
                    property int currentDayOfWeek: (currentDate.getDay() + 6) % 7
                    property date weekStart: {
                        var d = new Date(currentDate);
                        var day = d.getDay();
                        var diff = d.getDate() - day + (day === 0 ? -6 : 1);
                        return new Date(d.setDate(diff));
                    }

                    Timer {
                        interval: 60000
                        running: dock.isOpen
                        repeat: true
                        onTriggered: calendarPane.currentDate = new Date()
                    }

                    Column {
                        id: calendarColumn
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        spacing: 6

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: {
                                var m = calendarPane.currentDate.toLocaleDateString(Qt.locale(), "MMMM yyyy");
                                return m.charAt(0).toUpperCase() + m.slice(1);
                            }
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.Medium
                        }

                        Row {
                            spacing: 4

                            Repeater {
                                model: 7

                                Column {
                                    id: dayColumn
                                    required property int index
                                    spacing: 4
                                    width: (scroller.width - 28 - 6 * 4) / 7

                                    property date dayDate: {
                                        var d = new Date(calendarPane.weekStart);
                                        d.setDate(d.getDate() + index);
                                        return d;
                                    }
                                    property bool isToday: index === calendarPane.currentDayOfWeek

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: {
                                            var dayName = dayColumn.dayDate.toLocaleDateString(Qt.locale(), "ddd");
                                            return (dayName.charAt(0).toUpperCase() + dayName.slice(1, 2)).replace(".", "");
                                        }
                                        color: Colors.outline
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                        font.weight: Font.Medium
                                    }

                                    Item {
                                        width: 28
                                        height: 28
                                        anchors.horizontalCenter: parent.horizontalCenter

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 14
                                            color: Styling.srItem("overprimary")
                                            visible: dayColumn.isToday
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: dayColumn.dayDate.getDate()
                                            color: dayColumn.isToday ? Colors.background : Colors.overBackground
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(0)
                                            font.weight: dayColumn.isToday ? Font.Bold : Font.Normal
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── WEATHER ─────────────────────────────────────
                StyledRect {
                    Layout.fillWidth: true
                    variant: "pane"
                    radius: Styling.radius(6)
                    enableShadow: false
                    visible: WeatherService.dataAvailable
                    Layout.preferredHeight: visible ? (weatherCol.implicitHeight + 16) : 0

                    Column {
                        id: weatherCol
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 8
                        spacing: 6

                        WeatherWidget {
                            width: parent.width
                            height: 140
                            showDebugControls: false
                            animationsEnabled: dock.isOpen
                        }
                    }
                }

                // ── POMODORO / START WORK ───────────────────────
                StyledRect {
                    Layout.fillWidth: true
                    variant: "pane"
                    radius: Styling.radius(6)
                    enableShadow: false
                    Layout.preferredHeight: pomo.implicitHeight + 16

                    Pomodoro {
                        id: pomo
                        anchors.centerIn: parent
                        width: parent.width - 16
                    }
                }

                // ── COLOR PICKER ────────────────────────────────
                StyledRect {
                    Layout.fillWidth: true
                    variant: "pane"
                    radius: Styling.radius(6)
                    enableShadow: false
                    Layout.preferredHeight: pickerCol.implicitHeight + 24

                    Column {
                        id: pickerCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8

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

                Item { Layout.preferredHeight: 4 }
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
