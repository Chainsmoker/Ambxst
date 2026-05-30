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
        right: true
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ambxst:leftdock"
    exclusionMode: ExclusionMode.Ignore

    readonly property bool isOpen: GlobalStates.newsPanelOpen
    // Siempre visible para permitir que la máscara hoverStrip reciba eventos del cursor cuando está cerrado.
    visible: true

    readonly property int dockWidth: 860
    readonly property int hPadding: 16
    readonly property int sectionSpacing: 12
    readonly property int headerHeight: 120
    readonly property int shoulderSize: Config.roundness > 0 ? Config.roundness + 28 : 44

    // Panel inferior tipo notch: alto fijo (todas las cards llevan imagen/placeholder).
    readonly property int panelHeight: Math.min(360, dock.height - dock.barReserved - 28)

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

    // Máscara: cerrado → click-through (null); abierto → cuerpo + hombros cóncavos al borde inferior.
    mask: Region {
        regions: [
            Region { item: dock.isOpen ? bodyMask : null },
            Region { item: dock.isOpen ? leftShoulderMask : null },
            Region { item: dock.isOpen ? rightShoulderMask : null }
        ]
    }
    Item {
        id: bodyMask
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: dock.dockWidth
        height: dock.panelHeight
    }
    Item {
        id: leftShoulderMask
        anchors.bottom: parent.bottom
        anchors.right: bodyMask.left
        width: dock.shoulderSize
        height: dock.shoulderSize
    }
    Item {
        id: rightShoulderMask
        anchors.bottom: parent.bottom
        anchors.left: bodyMask.right
        width: dock.shoulderSize
        height: dock.shoulderSize
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
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: dock.dockWidth
        height: dock.panelHeight
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

        // Sube desde el borde inferior.
        transform: Translate {
            id: slideTransform
            y: dock.isOpen ? 0 : dock.panelHeight + 40
            Behavior on y {
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

        // Cuerpo del panel — bg matugen, esquinas SUPERIORES redondeadas (notch inferior).
        StyledRect {
            id: dockBg
            anchors.fill: parent
            variant: "bg"
            enableShadow: true
            radius: 0
            topLeftRadius: Config.roundness > 0 ? Config.roundness + 8 : 0
            topRightRadius: Config.roundness > 0 ? Config.roundness + 8 : 0
            bottomLeftRadius: 0
            bottomRightRadius: 0
            clip: true
        }

        // Tabs abajo, centrados
        Row {
            id: tabPills
            anchors.bottom: dockBg.bottom
            anchors.horizontalCenter: dockBg.horizontalCenter
            anchors.bottomMargin: 12
            spacing: 8
            z: 120

            Repeater {
                model: [
                    { ico: Icons.globe, label: "News", accent: Colors.primary },
                    { ico: Icons.shield, label: "CVEs", accent: Colors.error },
                    { ico: Icons.reddit, label: "Reddit", accent: Colors.tertiary }
                ]

                Rectangle {
                    id: pill
                    required property var modelData
                    required property int index
                    readonly property bool isActive: dock.currentTab === index
                    height: 38
                    width: pillRow.implicitWidth + 30
                    radius: height / 2
                    color: pill.isActive ? pill.modelData.accent : (pillMouse.containsMouse ? Colors.surfaceContainerHigh : Colors.surfaceContainer)
                    Behavior on color { ColorAnimation { duration: 180 } }

                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: pill.modelData.ico
                            textFormat: Text.RichText
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: pill.isActive ? Colors.background : Colors.overBackground
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: pill.modelData.label
                            font.family: Config.theme.font
                            font.capitalization: Font.Capitalize
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Bold
                            color: pill.isActive ? Colors.background : Colors.overBackground
                            anchors.verticalCenter: parent.verticalCenter
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

        // Hombro cóncavo inferior-izquierdo (funde el cuerpo con el borde de abajo).
        Item {
            id: leftShoulder
            width: dock.shoulderSize
            height: dock.shoulderSize
            anchors.bottom: dockBg.bottom
            anchors.right: dockBg.left

            RoundCorner {
                anchors.fill: parent
                corner: RoundCorner.CornerEnum.BottomRight
                size: dock.shoulderSize
                color: dockBg.color
                Behavior on color { ColorAnimation { duration: 700 } }
            }
        }

        // Hombro cóncavo inferior-derecho.
        Item {
            id: rightShoulder
            width: dock.shoulderSize
            height: dock.shoulderSize
            anchors.bottom: dockBg.bottom
            anchors.left: dockBg.right

            RoundCorner {
                anchors.fill: parent
                corner: RoundCorner.CornerEnum.BottomLeft
                size: dock.shoulderSize
                color: dockBg.color
                Behavior on color { ColorAnimation { duration: 700 } }
            }
        }

        // Feed: una sola fila horizontal por tab (scroll con rueda o arrastrar).
        Item {
            id: feedArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: dock.hPadding
            anchors.rightMargin: dock.hPadding
            anchors.top: dockBg.top
            anchors.topMargin: 26
            anchors.bottom: tabPills.top
            anchors.bottomMargin: 12

            // Tab 0: Tech News
            ListView {
                id: techList
                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: 12
                clip: true
                visible: dock.currentTab === 0
                boundsBehavior: Flickable.StopAtBounds
                model: (!NewsService.isLoadingNews && !NewsService.newsFailed) ? NewsService.techNews : []
                delegate: newsCardDelegate
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: e => { techList.contentX = Math.max(0, Math.min(Math.max(0, techList.contentWidth - techList.width), techList.contentX - e.angleDelta.y)); e.accepted = true; }
                }
            }
            Loader {
                anchors.centerIn: parent
                active: dock.currentTab === 0 && (NewsService.isLoadingNews || NewsService.newsFailed || NewsService.techNews.length === 0)
                visible: active
                sourceComponent: listStatusView
                property bool isLoading: NewsService.isLoadingNews
                property string statusText: NewsService.isLoadingNews ? "Fetching latest news..." : (NewsService.newsFailed ? "Failed to retrieve news feed." : "No articles available.")
                function onRetry() { NewsService.updateNews() }
            }

            // Tab 1: Latest CVEs
            ListView {
                id: cveList
                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: 12
                clip: true
                visible: dock.currentTab === 1
                boundsBehavior: Flickable.StopAtBounds
                model: (!NewsService.isLoadingCve && !NewsService.cveFailed) ? NewsService.cveFeed : []
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: e => { cveList.contentX = Math.max(0, Math.min(Math.max(0, cveList.contentWidth - cveList.width), cveList.contentX - e.angleDelta.y)); e.accepted = true; }
                }
                delegate: StyledRect {
                                id: cveCard
                                required property var modelData
                                required property int index
                                width: 320
                                height: ListView.view ? ListView.view.height : 280
                                variant: "internalbg"
                                radius: Styling.radius(-4)
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
                                    spacing: 6

                                    // Banner placeholder con acento por severidad
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 110
                                        clip: true
                                        Rectangle {
                                            anchors.fill: parent
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0; color: Qt.rgba(cveCard.accent.r, cveCard.accent.g, cveCard.accent.b, 0.30) }
                                                GradientStop { position: 1.0; color: Qt.rgba(cveCard.accent.r, cveCard.accent.g, cveCard.accent.b, 0.08) }
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                text: Icons.shield
                                                textFormat: Text.RichText
                                                font.family: Icons.font
                                                font.pixelSize: 44
                                                color: Qt.rgba(cveCard.accent.r, cveCard.accent.g, cveCard.accent.b, 0.55)
                                            }
                                        }
                                    }

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
            Loader {
                anchors.centerIn: parent
                active: dock.currentTab === 1 && (NewsService.isLoadingCve || NewsService.cveFailed || NewsService.cveFeed.length === 0)
                visible: active
                sourceComponent: listStatusView
                property bool isLoading: NewsService.isLoadingCve
                property string statusText: NewsService.isLoadingCve ? "Scanning vulnerability databases..." : (NewsService.cveFailed ? "Failed to retrieve vulnerabilities." : "No CVE reports available.")
                function onRetry() { NewsService.updateCve() }
            }

            // Tab 2: Reddit Updates
            ListView {
                id: redditList
                anchors.fill: parent
                orientation: ListView.Horizontal
                spacing: 12
                clip: true
                visible: dock.currentTab === 2
                boundsBehavior: Flickable.StopAtBounds
                model: (!NewsService.isLoadingReddit && !NewsService.redditFailed) ? NewsService.redditFeed : []
                delegate: newsCardDelegate
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: e => { redditList.contentX = Math.max(0, Math.min(Math.max(0, redditList.contentWidth - redditList.width), redditList.contentX - e.angleDelta.y)); e.accepted = true; }
                }
            }
            Loader {
                anchors.centerIn: parent
                active: dock.currentTab === 2 && (NewsService.isLoadingReddit || NewsService.redditFailed || NewsService.redditFeed.length === 0)
                visible: active
                sourceComponent: listStatusView
                property bool isLoading: NewsService.isLoadingReddit
                property string statusText: NewsService.isLoadingReddit ? "Fetching Reddit posts..." : (NewsService.redditFailed ? "Failed to retrieve Reddit feed." : "No posts available.")
                function onRetry() { NewsService.updateReddit() }
            }
        }
    }

    Component {
        id: newsCardDelegate
        StyledRect {
            id: cardRect
            required property var modelData
            required property int index
            width: 300
            height: ListView.view ? ListView.view.height : 280
            variant: "internalbg"
            radius: Styling.radius(-4)
            enableShadow: false

            property bool isHovered: false
            property color accent: dock.tabAccent

            HoverHandler {
                onHoveredChanged: cardRect.isHovered = hovered
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
                spacing: 0

                // Imagen (siempre 150; placeholder con acento si el item no trae imagen)
                Item {
                    id: imageArea
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    clip: true

                    // Placeholder: gradiente con el acento + icono grande tenue
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(cardRect.accent.r, cardRect.accent.g, cardRect.accent.b, 0.28) }
                            GradientStop { position: 1.0; color: Qt.rgba(cardRect.accent.r, cardRect.accent.g, cardRect.accent.b, 0.08) }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: dock.currentTab === 2 ? Icons.reddit : Icons.globe
                            textFormat: Text.RichText
                            font.family: Icons.font
                            font.pixelSize: 46
                            color: Qt.rgba(cardRect.accent.r, cardRect.accent.g, cardRect.accent.b, 0.55)
                        }
                    }

                    Image {
                        id: thumbImage
                        anchors.fill: parent
                        source: cardRect.modelData.image || ""
                        opacity: status === Image.Ready ? 1.0 : 0.0
                        visible: cardRect.modelData.image !== ""
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
