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
    // CRÍTICO: ocultar PanelWindow cuando cerrado para no bloquear clicks del sistema.
    visible: isOpen || dockContainer.opacity > 0.001

    readonly property int dockWidth: 380
    readonly property int hPadding: 12
    readonly property int vPadding: 0          // header come hasta el borde
    readonly property int headerHeight: 150
    readonly property int sectionSpacing: 10
    // Tamaño del hombro cóncavo (bottom-left del dock y top-left de la franja del bar)
    readonly property int shoulderSize: 18

    // Tab activa: 0=Calendar, 1=Weather, 2=Pomodoro, 3=ColorPicker
    property int currentTab: 0
    readonly property int tabBarHeight: 64  // altura reservada arriba para las pills floating

    readonly property bool barAtTop: {
        const pos = Config.bar?.position ?? "top";
        return pos === "top";
    }

    readonly property int activeContentHeight: {
        var item = contentStack.children[currentTab];
        if (!item) return 400;
        return item.implicitHeight > 0 ? item.implicitHeight : (item.Layout?.preferredHeight ?? 400);
    }

    readonly property int targetDockHeight: headerHeight + activeContentHeight + sectionSpacing + 24
    readonly property int dynamicHeight: Math.min(targetDockHeight, dock.height - barReserved - 24)

    // Accent dinámico por tab — define el color del border + active pill
    readonly property color tabAccent: {
        switch (currentTab) {
            case 0: return Colors.primary;        // calendar: matugen
            case 1: return "#5dadeb";             // weather: sky blue
            case 2: return "#E07556";             // pomodoro: tomato
            case 3: return Colors.tertiary;       // color picker: matugen tertiary
        }
        return Colors.primary;
    }

    readonly property int barReserved: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "top" ? base : 0;
    }

    implicitWidth: dockWidth + shoulderSize + 32

    // Patrón ChatPanel: cerrado → emptyMask (no intercepta), abierto → fullMask.
    mask: Region { item: dock.visible ? fullMask : emptyMask }
    Item {
        id: fullMask
        x: dock.width - dock.dockWidth
        y: barAtTop ? dock.barReserved : (dock.height - dockBg.height)
        width: dock.dockWidth
        height: dockBg.height
    }
    Item { id: emptyMask; width: 0; height: 0 }

    // Width total = dockBg (380) + shoulderSize. Tab rail vertical eliminada.
    readonly property int dockContainerWidth: dock.dockWidth + dock.shoulderSize

    Item {
        id: dockContainer
        width: dock.dockContainerWidth
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: dock.barReserved
        anchors.bottom: parent.bottom
        opacity: dock.isOpen ? 1 : 0
        visible: opacity > 0.001

        transform: Translate {
            id: slideTransform
            y: dock.isOpen ? 0 : (barAtTop ? -dockBg.height - 50 : dockBg.height + 50)
            Behavior on y {
                NumberAnimation {
                    duration: Config.animDuration > 0 ? Config.animDuration : 250
                    easing.type: dock.isOpen ? Easing.OutBack : Easing.InCubic
                    easing.overshoot: dock.isOpen ? 1.05 : 1.0
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Config.animDuration > 0 ? Config.animDuration : 220
                easing.type: Easing.OutCubic
            }
        }

        // Dock body — bg matugen sólido, sin border ni overlay.
        StyledRect {
            id: dockBg
            anchors.right: parent.right
            anchors.top: barAtTop ? parent.top : undefined
            anchors.bottom: barAtTop ? undefined : parent.bottom
            height: dock.dynamicHeight
            width: dock.dockWidth
            variant: "bg"
            enableShadow: true
            radius: 0
            topLeftRadius: barAtTop ? 0 : Styling.radius(16)
            topRightRadius: barAtTop ? 0 : Styling.radius(16)
            bottomLeftRadius: barAtTop ? Styling.radius(16) : 0
            bottomRightRadius: barAtTop ? Styling.radius(16) : 0
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Header fijo (wallpaper + distro logo) arriba del dock — vive
        // FUERA del ScrollView para que las pills floten sobre él.
        Item {
            id: dockHeader
            anchors.top: dockBg.top
            anchors.left: dockBg.left
            anchors.right: dockBg.right
            height: dock.headerHeight  // 150px
            clip: true
            z: 5

            DistroHeader {
                anchors.fill: parent
            }

            // Vignette inferior sutil para destacar borde del header con el contenido
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 24
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.45) }
                }
            }
        }

        // Hombro cóncavo bottom-left del dock body (rail eliminado).
        // Mismo dark glass que el dockBg para continuidad visual.
        Item {
            id: bottomLeftShoulder
            width: dock.shoulderSize
            height: dock.shoulderSize
            anchors.bottom: dockBg.bottom
            anchors.right: dockBg.left
            visible: !barAtTop

            RoundCorner {
                anchors.fill: parent
                corner: RoundCorner.CornerEnum.TopRight
                size: dock.shoulderSize
                color: dockBg.color
                Behavior on color { ColorAnimation { duration: 700 } }
            }
        }

        // Floating tab pills (top center del dock body) — flotan ENCIMA del
        // contenido. Z elevado para quedar sobre la animación de cada tab.
        Row {
            id: tabPills
            z: 100
            anchors.top: dockBg.top
            anchors.horizontalCenter: dockBg.horizontalCenter
            anchors.topMargin: 14
            spacing: 8

            Repeater {
                model: [
                    { ico: Icons.note,    name: "Calendar" },
                    { ico: Icons.sun,     name: "Weather" },
                    { ico: Icons.timer,   name: "Pomodoro" },
                    { ico: Icons.palette, name: "Color picker" }
                ]

                Rectangle {
                    id: pill
                    required property var modelData
                    required property int index
                    readonly property bool isActive: dock.currentTab === index

                    width: 44
                    height: 44
                    radius: 14
                    color: isActive
                        ? dock.tabAccent
                        : (pillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.42))
                    border.color: isActive ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.15)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 220 } }
                    Behavior on border.color { ColorAnimation { duration: 220 } }

                    // Glow sutil del pill activo
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 12
                        height: parent.height + 12
                        radius: parent.radius + 6
                        color: "transparent"
                        border.color: dock.tabAccent
                        border.width: 1
                        opacity: pill.isActive ? 0.4 : 0
                        Behavior on opacity { NumberAnimation { duration: 260 } }
                        z: -1
                    }

                    Text {
                        anchors.centerIn: parent
                        text: pill.modelData.ico
                        font.family: Icons.font
                        font.pixelSize: 20
                        color: "white"
                    }

                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dock.currentTab = pill.index
                    }

                    StyledToolTip {
                        show: pillMouse.containsMouse
                        tooltipText: pill.modelData.name
                    }
                }
            }
        }

        ScrollView {
            id: scroller
            anchors.right: parent.right
            anchors.top: dockHeader.bottom  // empieza debajo del DistroHeader fijo
            anchors.bottom: dockBg.bottom
            width: dock.dockWidth
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: scroller.width
                spacing: dock.sectionSpacing

                // ── CONTENT (sección activa, full-width) ────────
                StackLayout {
                    id: contentStack
                    Layout.fillWidth: true
                    Layout.leftMargin: dock.hPadding
                    Layout.rightMargin: dock.hPadding
                    Layout.alignment: Qt.AlignTop
                    currentIndex: dock.currentTab

                // ═══════ TAB 0: CALENDAR (time-of-day immersive) ═
                Item {
                    id: calendarTab
                    Layout.fillWidth: true
                    implicitHeight: calendarContent.implicitHeight + 24
                    Layout.preferredHeight: implicitHeight

                    // Hora actual (sin segundos para que no repaint con cada tick)
                    readonly property real hourOfDay: clockHeaderPane.now.getHours() + clockHeaderPane.now.getMinutes() / 60

                    // Background gradient time-of-day (cambia smoothly)
                    Rectangle {
                        id: calendarBg
                        anchors.fill: parent
                        radius: Styling.radius(8)
                        clip: true

                        function topColor(h) {
                            if (h < 5)   return "#0a0c1f";  // night
                            if (h < 6.5) return "#5a3a64";  // pre-dawn purple
                            if (h < 7.5) return "#ff9c5c";  // dawn warm
                            if (h < 12)  return "#7fc8e8";  // morning light blue
                            if (h < 16)  return "#5dadeb";  // afternoon
                            if (h < 18)  return "#ff8a4a";  // sunset
                            if (h < 20)  return "#7a4a8a";  // dusk
                            if (h < 22)  return "#231a3a";  // late evening
                            return "#0a0c1f";
                        }
                        function bottomColor(h) {
                            if (h < 5)   return "#020412";
                            if (h < 6.5) return "#cc7c9e";
                            if (h < 7.5) return "#ffe4b8";
                            if (h < 12)  return "#cfe9f7";
                            if (h < 16)  return "#9fd0ec";
                            if (h < 18)  return "#fcca8a";
                            if (h < 20)  return "#382650";
                            if (h < 22)  return "#0f1228";
                            return "#020412";
                        }

                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop {
                                position: 0.0
                                color: calendarBg.topColor(calendarTab.hourOfDay)
                                Behavior on color { ColorAnimation { duration: 3000 } }
                            }
                            GradientStop {
                                position: 1.0
                                color: calendarBg.bottomColor(calendarTab.hourOfDay)
                                Behavior on color { ColorAnimation { duration: 3000 } }
                            }
                        }

                        // Estrellas (noche)
                        Item {
                            anchors.fill: parent
                            visible: calendarTab.hourOfDay < 5.5 || calendarTab.hourOfDay >= 20
                            Repeater {
                                model: 50
                                Rectangle {
                                    required property int index
                                    x: Math.random() * parent.width
                                    y: Math.random() * (parent.height * 0.6)
                                    width: 1 + Math.random() * 1.5
                                    height: width
                                    radius: width / 2
                                    color: "white"
                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.2; to: 1.0; duration: 1500 + Math.random() * 2000 }
                                        NumberAnimation { from: 1.0; to: 0.2; duration: 1500 + Math.random() * 2000 }
                                    }
                                }
                            }
                        }

                        // Sol (mañana hasta sunset)
                        Rectangle {
                            visible: calendarTab.hourOfDay >= 6.5 && calendarTab.hourOfDay < 18
                            width: 70; height: 70; radius: 35
                            x: parent.width - width - 24
                            y: 24
                            color: calendarTab.hourOfDay < 7.5 ? "#ffd093" :
                                   calendarTab.hourOfDay < 17 ? "#ffe57a" : "#ff9550"
                            Behavior on color { ColorAnimation { duration: 3000 } }
                            // Halo difuminado
                            Rectangle {
                                anchors.centerIn: parent
                                width: 100; height: 100; radius: 50
                                color: parent.color
                                opacity: 0.25
                                z: -1
                            }
                        }

                        // Luna (noche)
                        Rectangle {
                            visible: calendarTab.hourOfDay < 5.5 || calendarTab.hourOfDay >= 20
                            width: 60; height: 60; radius: 30
                            x: parent.width - width - 24
                            y: 24
                            color: "#e8e6dc"
                            Rectangle {
                                width: 48; height: 48; radius: 24
                                x: 14; y: -4
                                color: calendarTab.hourOfDay < 5.5 || calendarTab.hourOfDay >= 22 ? "#0a0c1f" : "#231a3a"
                                Behavior on color { ColorAnimation { duration: 3000 } }
                            }
                        }

                        // Partículas de día (dust motes / lluvia de luz)
                        Item {
                            anchors.fill: parent
                            visible: calendarTab.hourOfDay >= 6 && calendarTab.hourOfDay < 20
                            Repeater {
                                model: 18
                                Rectangle {
                                    required property int index
                                    x: Math.random() * parent.width
                                    width: 2 + Math.random() * 1.5
                                    height: width
                                    radius: width / 2
                                    color: Qt.rgba(1, 0.95, 0.85, 0.45)
                                    opacity: 0
                                    SequentialAnimation on y {
                                        loops: Animation.Infinite
                                        NumberAnimation {
                                            from: parent.height + 10; to: -10
                                            duration: 12000 + Math.random() * 8000
                                            easing.type: Easing.Linear
                                        }
                                    }
                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0; to: 0.6; duration: 2000 }
                                        PauseAnimation { duration: 5000 }
                                        NumberAnimation { from: 0.6; to: 0; duration: 2000 }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        id: calendarContent
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                    // Analog clock + fecha + context strip (glass card)
                    Rectangle {
                        id: clockHeaderPane
                        Layout.fillWidth: true
                        Layout.preferredHeight: 280
                        color: Qt.rgba(0, 0, 0, 0.35)
                        radius: 14
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1

                        property date now: new Date()
                        Timer {
                            interval: 1000
                            running: dock.isOpen && dock.currentTab === 0
                            repeat: true
                            triggeredOnStart: true
                            onTriggered: clockHeaderPane.now = new Date()
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 10

                            // Analog clock face — Canvas draws face+numerals+ticks
                            // de forma determinística; las manecillas son
                            // Rectangle rotables encima.
                            Item {
                                id: analogClock
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 180
                                Layout.preferredHeight: 180
                                width: 180
                                height: 180

                                readonly property real cx: width / 2
                                readonly property real cy: height / 2

                                // Cara estática (border + numerales + minute ticks)
                                Canvas {
                                    id: faceCanvas
                                    anchors.fill: parent
                                    antialiasing: true

                                    readonly property color faceBg: Styling.srItem("pane") || Colors.background
                                    readonly property color outlineColor: Colors.outline
                                    readonly property color numColor: Colors.overBackground

                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);

                                        var cx = width / 2;
                                        var cy = height / 2;
                                        var rOuter = Math.min(cx, cy) - 1;
                                        var rNumerals = rOuter - 16;
                                        var rTickOuter = rOuter - 6;
                                        var rTickInner = rOuter - 10;

                                        // Face fill
                                        ctx.fillStyle = faceBg;
                                        ctx.beginPath();
                                        ctx.arc(cx, cy, rOuter, 0, 2 * Math.PI);
                                        ctx.fill();

                                        // Outer border
                                        ctx.strokeStyle = outlineColor;
                                        ctx.lineWidth = 1.5;
                                        ctx.beginPath();
                                        ctx.arc(cx, cy, rOuter, 0, 2 * Math.PI);
                                        ctx.stroke();

                                        // Minute ticks (60). Los de cada 5 son más largos pero
                                        // las posiciones de 5 las cubre el numeral, así que
                                        // dibujamos sólo los 48 minor ticks.
                                        ctx.strokeStyle = outlineColor;
                                        ctx.lineWidth = 1;
                                        for (var i = 0; i < 60; i++) {
                                            if (i % 5 === 0) continue; // skip donde van numerales
                                            var a = (i / 60) * 2 * Math.PI - Math.PI / 2;
                                            var x1 = cx + rTickInner * Math.cos(a);
                                            var y1 = cy + rTickInner * Math.sin(a);
                                            var x2 = cx + rTickOuter * Math.cos(a);
                                            var y2 = cy + rTickOuter * Math.sin(a);
                                            ctx.beginPath();
                                            ctx.moveTo(x1, y1);
                                            ctx.lineTo(x2, y2);
                                            ctx.stroke();
                                        }

                                        // Roman numerals (XII at top)
                                        var romans = ["XII","I","II","III","IV","V","VI","VII","VIII","IX","X","XI"];
                                        ctx.fillStyle = numColor;
                                        ctx.font = "600 13px " + Config.theme.font;
                                        ctx.textAlign = "center";
                                        ctx.textBaseline = "middle";
                                        for (var j = 0; j < 12; j++) {
                                            var ang = (j * 30 - 90) * Math.PI / 180;
                                            var nx = cx + rNumerals * Math.cos(ang);
                                            var ny = cy + rNumerals * Math.sin(ang);
                                            ctx.fillText(romans[j], nx, ny);
                                        }
                                    }

                                    Connections {
                                        target: Colors
                                        function onPrimaryChanged() { faceCanvas.requestPaint(); }
                                        function onOnSurfaceChanged() { faceCanvas.requestPaint(); }
                                    }
                                }

                                // Hour hand
                                Rectangle {
                                    width: 4
                                    height: analogClock.width * 0.27
                                    radius: 2
                                    color: Colors.primary
                                    x: analogClock.cx - width / 2
                                    y: analogClock.cy - height
                                    transformOrigin: Item.Bottom
                                    rotation: ((clockHeaderPane.now.getHours() % 12) * 30) +
                                              (clockHeaderPane.now.getMinutes() * 0.5)
                                }

                                // Minute hand
                                Rectangle {
                                    width: 3
                                    height: analogClock.width * 0.38
                                    radius: 1.5
                                    color: Colors.secondary
                                    x: analogClock.cx - width / 2
                                    y: analogClock.cy - height
                                    transformOrigin: Item.Bottom
                                    rotation: clockHeaderPane.now.getMinutes() * 6 +
                                              clockHeaderPane.now.getSeconds() * 0.1
                                }

                                // Second hand (thin, accent)
                                Rectangle {
                                    width: 1.5
                                    height: analogClock.width * 0.42
                                    color: Colors.tertiary
                                    x: analogClock.cx - width / 2
                                    y: analogClock.cy - height
                                    transformOrigin: Item.Bottom
                                    rotation: clockHeaderPane.now.getSeconds() * 6
                                }

                                // Center cap
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: Colors.primary
                                    z: 10
                                    border.color: Colors.background
                                    border.width: 2
                                }
                            }

                            // Date completa centrada debajo
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: {
                                    var s = clockHeaderPane.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM yyyy");
                                    return s.charAt(0).toUpperCase() + s.slice(1);
                                }
                                color: Colors.outline
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                                font.weight: Font.Medium
                            }

                            // Strip de context: semana ISO + día del año + % del año
                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22

                                // Compute helpers
                                function isoWeek(d) {
                                    var x = new Date(d.getTime());
                                    x.setHours(0, 0, 0, 0);
                                    // Jueves de esta semana
                                    x.setDate(x.getDate() + 3 - (x.getDay() + 6) % 7);
                                    var week1 = new Date(x.getFullYear(), 0, 4);
                                    return 1 + Math.round(((x - week1) / 86400000 - 3 + (week1.getDay() + 6) % 7) / 7);
                                }
                                function dayOfYear(d) {
                                    var start = new Date(d.getFullYear(), 0, 0);
                                    return Math.floor((d - start) / 86400000);
                                }
                                function daysInYear(y) {
                                    return ((y % 4 === 0 && y % 100 !== 0) || y % 400 === 0) ? 366 : 365;
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 14

                                    Text {
                                        text: "Wk " + parent.parent.isoWeek(clockHeaderPane.now)
                                        color: Colors.outline
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                    }
                                    Rectangle {
                                        width: 3; height: 3; radius: 1.5
                                        color: Colors.outline
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        property int doy: parent.parent.dayOfYear(clockHeaderPane.now)
                                        property int diy: parent.parent.daysInYear(clockHeaderPane.now.getFullYear())
                                        text: "Day " + doy + "/" + diy
                                        color: Colors.outline
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                    }
                                    Rectangle {
                                        width: 3; height: 3; radius: 1.5
                                        color: Colors.outline
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        property real pct: 100 * parent.parent.dayOfYear(clockHeaderPane.now) / parent.parent.daysInYear(clockHeaderPane.now.getFullYear())
                                        text: pct.toFixed(0) + "% year"
                                        color: Colors.primary
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }
                    }

                    // ── DAY PROGRESS card: % del día / semana / mes / año
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 144
                        color: Qt.rgba(0, 0, 0, 0.35)
                        radius: 14
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1

                        function dayProgress(d) {
                            return (d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()) / 86400;
                        }
                        function weekProgress(d) {
                            // Lunes como día 0
                            var dow = (d.getDay() + 6) % 7;
                            var elapsed = dow * 86400000 + (d - new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime());
                            return elapsed / (7 * 86400000);
                        }
                        function monthProgress(d) {
                            var first = new Date(d.getFullYear(), d.getMonth(), 1);
                            var next = new Date(d.getFullYear(), d.getMonth() + 1, 1);
                            return (d - first) / (next - first);
                        }
                        function yearProgress(d) {
                            var first = new Date(d.getFullYear(), 0, 1);
                            var next = new Date(d.getFullYear() + 1, 0, 1);
                            return (d - first) / (next - first);
                        }

                        Column {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 8

                            Text {
                                text: "Time elapsed"
                                color: Qt.rgba(1, 1, 1, 0.6)
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                            }

                            Repeater {
                                model: [
                                    { label: "Day",   getter: parent.parent.dayProgress },
                                    { label: "Week",  getter: parent.parent.weekProgress },
                                    { label: "Month", getter: parent.parent.monthProgress },
                                    { label: "Year",  getter: parent.parent.yearProgress }
                                ]

                                Item {
                                    required property var modelData
                                    width: parent.width
                                    height: 16

                                    readonly property real pct: modelData.getter(clockHeaderPane.now)

                                    Row {
                                        anchors.fill: parent
                                        spacing: 10

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 50
                                            text: modelData.label
                                            color: Qt.rgba(1, 1, 1, 0.7)
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-1)
                                        }

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 50 - 10 - 50 - 10
                                            height: 6
                                            radius: 3
                                            color: Qt.rgba(1, 1, 1, 0.12)
                                            Rectangle {
                                                width: parent.width * pct
                                                height: parent.height
                                                radius: parent.radius
                                                color: "white"
                                                Behavior on width { NumberAnimation { duration: 600 } }
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 50
                                            horizontalAlignment: Text.AlignRight
                                            text: (pct * 100).toFixed(1) + "%"
                                            color: "white"
                                            font.family: Config.theme.monoFont
                                            font.pixelSize: Styling.fontSize(-1)
                                            font.weight: Font.Bold
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── CALENDAR (full month) — glass card
                    Rectangle {
                        id: calendarPane
                        Layout.fillWidth: true
                        color: Qt.rgba(0, 0, 0, 0.35)
                        radius: 14
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1
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

                    Item { Layout.fillHeight: true } // spacer fin de tab Calendar
                    } // ColumnLayout calendarContent
                } // Item calendarTab (TAB 0)

                // ═══════ TAB 1: WEATHER (animated bg) ═══════════
                Item {
                    id: weatherTab
                    Layout.fillWidth: true
                    implicitHeight: weatherContent.implicitHeight + 24
                    Layout.preferredHeight: implicitHeight

                    // Categoría derivada del weather code para elegir animación
                    readonly property string weatherCategory: {
                        var c = WeatherService.weatherCode;
                        if (c === 0) return WeatherService.isDay ? "sunny" : "night";
                        if (c <= 3) return "cloudy";
                        if (c === 45 || c === 48) return "foggy";
                        if ((c >= 51 && c <= 57) || (c >= 61 && c <= 67) || (c >= 80 && c <= 82)) return "rainy";
                        if ((c >= 71 && c <= 77) || (c >= 85 && c <= 86)) return "snowy";
                        if (c >= 95 && c <= 99) return "stormy";
                        return "cloudy";
                    }

                    // ── BACKGROUND: gradient + animation
                    Rectangle {
                        id: weatherBg
                        anchors.fill: parent
                        radius: Styling.radius(8)
                        clip: true

                        // Gradient base — colores swap suave entre categorías
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop {
                                position: 0.0
                                color: {
                                    switch (weatherTab.weatherCategory) {
                                        case "sunny":  return "#5dade2";
                                        case "night":  return "#0c1a3e";
                                        case "rainy":  return "#3a4f5e";
                                        case "stormy": return "#1c2233";
                                        case "snowy":  return "#a8c5e0";
                                        case "foggy":  return "#7f8fa6";
                                        case "cloudy": return "#6d7b8d";
                                    }
                                    return "#6d7b8d";
                                }
                                Behavior on color { ColorAnimation { duration: 1500 } }
                            }
                            GradientStop {
                                position: 1.0
                                color: {
                                    switch (weatherTab.weatherCategory) {
                                        case "sunny":  return "#fcb084";
                                        case "night":  return "#020412";
                                        case "rainy":  return "#1f2937";
                                        case "stormy": return "#0a0a17";
                                        case "snowy":  return "#e8eef5";
                                        case "foggy":  return "#bfc7cf";
                                        case "cloudy": return "#34404f";
                                    }
                                    return "#34404f";
                                }
                                Behavior on color { ColorAnimation { duration: 1500 } }
                            }
                        }

                        // Loader con la animación apropiada
                        Loader {
                            anchors.fill: parent
                            sourceComponent: {
                                switch (weatherTab.weatherCategory) {
                                    case "sunny":  return sunnyAnim;
                                    case "night":  return nightAnim;
                                    case "rainy":  return rainAnim;
                                    case "stormy": return stormyAnim;
                                    case "snowy":  return snowyAnim;
                                    case "foggy":  return foggyAnim;
                                    case "cloudy": return cloudyAnim;
                                }
                                return cloudyAnim;
                            }
                        }
                    }

                    // ── CONTENT: glass cards encima del bg
                    ColumnLayout {
                        id: weatherContent
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        // HERO: emoji + temp + descripción
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 130
                            color: Qt.rgba(0, 0, 0, 0.32)
                            radius: 14
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                            border.width: 1

                            Row {
                                anchors.centerIn: parent
                                spacing: 18

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: WeatherService.weatherSymbol || "🌡"
                                    font.pixelSize: 64
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        text: Math.round(WeatherService.currentTemp) + "°"
                                        color: "white"
                                        font.family: Config.theme.font
                                        font.pixelSize: 52
                                        font.weight: Font.Light
                                    }
                                    Text {
                                        text: WeatherService.weatherDescription || "—"
                                        color: Qt.rgba(1, 1, 1, 0.78)
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(0)
                                    }
                                    Text {
                                        text: "feels " + Math.round(WeatherService.apparentTemp) + "°  ·  " +
                                              "↑" + Math.round(WeatherService.maxTemp) + "  ↓" + Math.round(WeatherService.minTemp)
                                        color: Qt.rgba(1, 1, 1, 0.55)
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                    }
                                }
                            }
                        }

                        // STATS GRID 4 mini-cards
                        Row {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 72
                            spacing: 8

                            Repeater {
                                model: [
                                    { ico: "💧", lab: "humid", val: Math.round(WeatherService.humidity) + "%" },
                                    { ico: "☀️", lab: "UV",    val: WeatherService.uvIndex.toFixed(1) },
                                    { ico: "⛅", lab: "rain",  val: Math.round(WeatherService.precipitationProbability) + "%" },
                                    { ico: "🌬", lab: "wind",  val: WeatherService.windSpeed.toFixed(0) + "km/h" }
                                ]

                                Rectangle {
                                    required property var modelData
                                    width: (weatherContent.width - 24) / 4
                                    height: 72
                                    color: Qt.rgba(0, 0, 0, 0.32)
                                    radius: 12
                                    border.color: Qt.rgba(1, 1, 1, 0.10)
                                    border.width: 1

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.ico
                                            font.pixelSize: 18
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.val
                                            color: "white"
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(0)
                                            font.weight: Font.Bold
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.lab
                                            color: Qt.rgba(1, 1, 1, 0.55)
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-2)
                                        }
                                    }
                                }
                            }
                        }

                        // WIND compass card
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 100
                            color: Qt.rgba(0, 0, 0, 0.32)
                            radius: 12
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            border.width: 1

                            Row {
                                anchors.centerIn: parent
                                spacing: 22

                                Item {
                                    width: 64; height: 64
                                    anchors.verticalCenter: parent.verticalCenter

                                    Canvas {
                                        anchors.fill: parent
                                        antialiasing: true
                                        onPaint: {
                                            var ctx = getContext("2d");
                                            ctx.clearRect(0, 0, width, height);
                                            var cx = width / 2, cy = height / 2, r = Math.min(cx, cy) - 2;
                                            ctx.strokeStyle = "rgba(255,255,255,0.4)";
                                            ctx.lineWidth = 1;
                                            ctx.beginPath();
                                            ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                                            ctx.stroke();
                                            ctx.fillStyle = "rgba(255,255,255,0.6)";
                                            ctx.font = "9px " + Config.theme.font;
                                            ctx.textAlign = "center"; ctx.textBaseline = "middle";
                                            ctx.fillText("N", cx, cy - r + 8);
                                            ctx.fillText("E", cx + r - 8, cy);
                                            ctx.fillText("S", cx, cy + r - 8);
                                            ctx.fillText("W", cx - r + 8, cy);
                                        }
                                    }
                                    Rectangle {
                                        width: 2; height: 24; radius: 1
                                        color: Colors.primary
                                        x: parent.width / 2 - width / 2
                                        y: parent.height / 2 - height
                                        transformOrigin: Item.Bottom
                                        rotation: WeatherService.windDirection + 180
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        text: WeatherService.windSpeed.toFixed(1) + " km/h"
                                        color: "white"
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(3)
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        text: {
                                            var dirs = ["N","NE","E","SE","S","SW","W","NW"];
                                            return "from " + dirs[Math.round(WeatherService.windDirection / 45) % 8];
                                        }
                                        color: Qt.rgba(1, 1, 1, 0.55)
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                    }
                                }
                            }
                        }

                        // FORECAST 5 días
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 110
                            color: Qt.rgba(0, 0, 0, 0.32)
                            radius: 12
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            border.width: 1
                            visible: WeatherService.forecast.length > 0

                            Row {
                                anchors.centerIn: parent
                                spacing: 6

                                Repeater {
                                    model: WeatherService.forecast.slice(0, 5)
                                    Column {
                                        required property var modelData
                                        spacing: 4
                                        width: (weatherContent.width - 24 - 4 * 6) / 5
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.dayName
                                            color: Qt.rgba(1, 1, 1, 0.75)
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-1)
                                            font.weight: Font.Medium
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.emoji
                                            font.pixelSize: Styling.fontSize(3)
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Math.round(modelData.maxTemp) + "°"
                                            color: "white"
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(0)
                                            font.weight: Font.Bold
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: Math.round(modelData.minTemp) + "°"
                                            color: Qt.rgba(1, 1, 1, 0.5)
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-1)
                                        }
                                    }
                                }
                            }
                        }

                        // HOURLY GRAPH 24h
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 110
                            color: Qt.rgba(0, 0, 0, 0.32)
                            radius: 12
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            border.width: 1
                            visible: WeatherService.hourly.length > 0

                            Column {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4
                                Text {
                                    text: "Next 24h"
                                    color: Qt.rgba(1, 1, 1, 0.6)
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.Medium
                                }
                                Canvas {
                                    width: parent.width
                                    height: parent.height - 24
                                    antialiasing: true
                                    property var d: WeatherService.hourly
                                    onDChanged: requestPaint()

                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        if (!d || d.length === 0) return;
                                        var w = width, h = height, pad = 8, n = d.length;
                                        var minT = d[0].temp, maxT = d[0].temp;
                                        for (var i = 0; i < n; i++) {
                                            if (d[i].temp < minT) minT = d[i].temp;
                                            if (d[i].temp > maxT) maxT = d[i].temp;
                                        }
                                        var range = maxT - minT || 1;
                                        // Fill bajo la curva
                                        ctx.fillStyle = "rgba(255,255,255,0.10)";
                                        ctx.beginPath();
                                        ctx.moveTo(pad, h - pad);
                                        for (var j = 0; j < n; j++) {
                                            var x = pad + (j / (n - 1)) * (w - 2 * pad);
                                            var y = h - pad - ((d[j].temp - minT) / range) * (h - 2 * pad - 12);
                                            ctx.lineTo(x, y);
                                        }
                                        ctx.lineTo(w - pad, h - pad);
                                        ctx.closePath();
                                        ctx.fill();
                                        // Curva
                                        ctx.strokeStyle = "white";
                                        ctx.lineWidth = 2;
                                        ctx.beginPath();
                                        for (var k = 0; k < n; k++) {
                                            var xx = pad + (k / (n - 1)) * (w - 2 * pad);
                                            var yy = h - pad - ((d[k].temp - minT) / range) * (h - 2 * pad - 12);
                                            if (k === 0) ctx.moveTo(xx, yy);
                                            else ctx.lineTo(xx, yy);
                                        }
                                        ctx.stroke();
                                        // Hour labels
                                        ctx.fillStyle = "rgba(255,255,255,0.55)";
                                        ctx.font = "10px " + Config.theme.font;
                                        ctx.textAlign = "center";
                                        var marks = [0, 6, 12, 18, n - 1];
                                        for (var m = 0; m < marks.length; m++) {
                                            var mi = marks[m];
                                            if (mi >= n) continue;
                                            var mx = pad + (mi / (n - 1)) * (w - 2 * pad);
                                            ctx.fillText(d[mi].time.split("T")[1].substring(0, 5), mx, h - 1);
                                        }
                                    }
                                }
                            }
                        }

                        // SUN / MOON
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            color: Qt.rgba(0, 0, 0, 0.32)
                            radius: 12
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            border.width: 1

                            function moonPhase(date) {
                                var lp = 2551443;
                                var nf = new Date(1970, 0, 7, 20, 35, 0);
                                var phase = ((date.getTime() / 1000) - nf.getTime() / 1000) % lp;
                                var f = phase / lp;
                                return ["🌑","🌒","🌓","🌔","🌕","🌖","🌗","🌘"][Math.floor(f * 8) % 8];
                            }

                            Row {
                                anchors.centerIn: parent
                                spacing: 22

                                Repeater {
                                    model: [
                                        { ico: "🌅", lab: "sunrise", val: WeatherService.sunrise || "—" },
                                        { ico: "🌇", lab: "sunset",  val: WeatherService.sunset  || "—" },
                                        { ico: parent.parent.moonPhase(clockHeaderPane.now), lab: "moon", val: "" }
                                    ]
                                    Column {
                                        required property var modelData
                                        spacing: 2
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.ico; font.pixelSize: 16 }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.val !== "" ? modelData.val : modelData.lab
                                            color: "white"
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-1)
                                            font.weight: modelData.val !== "" ? Font.Bold : Font.Normal
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── ANIMATION COMPONENTS (siblings as Component definitions)
                    Component {
                        id: sunnyAnim
                        Item {
                            Item {
                                id: sun
                                width: 120; height: 120
                                x: parent.width - width - 28
                                y: 28
                                // Halo difuminado simulado con 3 círculos concentricos
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 140; height: 140; radius: 70
                                    color: Qt.rgba(1, 0.95, 0.6, 0.15)
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 110; height: 110; radius: 55
                                    color: Qt.rgba(1, 0.92, 0.5, 0.3)
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 80; height: 80; radius: 40
                                    color: "#fcc14e"
                                }
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 60; height: 60; radius: 30
                                    color: "#fff0b0"
                                }
                                // Rotating rays
                                Item {
                                    anchors.centerIn: parent
                                    width: 180; height: 180
                                    NumberAnimation on rotation {
                                        from: 0; to: 360; duration: 30000; loops: Animation.Infinite
                                    }
                                    Repeater {
                                        model: 8
                                        Rectangle {
                                            required property int index
                                            width: 2; height: 28; radius: 1
                                            color: Qt.rgba(1, 0.95, 0.6, 0.45)
                                            x: 180 / 2 - 1
                                            y: 0
                                            transformOrigin: Item.Bottom
                                            rotation: index * 45
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Component {
                        id: nightAnim
                        Item {
                            Repeater {
                                model: 60
                                Rectangle {
                                    required property int index
                                    x: Math.random() * parent.width
                                    y: Math.random() * (parent.height * 0.7)
                                    width: 1 + Math.random() * 1.5
                                    height: width
                                    radius: width / 2
                                    color: "white"
                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 0.2; to: 1.0; duration: 1500 + Math.random() * 2000 }
                                        NumberAnimation { from: 1.0; to: 0.2; duration: 1500 + Math.random() * 2000 }
                                    }
                                }
                            }
                            // Luna
                            Rectangle {
                                width: 80; height: 80; radius: 40
                                x: parent.width - 110; y: 30
                                color: "#e8e6dc"
                                Rectangle {
                                    width: 65; height: 65; radius: 32
                                    x: 20; y: -5
                                    color: "#0c1a3e"
                                }
                            }
                        }
                    }

                    Component {
                        id: rainAnim
                        Item {
                            Repeater {
                                model: 80
                                Rectangle {
                                    required property int index
                                    x: Math.random() * parent.width
                                    width: 1
                                    height: 8 + Math.random() * 8
                                    color: Qt.rgba(0.7, 0.85, 1, 0.5)
                                    SequentialAnimation on y {
                                        loops: Animation.Infinite
                                        NumberAnimation {
                                            from: -20; to: parent.height + 20
                                            duration: 800 + Math.random() * 800
                                            easing.type: Easing.InQuad
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Component {
                        id: stormyAnim
                        Item {
                            Repeater {
                                model: 100
                                Rectangle {
                                    required property int index
                                    x: Math.random() * parent.width
                                    width: 1.5
                                    height: 12 + Math.random() * 10
                                    color: Qt.rgba(0.6, 0.7, 0.9, 0.6)
                                    SequentialAnimation on y {
                                        loops: Animation.Infinite
                                        NumberAnimation {
                                            from: -30; to: parent.height + 20
                                            duration: 600 + Math.random() * 500
                                            easing.type: Easing.InQuad
                                        }
                                    }
                                }
                            }
                            // Flash de rayo periódico
                            Rectangle {
                                anchors.fill: parent
                                color: "white"
                                opacity: 0
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: 4000 + Math.random() * 4000 }
                                    NumberAnimation { to: 0.55; duration: 60 }
                                    NumberAnimation { to: 0; duration: 200 }
                                    PauseAnimation { duration: 80 }
                                    NumberAnimation { to: 0.4; duration: 50 }
                                    NumberAnimation { to: 0; duration: 250 }
                                }
                            }
                        }
                    }

                    Component {
                        id: snowyAnim
                        Item {
                            Repeater {
                                model: 60
                                Text {
                                    required property int index
                                    readonly property real startX: Math.random() * parent.width
                                    readonly property real swayAmp: 12 + Math.random() * 12
                                    text: "❄"
                                    color: "white"
                                    opacity: 0.6 + Math.random() * 0.4
                                    font.pixelSize: 8 + Math.random() * 10
                                    x: startX
                                    NumberAnimation on y {
                                        loops: Animation.Infinite
                                        from: -10; to: parent.height + 10
                                        duration: 5000 + Math.random() * 3000
                                    }
                                    SequentialAnimation on x {
                                        loops: Animation.Infinite
                                        NumberAnimation { from: startX - swayAmp; to: startX + swayAmp; duration: 2500; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: startX + swayAmp; to: startX - swayAmp; duration: 2500; easing.type: Easing.InOutSine }
                                    }
                                }
                            }
                        }
                    }

                    Component {
                        id: foggyAnim
                        Item {
                            Repeater {
                                model: 6
                                Rectangle {
                                    required property int index
                                    width: parent.width * 1.3
                                    height: 40 + Math.random() * 30
                                    radius: 20
                                    color: Qt.rgba(1, 1, 1, 0.10)
                                    y: index * (parent.height / 6) + Math.random() * 30
                                    NumberAnimation on x {
                                        loops: Animation.Infinite
                                        from: -parent.width * 0.3
                                        to: parent.width * 0.1
                                        duration: 18000 + Math.random() * 10000
                                    }
                                }
                            }
                        }
                    }

                    Component {
                        id: cloudyAnim
                        Item {
                            Repeater {
                                model: 5
                                Item {
                                    required property int index
                                    readonly property real cw: 80 + Math.random() * 60
                                    readonly property real ch: 30 + Math.random() * 20
                                    width: cw; height: ch
                                    y: index * (parent.height / 6) + 10 + Math.random() * 20
                                    NumberAnimation on x {
                                        loops: Animation.Infinite
                                        from: -150; to: parent.width + 150
                                        duration: 22000 + Math.random() * 18000
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: parent.height / 2
                                        color: Qt.rgba(1, 1, 1, 0.18)
                                    }
                                    Rectangle {
                                        width: parent.width * 0.5; height: parent.height * 0.9
                                        radius: height / 2
                                        x: parent.width * 0.15; y: -parent.height * 0.35
                                        color: Qt.rgba(1, 1, 1, 0.16)
                                    }
                                }
                            }
                        }
                    }

                } // Item weatherTab (TAB 1)

                // ═══════ TAB 2: POMODORO (creative) ═════════════
                ColumnLayout {
                    spacing: dock.sectionSpacing

                    // Estado del día (in-memory)
                    property int sessionsToday: 0
                    property int minutesToday: 0
                    property int streakDays: 0  // requiere persistencia para ser real

                    Connections {
                        target: pomo
                        function onIsWorkSessionChanged() {
                            if (!pomo.isWorkSession && pomo.alarmActive) {
                                pomoTabRoot.sessionsToday++;
                                pomoTabRoot.minutesToday += Math.round(pomo.totalTime / 60);
                            }
                        }
                    }

                    Item { id: pomoTabRoot }  // placeholder para los Connections

                    // ──── HERO PANE: gradient bg + partículas + tomate + ring
                    Item {
                        id: heroPane
                        Layout.fillWidth: true
                        Layout.preferredHeight: 340

                        // Gradient dinámico: tonos cálidos en work, fríos en break
                        Rectangle {
                            anchors.fill: parent
                            radius: Styling.radius(6)
                            clip: true

                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop {
                                    position: 0.0
                                    color: pomo.isWorkSession
                                        ? Qt.darker(Colors.primary, 1.4)
                                        : Qt.lighter(Colors.secondary, 1.1)
                                    Behavior on color { ColorAnimation { duration: 1200 } }
                                }
                                GradientStop {
                                    position: 1.0
                                    color: pomo.isWorkSession
                                        ? Qt.darker(Colors.background, 1.2)
                                        : Qt.darker(Colors.tertiary, 1.3)
                                    Behavior on color { ColorAnimation { duration: 1200 } }
                                }
                            }

                            // Partículas flotantes — gotas de lluvia simuladas
                            Item {
                                anchors.fill: parent
                                clip: true

                                Repeater {
                                    model: 32

                                    Rectangle {
                                        required property int index
                                        readonly property real fallDuration: 2200 + Math.random() * 1800
                                        readonly property real startX: Math.random() * heroPane.width
                                        x: startX
                                        width: 1
                                        height: 8 + Math.random() * 6
                                        radius: 0.5
                                        color: Qt.rgba(1, 1, 1, 0.25 + Math.random() * 0.2)
                                        opacity: pomo.isRunning ? 1 : 0.4
                                        Behavior on opacity { NumberAnimation { duration: 600 } }

                                        SequentialAnimation on y {
                                            loops: Animation.Infinite
                                            running: heroPane.visible
                                            NumberAnimation {
                                                from: -20
                                                to: heroPane.height + 20
                                                duration: fallDuration
                                                easing.type: Easing.InQuad
                                            }
                                        }
                                    }
                                }
                            }

                            // Anillo de progreso + tomate centrado
                            Item {
                                id: tomatoStage
                                anchors.centerIn: parent
                                width: 220
                                height: 220

                                // Ring de progreso (Canvas)
                                Canvas {
                                    id: progressRing
                                    anchors.fill: parent
                                    antialiasing: true

                                    property real progress: pomo.visualProgress
                                    onProgressChanged: requestPaint()
                                    Connections {
                                        target: Colors
                                        function onPrimaryChanged() { progressRing.requestPaint(); }
                                    }

                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        var cx = width / 2, cy = height / 2;
                                        var r = Math.min(cx, cy) - 8;

                                        // Track de fondo
                                        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.15);
                                        ctx.lineWidth = 6;
                                        ctx.beginPath();
                                        ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                                        ctx.stroke();

                                        // Progress arc
                                        ctx.strokeStyle = pomo.isWorkSession ? Colors.primary : Colors.tertiary;
                                        ctx.lineWidth = 6;
                                        ctx.lineCap = "round";
                                        ctx.beginPath();
                                        ctx.arc(cx, cy, r, -Math.PI / 2,
                                                -Math.PI / 2 + (progress * 2 * Math.PI));
                                        ctx.stroke();
                                    }
                                }

                                // Tomate emoji con pulse + wobble al click
                                Text {
                                    id: tomato
                                    anchors.centerIn: parent
                                    text: pomo.isWorkSession ? "🍅" : "☕"
                                    font.pixelSize: 90

                                    // Pulse continuo cuando isRunning
                                    SequentialAnimation on scale {
                                        running: pomo.isRunning && dock.currentTab === 2
                                        loops: Animation.Infinite
                                        NumberAnimation { from: 1.0; to: 1.06; duration: 1500; easing.type: Easing.InOutSine }
                                        NumberAnimation { from: 1.06; to: 1.0; duration: 1500; easing.type: Easing.InOutSine }
                                    }

                                    // Wobble al hover/click
                                    transform: Rotation {
                                        id: wobble
                                        origin.x: tomato.width / 2
                                        origin.y: tomato.height / 2
                                        angle: 0
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: wobbleAnim.restart()
                                    }
                                    SequentialAnimation {
                                        id: wobbleAnim
                                        NumberAnimation { target: wobble; property: "angle"; to: -8; duration: 80 }
                                        NumberAnimation { target: wobble; property: "angle"; to: 8;  duration: 120 }
                                        NumberAnimation { target: wobble; property: "angle"; to: -4; duration: 100 }
                                        NumberAnimation { target: wobble; property: "angle"; to: 0;  duration: 100 }
                                    }
                                }

                                // Timer text encima del tomate (top center)
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    anchors.topMargin: 20
                                    text: {
                                        var s = Math.max(0, pomo.timeLeft);
                                        var m = Math.floor(s / 60);
                                        var ss = s % 60;
                                        return (m < 10 ? "0" : "") + m + ":" + (ss < 10 ? "0" : "") + ss;
                                    }
                                    color: "white"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(3)
                                    font.weight: Font.Bold
                                }

                                // Label work/break debajo del tomate
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 18
                                    text: pomo.isWorkSession ? "FOCUS" : "BREAK"
                                    color: "white"
                                    opacity: 0.7
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.Bold
                                    font.letterSpacing: 3
                                }
                            }

                            // Pomodoro widget existente (controles play/pause/skip) en bottom
                            Item {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 8
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 20
                                height: pomo.implicitHeight

                                Pomodoro {
                                    id: pomo
                                    anchors.centerIn: parent
                                    width: parent.width
                                }
                            }
                        }
                    }

                    // ──── STATS ANIMADOS ───────────────────────────
                    StyledRect {
                        Layout.fillWidth: true
                        variant: "pane"
                        radius: Styling.radius(6)
                        enableShadow: false
                        Layout.preferredHeight: 86

                        Row {
                            anchors.centerIn: parent
                            spacing: 32

                            // Sessions
                            Column {
                                spacing: 2
                                Row {
                                    spacing: 6
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Text {
                                        text: "🍅"; font.pixelSize: 18
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: pomoTabRoot.parent.sessionsToday
                                        color: Colors.overBackground
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(4)
                                        font.weight: Font.Bold
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "sessions today"
                                    color: Colors.outline
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                }
                            }

                            // Minutes
                            Column {
                                spacing: 2
                                Row {
                                    spacing: 6
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Text {
                                        text: "⏱"; font.pixelSize: 18
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: pomoTabRoot.parent.minutesToday
                                        color: Colors.overBackground
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(4)
                                        font.weight: Font.Bold
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "minutes"
                                    color: Colors.outline
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                }
                            }

                            // Streak (con flame animada)
                            Column {
                                spacing: 2
                                Row {
                                    spacing: 6
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Text {
                                        text: "🔥"; font.pixelSize: 18
                                        anchors.verticalCenter: parent.verticalCenter
                                        SequentialAnimation on scale {
                                            loops: Animation.Infinite
                                            running: dock.isOpen && dock.currentTab === 2
                                            NumberAnimation { from: 1.0; to: 1.15; duration: 800; easing.type: Easing.InOutSine }
                                            NumberAnimation { from: 1.15; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                                        }
                                    }
                                    Text {
                                        text: pomoTabRoot.parent.streakDays
                                        color: Colors.overBackground
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(4)
                                        font.weight: Font.Bold
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "day streak"
                                    color: Colors.outline
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                }
                            }
                        }
                    }

                    // ──── QUOTE ROTATIVA ───────────────────────────
                    StyledRect {
                        id: quotePane
                        Layout.fillWidth: true
                        variant: "pane"
                        radius: Styling.radius(6)
                        enableShadow: false
                        Layout.preferredHeight: 64

                        readonly property var quotes: [
                            "Focus is the new IQ.",
                            "Small steps every day.",
                            "Done is better than perfect.",
                            "Progress, not perfection.",
                            "Slow is smooth, smooth is fast.",
                            "Quality is the result of attention.",
                            "Start where you are. Use what you have.",
                            "Discipline is freedom.",
                            "The work is the reward.",
                            "Deep work beats shallow hustle."
                        ]
                        property int quoteIdx: 0

                        Timer {
                            interval: 25000
                            running: dock.isOpen && dock.currentTab === 2
                            repeat: true
                            onTriggered: quoteRotateAnim.start()
                        }

                        SequentialAnimation {
                            id: quoteRotateAnim
                            NumberAnimation { target: quoteText; property: "opacity"; to: 0; duration: 280 }
                            ScriptAction { script: quotePane.quoteIdx = (quotePane.quoteIdx + 1) % quotePane.quotes.length }
                            NumberAnimation { target: quoteText; property: "opacity"; to: 1; duration: 280 }
                        }

                        Text {
                            id: quoteText
                            anchors.centerIn: parent
                            width: parent.width - 32
                            text: '"' + quotePane.quotes[quotePane.quoteIdx] + '"'
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.italic: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }

                    Item { Layout.fillHeight: true } // spacer fin de tab Pomodoro
                } // ColumnLayout TAB 2 Pomodoro

                // ═══════ TAB 3: COLOR PICKER (immersive) ════════
                Item {
                    id: colorTab
                    Layout.fillWidth: true
                    implicitHeight: colorContent.implicitHeight + 24
                    Layout.preferredHeight: implicitHeight

                    readonly property color currentColor: hsvPicker.resultColor

                    // BACKGROUND: oscurecido del color elegido + glow blob central
                    Rectangle {
                        anchors.fill: parent
                        radius: Styling.radius(8)
                        clip: true
                        color: Qt.darker(colorTab.currentColor, 2.6)
                        Behavior on color { ColorAnimation { duration: 250 } }

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width
                            height: parent.width * 0.7
                            radius: width / 2
                            color: colorTab.currentColor
                            opacity: 0.18
                            Behavior on color { ColorAnimation { duration: 250 } }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.65
                            height: parent.width * 0.45
                            radius: width / 2
                            color: colorTab.currentColor
                            opacity: 0.30
                            Behavior on color { ColorAnimation { duration: 250 } }
                        }

                        Repeater {
                            model: 18
                            Rectangle {
                                required property int index
                                readonly property real startX: Math.random() * parent.width
                                width: 2 + Math.random() * 2
                                height: width
                                radius: width / 2
                                color: Qt.rgba(1, 1, 1, 0.5)
                                opacity: 0.6
                                x: startX
                                SequentialAnimation on y {
                                    loops: Animation.Infinite
                                    NumberAnimation {
                                        from: parent.height + 10; to: -10
                                        duration: 6000 + Math.random() * 4000
                                        easing.type: Easing.Linear
                                    }
                                }
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 0; to: 0.6; duration: 1500 }
                                    PauseAnimation { duration: 3000 }
                                    NumberAnimation { from: 0.6; to: 0; duration: 1500 }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        id: colorContent
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        // HERO: swatch + hex grande + rgb (click copia)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 110
                            color: Qt.rgba(0, 0, 0, 0.35)
                            radius: 14
                            border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
                            Row {
                                anchors.centerIn: parent
                                spacing: 18
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 64; height: 64; radius: 12
                                    color: colorTab.currentColor
                                    border.color: Qt.rgba(1, 1, 1, 0.3); border.width: 1
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        text: hsvPicker.hexValue.toUpperCase()
                                        color: "white"
                                        font.family: Config.theme.monoFont
                                        font.pixelSize: 32; font.weight: Font.Light
                                    }
                                    Text {
                                        text: {
                                            var c = colorTab.currentColor;
                                            return "rgb(" + Math.round(c.r * 255) + ", " +
                                                   Math.round(c.g * 255) + ", " +
                                                   Math.round(c.b * 255) + ")";
                                        }
                                        color: Qt.rgba(1, 1, 1, 0.6)
                                        font.family: Config.theme.monoFont
                                        font.pixelSize: Styling.fontSize(-1)
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Quickshell.execDetached(["wl-copy", hsvPicker.hexValue]);
                                    Quickshell.execDetached(["notify-send", "-t", "1500", "Color copied", hsvPicker.hexValue]);
                                }
                            }
                        }

                        // PICKER existente como child
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: pickerHolder.implicitHeight + 20
                            color: Qt.rgba(0, 0, 0, 0.32)
                            radius: 12
                            border.color: Qt.rgba(1, 1, 1, 0.10); border.width: 1
                            Item {
                                id: pickerHolder
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: parent.top; anchors.margins: 10
                                implicitHeight: hsvPicker.implicitHeight
                                ColorPicker {
                                    id: hsvPicker
                                    anchors.left: parent.left; anchors.right: parent.right
                                }
                            }
                        }

                        // FORMATS: HEX / RGB / HSL bidireccionales
                        Rectangle {
                            id: formatsCard
                            Layout.fillWidth: true
                            Layout.preferredHeight: formatsCol.implicitHeight + 20
                            color: Qt.rgba(0, 0, 0, 0.32)
                            radius: 12
                            border.color: Qt.rgba(1, 1, 1, 0.10); border.width: 1

                            function rgbToHex(r, g, b) {
                                var pad = function (n) { var s = Math.round(n).toString(16); return s.length < 2 ? "0" + s : s; };
                                return "#" + pad(r) + pad(g) + pad(b);
                            }
                            function parseRgb(s) {
                                var m = s.match(/(\d+)[,\s]+(\d+)[,\s]+(\d+)/);
                                if (!m) return null;
                                return [parseInt(m[1]), parseInt(m[2]), parseInt(m[3])];
                            }
                            function parseHsl(s) {
                                var m = s.match(/(\d+(?:\.\d+)?)[,\s]+(\d+(?:\.\d+)?)%?[,\s]+(\d+(?:\.\d+)?)%?/);
                                if (!m) return null;
                                return [parseFloat(m[1]), parseFloat(m[2]) / 100, parseFloat(m[3]) / 100];
                            }
                            function hslToRgb(h, s, l) {
                                h = h / 360;
                                var r, g, b;
                                if (s === 0) { r = g = b = l; }
                                else {
                                    var hue2rgb = function (p, q, t) {
                                        if (t < 0) t += 1; if (t > 1) t -= 1;
                                        if (t < 1/6) return p + (q - p) * 6 * t;
                                        if (t < 1/2) return q;
                                        if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
                                        return p;
                                    };
                                    var q = l < 0.5 ? l * (1 + s) : l + s - l * s;
                                    var p = 2 * l - q;
                                    r = hue2rgb(p, q, h + 1/3);
                                    g = hue2rgb(p, q, h);
                                    b = hue2rgb(p, q, h - 1/3);
                                }
                                return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255)];
                            }
                            function rgbToHsl(r, g, b) {
                                r /= 255; g /= 255; b /= 255;
                                var max = Math.max(r, g, b), min = Math.min(r, g, b);
                                var h = 0, s = 0, l = (max + min) / 2;
                                if (max !== min) {
                                    var d = max - min;
                                    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
                                    if (max === r) h = ((g - b) / d + (g < b ? 6 : 0));
                                    else if (max === g) h = (b - r) / d + 2;
                                    else h = (r - g) / d + 4;
                                    h *= 60;
                                }
                                return [Math.round(h), Math.round(s * 100), Math.round(l * 100)];
                            }

                            ColumnLayout {
                                id: formatsCol
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: parent.top; anchors.margins: 10
                                spacing: 6
                                Text {
                                    text: "Formats"
                                    color: Qt.rgba(1, 1, 1, 0.6)
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1); font.weight: Font.Medium
                                }
                                Repeater {
                                    model: ["HEX", "RGB", "HSL"]
                                    Row {
                                        Layout.fillWidth: true
                                        required property string modelData
                                        required property int index
                                        spacing: 8
                                        Text {
                                            text: modelData; color: Qt.rgba(1,1,1,0.55)
                                            font.family: Config.theme.monoFont
                                            font.pixelSize: Styling.fontSize(-1)
                                            anchors.verticalCenter: parent.verticalCenter; width: 38
                                        }
                                        Rectangle {
                                            width: formatsCard.width - 20 - 38 - 8
                                            height: 32; radius: 6
                                            color: Qt.rgba(1, 1, 1, 0.08)
                                            border.color: Qt.rgba(1, 1, 1, 0.15); border.width: 1
                                            TextInput {
                                                anchors.fill: parent; anchors.leftMargin: 10
                                                verticalAlignment: TextInput.AlignVCenter
                                                color: "white"
                                                font.family: Config.theme.monoFont
                                                font.pixelSize: Styling.fontSize(0)
                                                selectByMouse: true
                                                text: {
                                                    var c = colorTab.currentColor;
                                                    if (modelData === "HEX") return hsvPicker.hexValue.toUpperCase();
                                                    if (modelData === "RGB")
                                                        return Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " + Math.round(c.b * 255);
                                                    var hsl = formatsCard.rgbToHsl(c.r * 255, c.g * 255, c.b * 255);
                                                    return hsl[0] + ", " + hsl[1] + "%, " + hsl[2] + "%";
                                                }
                                                onEditingFinished: {
                                                    if (modelData === "HEX") {
                                                        hsvPicker.setFromHex(text);
                                                    } else if (modelData === "RGB") {
                                                        var rgb = formatsCard.parseRgb(text);
                                                        if (rgb) hsvPicker.setFromHex(formatsCard.rgbToHex(rgb[0], rgb[1], rgb[2]));
                                                    } else {
                                                        var hsl = formatsCard.parseHsl(text);
                                                        if (hsl) {
                                                            var rgb2 = formatsCard.hslToRgb(hsl[0], hsl[1], hsl[2]);
                                                            hsvPicker.setFromHex(formatsCard.rgbToHex(rgb2[0], rgb2[1], rgb2[2]));
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // HARMONIES: 5 swatches derivados
                        Rectangle {
                            id: harmoniesCard
                            Layout.fillWidth: true
                            Layout.preferredHeight: 96
                            color: Qt.rgba(0, 0, 0, 0.32)
                            radius: 12
                            border.color: Qt.rgba(1, 1, 1, 0.10); border.width: 1
                            Column {
                                anchors.fill: parent; anchors.margins: 10; spacing: 8
                                Text {
                                    text: "Harmonies"
                                    color: Qt.rgba(1, 1, 1, 0.6)
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1); font.weight: Font.Medium
                                }
                                Row {
                                    width: parent.width; spacing: 8
                                    Repeater {
                                        model: [
                                            { name: "comp",     hueOffset: 0.5 },
                                            { name: "analog 1", hueOffset: 0.0833 },
                                            { name: "analog 2", hueOffset: -0.0833 },
                                            { name: "triad 1",  hueOffset: 0.333 },
                                            { name: "triad 2",  hueOffset: 0.667 }
                                        ]
                                        Column {
                                            required property var modelData
                                            spacing: 3
                                            width: (harmoniesCard.width - 20 - 4 * 8) / 5
                                            Rectangle {
                                                width: parent.width; height: 38; radius: 8
                                                color: Qt.hsva((hsvPicker.hue + modelData.hueOffset + 1) % 1,
                                                               hsvPicker.sat, hsvPicker.val, 1)
                                                border.color: Qt.rgba(1, 1, 1, 0.18); border.width: 1
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: hsvPicker.setFromColor(parent.color)
                                                }
                                            }
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: modelData.name
                                                color: Qt.rgba(1, 1, 1, 0.5)
                                                font.family: Config.theme.font
                                                font.pixelSize: Styling.fontSize(-2)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ACTIONS: eyedropper + apply
                        Row {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 50
                            spacing: 8

                            Rectangle {
                                width: 50; height: 50; radius: 12
                                color: eyedropMouse.containsMouse ? Qt.rgba(1,1,1,0.18) : Qt.rgba(0,0,0,0.32)
                                border.color: Qt.rgba(1, 1, 1, 0.12); border.width: 1
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text { anchors.centerIn: parent; text: "💧"; font.pixelSize: 22 }
                                MouseArea {
                                    id: eyedropMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: eyedropProc.running = true
                                }
                                StyledToolTip {
                                    show: eyedropMouse.containsMouse
                                    tooltipText: "Pick color from screen (grim+slurp)"
                                }
                            }

                            Rectangle {
                                width: parent.width - 50 - 8; height: 50; radius: 12
                                color: applyMouse.containsMouse ? colorTab.currentColor : Qt.darker(colorTab.currentColor, 1.3)
                                border.color: Qt.rgba(1, 1, 1, 0.2); border.width: 1
                                Behavior on color { ColorAnimation { duration: 160 } }
                                Row {
                                    anchors.centerIn: parent; spacing: 10
                                    Text { text: "🎨"; font.pixelSize: 20; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: "Use as wallpaper accent"
                                        color: "white"
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(0); font.weight: Font.Bold
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                MouseArea {
                                    id: applyMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Quickshell.execDetached(["matugen", "color", "hex", hsvPicker.hexValue]);
                                        Quickshell.execDetached(["notify-send", "-t", "2000", "Accent applied", hsvPicker.hexValue]);
                                    }
                                }
                            }
                        }

                        // MATUGEN PALETTE
                        Rectangle {
                            id: paletteCard
                            Layout.fillWidth: true
                            Layout.preferredHeight: 84
                            color: Qt.rgba(0, 0, 0, 0.32)
                            radius: 12
                            border.color: Qt.rgba(1, 1, 1, 0.10); border.width: 1
                            Column {
                                anchors.fill: parent; anchors.margins: 10; spacing: 6
                                Text {
                                    text: "Matugen palette"
                                    color: Qt.rgba(1, 1, 1, 0.6)
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1); font.weight: Font.Medium
                                }
                                Row {
                                    spacing: 6
                                    Repeater {
                                        model: [
                                            { name: "primary",   c: Colors.primary },
                                            { name: "secondary", c: Colors.secondary },
                                            { name: "tertiary",  c: Colors.tertiary },
                                            { name: "error",     c: Colors.error },
                                            { name: "surface",   c: Colors.background },
                                            { name: "outline",   c: Colors.outline }
                                        ]
                                        Rectangle {
                                            required property var modelData
                                            width: (paletteCard.width - 20 - 5 * 6) / 6
                                            height: 36; radius: 8
                                            color: modelData.c
                                            border.color: Qt.rgba(1, 1, 1, 0.18); border.width: 1
                                            MouseArea {
                                                id: pmouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: hsvPicker.setFromColor(modelData.c)
                                            }
                                            StyledToolTip {
                                                show: pmouse.containsMouse
                                                tooltipText: modelData.name + ": " + modelData.c
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // RECENT
                        Rectangle {
                            id: recentCard
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? (recentCol.implicitHeight + 20) : 0
                            color: Qt.rgba(0, 0, 0, 0.32)
                            radius: 12
                            border.color: Qt.rgba(1, 1, 1, 0.10); border.width: 1
                            visible: colorHistory.colors.length > 0
                            QtObject {
                                id: colorHistory
                                property var colors: []
                                function add(hex) {
                                    if (!hex || hex === "") return;
                                    var filtered = colors.filter(function (c) { return c !== hex; });
                                    filtered.unshift(hex);
                                    if (filtered.length > 12) filtered = filtered.slice(0, 12);
                                    colors = filtered;
                                }
                            }
                            Timer {
                                id: histDebounce
                                interval: 1000; repeat: false
                                onTriggered: colorHistory.add(hsvPicker.hexValue)
                            }
                            Connections {
                                target: hsvPicker
                                function onHexValueChanged() { histDebounce.restart(); }
                            }
                            Column {
                                id: recentCol
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.top: parent.top; anchors.margins: 10
                                spacing: 6
                                Text {
                                    text: "Recent"
                                    color: Qt.rgba(1, 1, 1, 0.6)
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1); font.weight: Font.Medium
                                }
                                Flow {
                                    width: parent.width; spacing: 6
                                    Repeater {
                                        model: colorHistory.colors
                                        Rectangle {
                                            required property string modelData
                                            width: 30; height: 30; radius: 7
                                            color: modelData
                                            border.color: Qt.rgba(1, 1, 1, 0.2); border.width: 1
                                            MouseArea {
                                                id: rmouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: hsvPicker.setFromHex(parent.modelData)
                                            }
                                            StyledToolTip {
                                                show: rmouse.containsMouse
                                                tooltipText: parent.modelData
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Eyedropper: grim+slurp captura pixel y devuelve hex
                    Process {
                        id: eyedropProc
                        command: ["sh", "-c",
                            "grim -g \"$(slurp -p)\" -t ppm - | tail -c 3 | hexdump -e '\"#%02X%02X%02X\"'"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                var hex = this.text.trim();
                                if (hex.match(/^#[0-9A-F]{6}$/i)) {
                                    hsvPicker.setFromHex(hex);
                                }
                            }
                        }
                    }
                } // Item colorTab (TAB 3)
                } // StackLayout contentStack

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

    // Refetch weather al cambiar a la tab Weather si faltan los campos
    // nuevos (humidity/uv/wind direction/hourly) — la API expandida fue
    // agregada después, así que el cache previo no los tiene.
    onCurrentTabChanged: {
        if (currentTab === 1 && WeatherService.dataAvailable) {
            // Si humidity es 0 Y uvIndex es 0 Y hourly vacío, asumimos cache viejo
            if (WeatherService.humidity === 0 && WeatherService.uvIndex === 0 &&
                WeatherService.hourly.length === 0) {
                WeatherService.updateWeather();
            }
        }
    }
}
