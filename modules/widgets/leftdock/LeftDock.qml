pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
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
    // Siempre visible para permitir que la máscara hoverStrip reciba eventos del cursor cuando está cerrado.
    visible: true

    readonly property int dockWidth: 420
    readonly property int hPadding: 16
    readonly property int sectionSpacing: 12
    readonly property int headerHeight: 160
    readonly property int shoulderSize: Config.roundness > 0 ? Config.roundness + 28 : 44

    // Tab activa: 0=Tech News, 1=CVEs, 2=Redis
    property int currentTab: 0

    // Accent dinámico por tab — define el color del border + active pill
    readonly property color tabAccent: {
        switch (currentTab) {
            case 0: return Colors.primary;        // tech news: matugen primary
            case 1: return "#E07556";             // CVEs: Alert orange/tomato
            case 2: return "#E05638";             // Redis: Red
        }
        return Colors.primary;
    }

    readonly property bool barAtTop: {
        const pos = Config.bar?.position ?? "top";
        return pos === "top";
    }

    readonly property int barReserved: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "top" ? base : 0;
    }

    implicitWidth: dockWidth + dock.shoulderSize + 8

    // Patrón mask: cerrado → hoverStrip, abierto → fullMask con hombros de unión.
    mask: Region {
        regions: [
            Region { item: dock.isOpen ? fullMask : hoverStrip },
            Region { item: (dock.isOpen && (!dock.barAtTop || Config.showBackground)) ? topRightShoulder : null },
            Region { item: (dock.isOpen && !dock.barAtTop && Config.showBackground) ? bottomRightShoulder : null }
        ]
    }
    Item {
        id: fullMask
        x: 0
        y: dock.barReserved
        width: dock.dockWidth
        height: dock.height - dock.barReserved
    }
    Item {
        id: hoverStrip
        x: 0
        y: dock.barReserved
        width: 10
        height: dock.height - dock.barReserved
    }

    // Gatillo de hover lateral en el borde izquierdo
    Item {
        id: hoverTrigger
        x: 0
        y: dock.barReserved
        width: 10
        height: dock.height - dock.barReserved
        visible: !dock.isOpen

        HoverHandler {
            onHoveredChanged: {
                if (hovered && !dock.isOpen) {
                    GlobalStates.newsPanelOpen = true;
                }
            }
        }
    }

    // Temporizador para auto-cerrar el panel tras 600ms de inactividad del cursor
    Timer {
        id: closeTimer
        interval: 600
        repeat: false
        onTriggered: {
            GlobalStates.newsPanelOpen = false;
        }
    }

    readonly property int dockContainerWidth: dock.dockWidth

    // Live feeds are managed and loaded via NewsService

    Item {
        id: dockContainer
        width: dock.dockContainerWidth
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: dock.barReserved
        anchors.bottom: parent.bottom
        opacity: dock.isOpen ? 1 : 0
        visible: opacity > 0.001

        HoverHandler {
            id: dockHoverHandler
            onHoveredChanged: {
                if (!hovered && dock.isOpen) {
                    closeTimer.restart();
                } else {
                    closeTimer.stop();
                }
            }
        }

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
            topRightRadius: 0
            bottomRightRadius: 0
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

            // Dynamic header background image
            Image {
                anchors.fill: parent
                source: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=600&auto=format&fit=crop&q=80"
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: 0.45
            }

            // Dark tint layer
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.35)
            }

            // Seamless gradient transition to widget bg
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: dockBg.color }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: dock.hPadding
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true

                    // Live Feed Indicator
                    Rectangle {
                        id: liveBadge
                        height: 22
                        width: liveRow.implicitWidth + 16
                        radius: 11
                        color: Qt.rgba(1, 1, 1, 0.12)
                        border.color: Qt.rgba(1, 1, 1, 0.2)
                        border.width: 1

                        Row {
                            id: liveRow
                            anchors.centerIn: parent
                            spacing: 6
                            
                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: "#2ecc71"
                                anchors.verticalCenter: parent.verticalCenter
                                
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1.0; to: 0.3; duration: 800; easing.type: Easing.InOutQuad }
                                    NumberAnimation { from: 0.3; to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                                }
                            }

                            Text {
                                text: "LIVE FEED"
                                color: "white"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.weight: Font.Bold
                                font.letterSpacing: 1
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
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
                            color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: Icons.cancel
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: "white"
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

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "News & Security"
                        color: "white"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(3)
                        font.weight: Font.ExtraBold
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Your curated tech and vulnerability updates"
                        color: Qt.rgba(255, 255, 255, 0.8)
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        // Hombro cóncavo top-right del dock body (solo si bar está arriba).
        Item {
            id: topRightShoulder
            width: dock.shoulderSize
            height: dock.shoulderSize
            anchors.top: dockBg.top
            anchors.left: dockBg.right
            visible: !dock.barAtTop || Config.showBackground

            RoundCorner {
                anchors.fill: parent
                corner: RoundCorner.CornerEnum.TopLeft
                size: dock.shoulderSize
                color: dockBg.color
                Behavior on color { ColorAnimation { duration: 700 } }
            }
        }

        // Hombro cóncavo bottom-right del dock body (solo si bar está abajo).
        Item {
            id: bottomRightShoulder
            width: dock.shoulderSize
            height: dock.shoulderSize
            anchors.bottom: dockBg.bottom
            anchors.left: dockBg.right
            visible: !dock.barAtTop && Config.showBackground

            RoundCorner {
                anchors.fill: parent
                corner: RoundCorner.CornerEnum.BottomLeft
                size: dock.shoulderSize
                color: dockBg.color
                Behavior on color { ColorAnimation { duration: 700 } }
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
                    { ico: Icons.globe, name: "Tech" },
                    { ico: Icons.shield, name: "CVEs" },
                    { ico: Icons.cube, name: "Redis" }
                ]

                Rectangle {
                    id: pill
                    required property var modelData
                    required property int index
                    readonly property bool isActive: dock.currentTab === index

                    width: 120
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

                    // Tab 0: Tech News
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Loader {
                            Layout.fillWidth: true
                            active: NewsService.isLoadingNews || NewsService.newsFailed || NewsService.techNews.length === 0
                            sourceComponent: listStatusView
                            
                            property bool isLoading: NewsService.isLoadingNews
                            property string statusText: NewsService.isLoadingNews ? "Fetching latest news..." : (NewsService.newsFailed ? "Failed to retrieve news feed." : "No articles available.")
                            function onRetry() { NewsService.updateNews() }
                        }

                        Repeater {
                            model: (!NewsService.isLoadingNews && !NewsService.newsFailed) ? NewsService.techNews : []
                            delegate: newsCardDelegate
                        }
                    }

                    // Tab 1: Latest CVEs
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Loader {
                            Layout.fillWidth: true
                            active: NewsService.isLoadingCve || NewsService.cveFailed || NewsService.cveFeed.length === 0
                            sourceComponent: listStatusView
                            
                            property bool isLoading: NewsService.isLoadingCve
                            property string statusText: NewsService.isLoadingCve ? "Scanning vulnerability databases..." : (NewsService.cveFailed ? "Failed to retrieve vulnerabilities." : "No CVE reports available.")
                            function onRetry() { NewsService.updateCve() }
                        }

                        Repeater {
                            model: (!NewsService.isLoadingCve && !NewsService.cveFailed) ? NewsService.cveFeed : []

                            delegate: StyledRect {
                                id: cveCard
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredHeight: cveCol.implicitHeight + 16
                                variant: "internalbg"
                                radius: 16
                                enableShadow: false

                                property bool isHovered: false
                                scale: isHovered ? 1.02 : 1.0
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                                HoverHandler {
                                    onHoveredChanged: cveCard.isHovered = hovered
                                }

                                ColumnLayout {
                                    id: cveCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: 0

                                    // Top Section: Severity Gradient & Shield
                                    Item {
                                        id: cveHeaderArea
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 120
                                        clip: true

                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: cveMaskShape
                                        }

                                        Item {
                                            id: cveMaskShape
                                            anchors.fill: parent
                                            visible: false
                                            Rectangle {
                                                anchors.fill: parent
                                                topLeftRadius: 16
                                                topRightRadius: 16
                                                bottomLeftRadius: 0
                                                bottomRightRadius: 0
                                                color: "black"
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: cveCard.modelData.color }
                                                GradientStop { position: 1.0; color: Qt.darker(cveCard.modelData.color, 1.8) }
                                            }

                                            Rectangle {
                                                width: 80
                                                height: 80
                                                radius: 40
                                                color: Qt.rgba(1, 1, 1, 0.08)
                                                x: parent.width - 40
                                                y: -20
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: Icons.shield
                                                color: Qt.rgba(1, 1, 1, 0.9)
                                                font.family: Icons.font
                                                font.pixelSize: 48
                                                
                                                scale: cveCard.isHovered ? 1.1 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
                                            }
                                        }

                                        // Floating severity badge
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.margins: 12
                                            height: 24
                                            width: sevText.implicitWidth + 16
                                            radius: 12
                                            color: Qt.rgba(0, 0, 0, 0.6)
                                            border.color: Qt.rgba(1, 1, 1, 0.2)
                                            border.width: 1

                                            Text {
                                                id: sevText
                                                anchors.centerIn: parent
                                                text: cveCard.modelData.severity + " (" + cveCard.modelData.score + ")"
                                                color: "white"
                                                font.family: Config.theme.font
                                                font.pixelSize: Styling.fontSize(-2)
                                                font.weight: Font.Bold
                                            }
                                        }
                                    }

                                    // Bottom Section: Info and Text
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.margins: 16
                                        spacing: 8

                                        Text {
                                            text: cveCard.modelData.cve
                                            color: Colors.overBackground
                                            font.family: Config.theme.monoFont
                                            font.pixelSize: Styling.fontSize(0)
                                            font.weight: Font.Bold
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: cveCard.modelData.description
                                            color: Colors.outline
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-1)
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            opacity: 0.85
                                            lineHeight: 1.2
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Tab 2: Redis Updates
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Loader {
                            Layout.fillWidth: true
                            active: NewsService.isLoadingRedis || NewsService.redisFailed || NewsService.redisFeed.length === 0
                            sourceComponent: listStatusView
                            
                            property bool isLoading: NewsService.isLoadingRedis
                            property string statusText: NewsService.isLoadingRedis ? "Fetching Redis news..." : (NewsService.redisFailed ? "Failed to retrieve Redis updates." : "No updates available.")
                            function onRetry() { NewsService.updateRedis() }
                        }

                        Repeater {
                            model: (!NewsService.isLoadingRedis && !NewsService.redisFailed) ? NewsService.redisFeed : []
                            delegate: newsCardDelegate
                        }
                    }
                }
            }
        }
    }

    Component {
        id: newsCardDelegate
        StyledRect {
            id: cardRect
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Layout.preferredHeight: contentColumn.implicitHeight + 16
            variant: "internalbg"
            radius: 16
            enableShadow: false

            property bool isHovered: false
            scale: isHovered ? 1.02 : 1.0
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

            HoverHandler {
                onHoveredChanged: cardRect.isHovered = hovered
            }

            ColumnLayout {
                id: contentColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: 0

                // Top Section: Image or Fallback
                Item {
                    id: imageArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: 180
                    clip: true

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: imageMaskShape
                    }

                    Item {
                        id: imageMaskShape
                        anchors.fill: parent
                        visible: false
                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: 16
                            topRightRadius: 16
                            bottomLeftRadius: 0
                            bottomRightRadius: 0
                            color: "black"
                        }
                    }

                    // Fallback Bg
                    Rectangle {
                        id: fallbackBg
                        anchors.fill: parent
                        visible: !thumbImage.visible
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: cardRect.modelData.tagColor }
                            GradientStop { position: 1.0; color: Qt.darker(cardRect.modelData.tagColor, 1.8) }
                        }

                        Rectangle {
                            width: 120
                            height: 120
                            radius: 60
                            color: Qt.rgba(1, 1, 1, 0.1)
                            x: parent.width - 60
                            y: -30
                        }

                        Text {
                            anchors.centerIn: parent
                            text: cardRect.modelData.tag
                            color: Qt.rgba(1, 1, 1, 0.9)
                            font.family: Config.theme.font
                            font.pixelSize: 36
                            font.weight: Font.Bold
                            font.letterSpacing: 2
                        }
                    }

                    // Actual Image
                    Image {
                        id: thumbImage
                        anchors.fill: parent
                        source: cardRect.modelData.image || ""
                        visible: cardRect.modelData.image !== "" && status === Image.Ready
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true

                        scale: cardRect.isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
                    }

                    // Floating tag badge
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 12
                        height: 24
                        width: tagText.implicitWidth + 16
                        radius: 12
                        color: Qt.rgba(0, 0, 0, 0.6)
                        border.color: Qt.rgba(1, 1, 1, 0.2)
                        border.width: 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 4
                            Rectangle {
                                width: 6
                                height: 6
                                radius: 3
                                color: cardRect.modelData.tagColor
                            }
                            Text {
                                id: tagText
                                text: cardRect.modelData.tag
                                color: "white"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                font.weight: Font.Bold
                            }
                        }
                    }
                }

                // Bottom Section: Info and Text
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    spacing: 8

                    Text {
                        text: cardRect.modelData.source
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        opacity: 0.8
                    }

                    Text {
                        text: cardRect.modelData.title
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        font.weight: Font.Bold
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        lineHeight: 1.15
                    }

                    Text {
                        text: cardRect.modelData.excerpt
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        opacity: 0.85
                        lineHeight: 1.2
                    }
                }
            }
        }
    }

    Component {
        id: listStatusView
        Item {
            id: statusRoot
            readonly property string statusText: parent.statusText
            readonly property bool isLoading: parent.isLoading

            implicitWidth: parent.width
            implicitHeight: 300

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 16
                width: parent.width - 32

                Text {
                    id: iconText
                    Layout.alignment: Qt.AlignHCenter
                    text: statusRoot.isLoading ? Icons.circleNotch : Icons.alert
                    font.family: Icons.font
                    font.pixelSize: 36
                    color: dock.tabAccent

                    RotationAnimator {
                        target: iconText
                        running: statusRoot.isLoading
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1200
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: statusRoot.statusText
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    color: Colors.outline
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Rectangle {
                    visible: !statusRoot.isLoading
                    Layout.alignment: Qt.AlignHCenter
                    width: 110
                    height: 36
                    radius: 12
                    color: retryMouse.containsMouse ? dock.tabAccent : Qt.rgba(1, 1, 1, 0.1)
                    border.color: Qt.rgba(1, 1, 1, 0.2)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Retry"
                        color: "white"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Bold
                    }

                    MouseArea {
                        id: retryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: statusRoot.parent.onRetry()
                    }
                }
            }
        }
    }
}
