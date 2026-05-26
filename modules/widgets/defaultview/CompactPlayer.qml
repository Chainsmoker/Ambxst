import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.modules.theme
import qs.modules.bar.workspaces
import qs.modules.services
import qs.modules.components
import qs.config

Item {
    id: compactPlayer

    required property var player
    required property bool notchHovered

    // Mostrar el reproductor cuando HAY reproducción activa (no solo player existente).
    // Si está pausado o sin player → vuelve al texto. Hover sigue funcionando.
    readonly property bool playerExpanded: compactPlayer.isPlaying || compactPlayer.notchHovered

    onPlayerChanged: {
    }

    property bool isPlaying: player?.playbackState === MprisPlaybackState.Playing
    property real position: player?.position ?? 0.0
    property real length: player?.length ?? 1.0
    property bool hasArtwork: (player?.trackArtUrl ?? "") !== ""
    property string wallpaperPath: {
        if (!GlobalStates.wallpaperManager) return "";
        let path = GlobalStates.wallpaperManager.currentWallpaper;
        let frame = GlobalStates.wallpaperManager.getLockscreenFramePath(path);
        return frame ? "file://" + frame : "";
    }

    readonly property string focusedTitle: {
        const activeWsId = AxctlService.focusedMonitor?.activeWorkspace?.id;
        if (!activeWsId) return "";
        const windows = CompositorData.workspaceWindowsMap[activeWsId] || [];
        if (windows.length === 0) return "";
        const best = windows.reduce((best, win) => {
            const bestFocus = best?.focusHistoryID ?? Infinity;
            const winFocus = win?.focusHistoryID ?? Infinity;
            return winFocus < bestFocus ? win : best;
        }, null);
        return best ? best.title : "";
    }

    property string hostname: ""

    Process {
        id: hostnameReader
        running: true
        command: ["hostname"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const host = text.trim();
                if (host) {
                    compactPlayer.hostname = host;
                }
            }
        }
    }

    readonly property string userHostText: {
        const user = Quickshell.env("USER") || "user";
        const host = hostname || "host";
        return user + "@" + host;
    }

    readonly property string noMediaText: {
        const displayType = Config.notch.noMediaDisplay ?? "userHost";
        if (displayType === "userHost") return userHostText;
        if (displayType === "compositor") return "AxctlService";
        return Config.notch.customText ?? "Ambxst";
    }

    readonly property string displayedTitle: {
        // Solo usar metadata del player si tiene un trackTitle real
        // (caso típico: Brave pausado expone player pero sin trackTitle → "Unknown")
        if (player && player.trackTitle) {
            return (player.trackArtist ? player.trackArtist + " - " : "") + player.trackTitle;
        }
        return focusedTitle || noMediaText;
    }

    function getPlayerIcon(player) {
        if (!player)
            return Icons.player;
        const dbusName = (player.dbusName || "").toLowerCase();
        const desktopEntry = (player.desktopEntry || "").toLowerCase();
        const identity = (player.identity || "").toLowerCase();
        if (dbusName.includes("spotify") || desktopEntry.includes("spotify") || identity.includes("spotify"))
            return Icons.spotify;
        if (dbusName.includes("chromium") || dbusName.includes("chrome") || dbusName.includes("brave")
            || desktopEntry.includes("chromium") || desktopEntry.includes("chrome") || desktopEntry.includes("brave")
            || identity.includes("brave"))
            return Icons.chromium;
        if (dbusName.includes("firefox") || desktopEntry.includes("firefox"))
            return Icons.firefox;
        if (dbusName.includes("telegram") || desktopEntry.includes("telegram") || identity.includes("telegram"))
            return Icons.telegram;
        return Icons.player;
    }



    StyledRect {
        variant: "common"
        anchors.fill: parent
        radius: Styling.radius(-4)

        Text {
            id: mediaTitle
            anchors.centerIn: parent
            width: parent.width - 32
            text: compactPlayer.displayedTitle
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(0)
            font.bold: true
            color: Colors.overBackground
            elide: Text.ElideRight
            visible: opacity > 0
            opacity: (compactPlayer.playerExpanded && compactPlayer.player) ? 0.0 : 1.0
            horizontalAlignment: Text.AlignHCenter
            z: 5

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutQuart
                }
            }
        }

        ClippingRectangle {
            anchors.fill: parent
            radius: Styling.radius(-4)
            color: "transparent"

            Image {
                mipmap: true
                id: backgroundArt
                anchors.fill: parent
                source: (compactPlayer.player?.trackArtUrl ?? "") !== "" ? compactPlayer.player.trackArtUrl : compactPlayer.wallpaperPath
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }

            MultiEffect {
                anchors.fill: backgroundArt
                source: backgroundArt
                // Solo mostrar el blur cuando el player está expandido (playing/hover).
                // Si está en modo "texto" no queremos ver el favicon de Brave o lo que sea.
                blurEnabled: (hasArtwork || wallpaperPath !== "") && compactPlayer.playerExpanded
                blurMax: 32
                blur: 0.75
                autoPaddingEnabled: false
                opacity: ((hasArtwork || wallpaperPath !== "") && compactPlayer.playerExpanded) ? 1.0 : 0.0
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
            }

            StyledRect {
                anchors.fill: parent
                variant: "internalbg"
                opacity: ((hasArtwork || wallpaperPath !== "") && compactPlayer.playerExpanded) ? 0.5 : 0.0
                radius: Styling.radius(-4)
                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: (compactPlayer.player !== null || compactPlayer.playerExpanded) ? 4 : 0
            anchors.rightMargin: (compactPlayer.player !== null || compactPlayer.playerExpanded) ? 4 : 0
            spacing: (compactPlayer.player !== null && compactPlayer.playerExpanded) ? 4 : 0
            layer.enabled: true
            layer.effect: BgShadow {}
            opacity: (compactPlayer.playerExpanded && compactPlayer.player) ? 1.0 : 0.0
            visible: opacity > 0
            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutQuart
                }
            }
            Behavior on spacing {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration
                    easing.type: Easing.OutQuart
                }
            }

            Item {
                id: artworkContainer
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                visible: compactPlayer.playerExpanded
                ClippingRectangle {
                    anchors.fill: parent
                    radius: compactPlayer.isPlaying ? Styling.radius(-8) : Styling.radius(-4)
                    color: "transparent"
                    Image {
                        mipmap: true
                        id: artworkImage
                        anchors.fill: parent
                        source: (compactPlayer.player?.trackArtUrl ?? "") !== "" ? compactPlayer.player.trackArtUrl : compactPlayer.wallpaperPath
                        sourceSize: Qt.size(48, 48)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: artworkImage
                        // Only enable blur when there's content to blur (saves GPU)
                        blurEnabled: (hasArtwork || wallpaperPath !== "") && compactPlayer.playerExpanded
                        blurMax: 32
                        blur: 0.75
                        opacity: (hasArtwork || wallpaperPath !== "") ? 1.0 : 0.0 // Simplificado
                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }
                    }

                    StyledRect {
                        anchors.fill: parent
                        variant: "internalbg"
                        opacity: ((hasArtwork || wallpaperPath !== "") && compactPlayer.playerExpanded) ? 0.5 : 0.0
                        radius: parent.radius
                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }
                    }

                    Text {
                        id: playPauseBtn
                        anchors.centerIn: parent
                        text: compactPlayer.isPlaying ? Icons.pause : Icons.play
                        textFormat: Text.RichText
                        color: playPauseHover.hovered ? ((hasArtwork || wallpaperPath !== "") ? Styling.srItem("overprimary") : Styling.srItem("overprimary")) : ((hasArtwork || wallpaperPath !== "") ? Colors.overBackground : Colors.overBackground)
                        font.pixelSize: 16
                        font.family: Icons.font
                        opacity: (compactPlayer.player?.canPause ?? false) && compactPlayer.playerExpanded ? 1.0 : 0.0
                        scale: 1.0
                        layer.enabled: true
                        layer.effect: BgShadow {}
                        visible: opacity > 0
                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }
                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutQuart
                            }
                        }
                        Behavior on scale {
                            enabled: Config.animDuration > 0
                            NumberAnimation {
                                duration: Config.animDuration
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.5
                            }
                        }
                        HoverHandler {
                            id: playPauseHover
                            enabled: compactPlayer.player !== null && compactPlayer.playerExpanded
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: compactPlayer.player ? Qt.PointingHandCursor : Qt.ArrowCursor
                            enabled: compactPlayer.player !== null && compactPlayer.playerExpanded
                            onClicked: {
                                playPauseBtn.scale = 1.1;
                                compactPlayer.player?.togglePlaying();
                                playPauseScaleTimer.restart();
                            }
                        }
                        Timer {
                            id: playPauseScaleTimer
                            interval: 100
                            onTriggered: playPauseBtn.scale = 1.0
                        }
                    }
                }
            }

            Text {
                id: previousBtn
                text: Icons.previous
                textFormat: Text.RichText
                color: previousHover.hovered ? ((hasArtwork || wallpaperPath !== "") ? Styling.srItem("overprimary") : Styling.srItem("overprimary")) : Colors.overBackground
                font.pixelSize: 16
                font.family: Icons.font
                opacity: compactPlayer.player?.canGoPrevious ?? false ? 1.0 : 0.3
                visible: compactPlayer.player !== null && compactPlayer.playerExpanded && (compactPlayer.player?.canGoPrevious ?? false)
                clip: true
                scale: 1.0
                readonly property real naturalWidth: implicitWidth
                Layout.preferredWidth: (compactPlayer.player !== null && compactPlayer.playerExpanded) ? naturalWidth : 0
                Behavior on Layout.preferredWidth {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on color {
                    enabled: Config.animDuration > 0
                    ColorAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on scale {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.5
                    }
                }
                HoverHandler {
                    id: previousHover
                    enabled: compactPlayer.player?.canGoPrevious ?? false
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: compactPlayer.player?.canGoPrevious ?? false ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: compactPlayer.player?.canGoPrevious ?? false
                    onClicked: {
                        previousBtn.scale = 1.5;
                        compactPlayer.player?.previous();
                        previousScaleTimer.restart();
                    }
                }
                Timer {
                    id: previousScaleTimer
                    interval: 100
                    onTriggered: previousBtn.scale = 1.0
                }
            }

            WavyLine {
                id: visualizer
                Layout.fillWidth: true
                Layout.preferredHeight: 18
                Layout.leftMargin: compactPlayer.playerExpanded ? 0 : 8
                Layout.rightMargin: compactPlayer.playerExpanded ? 0 : 8
                active: compactPlayer.isPlaying
                cavaStyle: Config.theme.cavaStyle
                visible: compactPlayer.playerExpanded
                color: (hasArtwork || wallpaperPath !== "") ? Styling.srItem("overprimary") : Colors.overBackground
            }

            Text {
                id: nextBtn
                text: Icons.next
                textFormat: Text.RichText
                color: nextHover.hovered ? ((hasArtwork || wallpaperPath !== "") ? Styling.srItem("overprimary") : Styling.srItem("overprimary")) : Colors.overBackground
                font.pixelSize: 16
                font.family: Icons.font
                opacity: compactPlayer.player?.canGoNext ?? false ? 1.0 : 0.3
                clip: true
                scale: 1.0
                visible: compactPlayer.playerExpanded
                readonly property real naturalWidth: implicitWidth
                Layout.preferredWidth: (compactPlayer.player !== null && compactPlayer.playerExpanded) ? naturalWidth : 0
                Behavior on Layout.preferredWidth {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on color {
                    enabled: Config.animDuration > 0
                    ColorAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on scale {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.5
                    }
                }
                HoverHandler {
                    id: nextHover
                    enabled: compactPlayer.player?.canGoNext ?? false
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: compactPlayer.player?.canGoNext ?? false ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: compactPlayer.player?.canGoNext ?? false
                    onClicked: {
                        nextBtn.scale = 1.1;
                        compactPlayer.player?.next();
                        nextScaleTimer.restart();
                    }
                }
                Timer {
                    id: nextScaleTimer
                    interval: 100
                    onTriggered: nextBtn.scale = 1.0
                }
            }

            Text {
                id: modeBtn
                text: {
                    if (MprisController.hasShuffle)
                        return Icons.shuffle;
                    switch (MprisController.loopState) {
                    case MprisLoopState.Track:
                        return Icons.repeatOnce;
                    case MprisLoopState.Playlist:
                        return Icons.repeat;
                    default:
                        return Icons.shuffle;
                    }
                }
                textFormat: Text.RichText
                color: modeBtn.modeHover.hovered ? ((hasArtwork || wallpaperPath !== "") ? Styling.srItem("overprimary") : Styling.srItem("overprimary")) : Colors.overBackground
                property alias modeHover: modeHover
                font.pixelSize: 16
                font.family: Icons.font
                opacity: {
                    if (!(MprisController.shuffleSupported || MprisController.loopSupported))
                        return 0.3;
                    if (!MprisController.hasShuffle && MprisController.loopState === MprisLoopState.None)
                        return 0.3;
                    return 1.0;
                }
                clip: true
                scale: 1.0
                visible: false // Hidden by user request
                readonly property real naturalWidth: implicitWidth
                Layout.preferredWidth: 0 // Hidden by user request
                Behavior on Layout.preferredWidth {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on color {
                    enabled: Config.animDuration > 0
                    ColorAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on scale {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.5
                    }
                }
                HoverHandler {
                    id: modeHover
                    enabled: MprisController.shuffleSupported || MprisController.loopSupported
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: MprisController.shuffleSupported || MprisController.loopSupported
                    onClicked: {
                        modeBtn.scale = 1.1;
                        if (MprisController.hasShuffle) {
                            MprisController.setShuffle(false);
                            MprisController.setLoopState(MprisLoopState.Playlist);
                        } else if (MprisController.loopState === MprisLoopState.Playlist) {
                            MprisController.setLoopState(MprisLoopState.Track);
                        } else if (MprisController.loopState === MprisLoopState.Track) {
                            MprisController.setLoopState(MprisLoopState.None);
                        } else {
                            MprisController.setShuffle(true);
                        }
                        modeScaleTimer.restart();
                    }
                }
                Timer {
                    id: modeScaleTimer
                    interval: 100
                    onTriggered: modeBtn.scale = 1.0
                }
            }

            Text {
                id: playerIcon
                text: compactPlayer.getPlayerIcon(compactPlayer.player)
                textFormat: Text.RichText
                color: playerIconHover.hovered ? ((hasArtwork || wallpaperPath !== "") ? Styling.srItem("overprimary") : Styling.srItem("overprimary")) : Colors.overBackground
                font.pixelSize: 20
                font.family: Icons.font
                verticalAlignment: Text.AlignVCenter
                visible: false // Hidden by user request
                Layout.preferredWidth: 0 // Hidden by user request
                Layout.rightMargin: 0 // Hidden by user request
                Behavior on Layout.preferredWidth {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on Layout.rightMargin {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
                Behavior on color {
                    enabled: Config.animDuration > 0
                    ColorAnimation {
                        duration: Config.animDuration
                        easing.type: Easing.OutQuart
                    }
                }
                HoverHandler {
                    id: playerIconHover
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            MprisController.cyclePlayer(1);
                        } else if (mouse.button === Qt.RightButton) {
                            playerPopup.toggle();
                        }
                    }
                }
            }
        }
    }

    BarPopup {
        id: playerPopup
        anchorItem: playerIcon
        bar: ({
                position: Config.bar?.position ?? "top"
            })

        contentWidth: 250
        contentHeight: playersColumn.implicitHeight + playerPopup.popupPadding * 2

        ColumnLayout {
            id: playersColumn
            anchors.fill: parent
            spacing: 4

            Repeater {
                model: MprisController.filteredPlayers
                delegate: StyledRect {
                    id: playerItem
                    required property var modelData
                    required property int index

                    readonly property bool isSelected: compactPlayer.player === modelData
                    readonly property bool isFirst: index === 0
                    readonly property bool isLast: index === MprisController.filteredPlayers.length - 1

                    readonly property real defaultRadius: Styling.radius(4)
                    readonly property real selectedRadius: defaultRadius / 2

                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    variant: isSelected ? "primary" : (hoverHandler.hovered ? "focus" : "common")
                    enableShadow: false

                    topLeftRadius: isSelected ? (isFirst ? defaultRadius : selectedRadius) : defaultRadius
                    topRightRadius: isSelected ? (isFirst ? defaultRadius : selectedRadius) : defaultRadius
                    bottomLeftRadius: isSelected ? (isLast ? defaultRadius : selectedRadius) : defaultRadius
                    bottomRightRadius: isSelected ? (isLast ? defaultRadius : selectedRadius) : defaultRadius

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Text {
                            text: compactPlayer.getPlayerIcon(playerItem.modelData)
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: playerItem.item
                        }

                        Text {
                            text: playerItem.modelData.trackTitle || playerItem.modelData.identity || "Unknown Player"
                            font.family: Styling.defaultFont
                            font.pixelSize: Styling.fontSize(0)
                            color: playerItem.item
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    HoverHandler {
                        id: hoverHandler
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            MprisController.setActivePlayer(playerItem.modelData);
                        }
                    }
                }
            }
        }
    }
}
