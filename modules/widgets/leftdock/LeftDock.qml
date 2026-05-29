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
    readonly property int headerHeight: 120
    readonly property int shoulderSize: Config.roundness > 0 ? Config.roundness + 28 : 44

    // Tab activa: 0=Tech News, 1=CVEs, 2=Reddit
    property int currentTab: 0

    onCurrentTabChanged: {
        if (scroller.contentItem) {
            scroller.contentItem.contentY = 0
            Qt.callLater(() => {
                if (scroller.contentItem) {
                    scroller.contentItem.contentY = 0
                }
            })
        }
    }

    // Accent dinámico por tab — define el color del border + active pill
    readonly property color tabAccent: {
        switch (currentTab) {
            case 0: return Colors.primary;        // tech news → primary matugen
            case 1: return Colors.error;          // CVEs → error matugen (alerta)
            case 2: return Colors.tertiary;       // Reddit → tertiary matugen
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

    // Patrón mask: cerrado → click-through (null), abierto → fullMask con hombros de unión.
    mask: Region {
        regions: [
            Region { item: dock.isOpen ? fullMask : null },
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
                source: "file://" + Quickshell.env("HOME") + "/.cache/ambxst/images/header_bg.jpg"
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
                        radius: 0
                        color: "transparent"
                        border.color: dock.tabAccent
                        border.width: 1

                        Row {
                            id: liveRow
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                width: 6
                                height: 6
                                radius: 0
                                color: dock.tabAccent
                                anchors.verticalCenter: parent.verticalCenter

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    NumberAnimation { from: 1.0; to: 0.3; duration: 800; easing.type: Easing.InOutQuad }
                                    NumberAnimation { from: 0.3; to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                                }
                            }

                            Text {
                                text: "LIVE FEED"
                                color: Colors.overBackground
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
                            radius: 0
                            color: closeMouse.containsMouse ? Qt.rgba(dock.tabAccent.r, dock.tabAccent.g, dock.tabAccent.b, 0.22) : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: Icons.cancel
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: Colors.overBackground
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

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle { width: 5; Layout.preferredHeight: titleT.implicitHeight; color: dock.tabAccent }
                        Text {
                            id: titleT
                            text: "NEWS // SECURITY"
                            color: Colors.overBackground
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(3)
                            font.weight: Font.ExtraBold
                            font.letterSpacing: 1
                            Layout.fillWidth: true
                        }
                    }

                    Text {
                        text: "CURATED TECH & VULNERABILITY UPDATES"
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
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
                    { ico: Icons.globe },
                    { ico: Icons.shield },
                    { ico: Icons.reddit }
                ]

                Rectangle {
                    id: pill
                    required property var modelData
                    required property int index
                    readonly property bool isActive: dock.currentTab === index

                    width: 64
                    height: 40
                    radius: 0
                    color: isActive
                        ? dock.tabAccent
                        : (pillMouse.containsMouse ? Qt.rgba(dock.tabAccent.r, dock.tabAccent.g, dock.tabAccent.b, 0.15) : "transparent")
                    border.color: isActive ? dock.tabAccent : Colors.outline
                    border.width: 2
                    Behavior on color { ColorAnimation { duration: 220 } }
                    Behavior on border.color { ColorAnimation { duration: 220 } }

                    Text {
                        anchors.centerIn: parent
                        text: pill.modelData.ico
                        textFormat: Text.RichText
                        font.family: Icons.font
                        font.pixelSize: 18
                        color: pill.isActive ? Colors.background : Colors.overBackground
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
            bottomPadding: 24
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            NumberAnimation {
                id: scrollAnim
                target: scroller.contentItem
                property: "contentY"
                duration: 250
                easing.type: Easing.OutCubic
            }

            WheelHandler {
                target: scroller.contentItem
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    var flick = scroller.contentItem;
                    var scrollStep = event.angleDelta.y * 1.5;
                    var currentTarget = scrollAnim.running ? scrollAnim.to : flick.contentY;
                    var newTarget = Math.max(0, Math.min(flick.contentHeight - flick.height, currentTarget - scrollStep));
                    scrollAnim.stop();
                    scrollAnim.to = newTarget;
                    scrollAnim.start();
                    event.accepted = true;
                }
            }

            Column {
                id: contentStack
                x: 12
                width: scroller.width - 24
                spacing: 0

                    // Tab 0: Tech News
                    ColumnLayout {
                        id: techColumn
                        width: parent.width
                        spacing: 12
                        visible: dock.currentTab === 0

                        Loader {
                            Layout.fillWidth: true
                            active: NewsService.isLoadingNews || NewsService.newsFailed || NewsService.techNews.length === 0
                            visible: active
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
                        id: cveColumn
                        width: parent.width
                        spacing: 12
                        visible: dock.currentTab === 1

                        Loader {
                            Layout.fillWidth: true
                            active: NewsService.isLoadingCve || NewsService.cveFailed || NewsService.cveFeed.length === 0
                            visible: active
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
                                Layout.preferredHeight: cveCol.implicitHeight
                                variant: "internalbg"
                                radius: 0
                                enableShadow: false

                                property bool isHovered: false
                                function sevColor(s) {
                                    var v = ("" + s).toLowerCase();
                                    if (v.indexOf("crit") >= 0) return Colors.error;
                                    if (v.indexOf("high") >= 0) return Colors.tertiary;
                                    if (v.indexOf("med")  >= 0) return Colors.secondary;
                                    return Colors.outline; // low / desconocido
                                }
                                property color accent: sevColor(modelData.severity)

                                HoverHandler {
                                    onHoveredChanged: cveCard.isHovered = hovered
                                }

                                // Barra de severidad (matugen) a la izquierda
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: 4
                                    color: cveCard.accent
                                    z: 2
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    color: cveCard.accent
                                    opacity: cveCard.isHovered ? 0.08 : 0
                                    Behavior on opacity { NumberAnimation { duration: 150 } }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: cveCard.modelData.url ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (cveCard.modelData.url) {
                                            Qt.openUrlExternally(cveCard.modelData.url)
                                        }
                                    }
                                }

                                ColumnLayout {
                                    id: cveCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.leftMargin: 4
                                    spacing: 6

                                    // Fila superior: shield + severidad (CAPS) + score (mono grande)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 14
                                        Layout.rightMargin: 14
                                        Layout.topMargin: 12
                                        spacing: 8

                                        Text {
                                            text: Icons.shield
                                            font.family: Icons.font
                                            font.pixelSize: 16
                                            color: cveCard.accent
                                        }
                                        Text {
                                            text: ("" + cveCard.modelData.severity).toUpperCase()
                                            color: cveCard.accent
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-1)
                                            font.weight: Font.ExtraBold
                                            font.letterSpacing: 1.5
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: cveCard.modelData.score
                                            color: cveCard.accent
                                            font.family: Config.theme.monoFont
                                            font.pixelSize: Styling.fontSize(1)
                                            font.weight: Font.ExtraBold
                                        }
                                    }

                                    // CVE-ID (mono, bold)
                                    Text {
                                        text: cveCard.modelData.cve
                                        color: Colors.overBackground
                                        font.family: Config.theme.monoFont
                                        font.pixelSize: Styling.fontSize(0)
                                        font.weight: Font.Bold
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 14
                                        Layout.rightMargin: 14
                                    }

                                    // Intel de explotación: KEV / ransomware / PoC / EPSS
                                    Flow {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 14
                                        Layout.rightMargin: 14
                                        spacing: 6
                                        visible: cveCard.modelData.kev === true
                                                 || (cveCard.modelData.exploits || 0) > 0
                                                 || cveCard.modelData.ransomware === true
                                                 || ("" + (cveCard.modelData.epss || "")).length > 0

                                        // EXPLOITED (KEV) — explotación confirmada en el mundo real
                                        Rectangle {
                                            visible: cveCard.modelData.kev === true
                                            height: 18
                                            width: kevTxt.implicitWidth + 14
                                            radius: 3
                                            color: Qt.rgba(Colors.error.r, Colors.error.g, Colors.error.b, 0.16)
                                            border.width: 1
                                            border.color: Colors.error
                                            Text {
                                                id: kevTxt
                                                anchors.centerIn: parent
                                                text: "EXPLOITED"
                                                color: Colors.error
                                                font.family: Config.theme.monoFont
                                                font.pixelSize: Styling.monoFontSize(-2)
                                                font.weight: Font.Bold
                                                font.letterSpacing: 0.5
                                            }
                                        }

                                        // RANSOMWARE
                                        Rectangle {
                                            visible: cveCard.modelData.ransomware === true
                                            height: 18
                                            width: ransTxt.implicitWidth + 14
                                            radius: 3
                                            color: Qt.rgba(Colors.error.r, Colors.error.g, Colors.error.b, 0.16)
                                            border.width: 1
                                            border.color: Colors.error
                                            Text {
                                                id: ransTxt
                                                anchors.centerIn: parent
                                                text: "RANSOMWARE"
                                                color: Colors.error
                                                font.family: Config.theme.monoFont
                                                font.pixelSize: Styling.monoFontSize(-2)
                                                font.weight: Font.Bold
                                                font.letterSpacing: 0.5
                                            }
                                        }

                                        // Exploits / PoC públicos (VulnCheck) — clicable al exploit
                                        Rectangle {
                                            visible: (cveCard.modelData.exploits || 0) > 0
                                            height: 18
                                            width: pocTxt.implicitWidth + 14
                                            radius: 3
                                            color: Qt.rgba(Colors.tertiary.r, Colors.tertiary.g, Colors.tertiary.b, 0.16)
                                            border.width: 1
                                            border.color: Colors.tertiary
                                            Text {
                                                id: pocTxt
                                                anchors.centerIn: parent
                                                text: (cveCard.modelData.exploits || 0) + " PoC"
                                                color: Colors.tertiary
                                                font.family: Config.theme.monoFont
                                                font.pixelSize: Styling.monoFontSize(-2)
                                                font.weight: Font.Bold
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: ("" + (cveCard.modelData.exploitUrl || "")).length > 0
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Qt.openUrlExternally(cveCard.modelData.exploitUrl)
                                            }
                                        }

                                        // EPSS — probabilidad de explotación (próximos 30 días)
                                        Rectangle {
                                            visible: ("" + (cveCard.modelData.epss || "")).length > 0
                                            height: 18
                                            width: epssTxt.implicitWidth + 14
                                            radius: 3
                                            color: "transparent"
                                            border.width: 1
                                            border.color: Colors.outline
                                            Text {
                                                id: epssTxt
                                                anchors.centerIn: parent
                                                text: "EPSS " + cveCard.modelData.epss
                                                color: Colors.outline
                                                font.family: Config.theme.monoFont
                                                font.pixelSize: Styling.monoFontSize(-2)
                                            }
                                        }
                                    }

                                    // Descripción
                                    Text {
                                        text: cveCard.modelData.description
                                        color: Colors.outline
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 14
                                        Layout.rightMargin: 14
                                        Layout.bottomMargin: 14
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                        lineHeight: 1.2
                                    }
                                }
                            }
                        }
                    }

                    // Tab 2: Reddit Updates
                    ColumnLayout {
                        id: redditColumn
                        width: parent.width
                        spacing: 12
                        visible: dock.currentTab === 2

                        Loader {
                            Layout.fillWidth: true
                            active: NewsService.isLoadingReddit || NewsService.redditFailed || NewsService.redditFeed.length === 0
                            visible: active
                            sourceComponent: listStatusView
                            
                            property bool isLoading: NewsService.isLoadingReddit
                            property string statusText: NewsService.isLoadingReddit ? "Fetching Reddit posts..." : (NewsService.redditFailed ? "Failed to retrieve Reddit feed." : "No posts available.")
                            function onRetry() { NewsService.updateReddit() }
                        }

                        Repeater {
                            model: (!NewsService.isLoadingReddit && !NewsService.redditFailed) ? NewsService.redditFeed : []
                            delegate: newsCardDelegate
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
            Layout.preferredHeight: contentColumn.implicitHeight
            variant: "internalbg"
            radius: 0
            enableShadow: false

            property bool isHovered: false
            property color accent: dock.tabAccent

            HoverHandler {
                onHoveredChanged: cardRect.isHovered = hovered
            }

            // Barra de acento gruesa a la izquierda (brutalista)
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 4
                color: cardRect.accent
                opacity: cardRect.isHovered ? 1.0 : 0.85
                z: 2
            }
            // Resalte de bloque en hover
            Rectangle {
                anchors.fill: parent
                color: cardRect.accent
                opacity: cardRect.isHovered ? 0.08 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (cardRect.modelData.url) {
                        Qt.openUrlExternally(cardRect.modelData.url)
                    }
                }
            }

            ColumnLayout {
                id: contentColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 4   // deja ver la barra de acento
                spacing: 0

                // Imagen (bloque recto, sin máscara redondeada). Solo si hay imagen.
                Item {
                    id: imageArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: cardRect.modelData.image !== "" ? 150 : 0
                    visible: cardRect.modelData.image !== ""
                    clip: true

                    Image {
                        id: thumbImage
                        anchors.fill: parent
                        source: cardRect.modelData.image || ""
                        opacity: status === Image.Ready ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                    // Oscurecido inferior (legibilidad / look difuminado)
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.45; color: "transparent" }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
                        }
                    }
                }

                // Bloque de texto
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    Layout.topMargin: 12
                    Layout.bottomMargin: 14
                    spacing: 6

                    // Fuente / tag — ALL-CAPS bold con acento (brutalista)
                    Text {
                        text: (cardRect.modelData.tag + "  //  " + cardRect.modelData.source).toUpperCase()
                        color: cardRect.accent
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Título — extra bold fuerte
                    Text {
                        text: cardRect.modelData.title
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(1)
                        font.weight: Font.ExtraBold
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        lineHeight: 1.1
                    }

                    // Excerpt
                    Text {
                        text: cardRect.modelData.excerpt
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
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
                    radius: 0
                    color: retryMouse.containsMouse ? dock.tabAccent : "transparent"
                    border.color: dock.tabAccent
                    border.width: 2
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "RETRY"
                        color: retryMouse.containsMouse ? Colors.background : Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
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
