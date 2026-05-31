pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
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
    WlrLayershell.namespace: "ambxst:musicdock"
    exclusionMode: ExclusionMode.Ignore

    readonly property bool isOpen: GlobalStates.musicPanelOpen
    // Siempre visible para que la máscara reciba el cursor al cerrar (igual que NewsDock).
    visible: true

    readonly property int dockWidth: 600
    readonly property int hPadding: 20
    readonly property int shoulderSize: Config.roundness > 0 ? Config.roundness + 28 : 44

    readonly property int barReserved: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "top" ? base : 0;
    }

    readonly property int panelHeight: Math.min(440, dock.height - dock.barReserved - 28)

    // ── Estado MPRIS (vía MprisController) ──────────────────────────────
    property var player: MprisController.activePlayer
    readonly property real position: player?.position ?? 0
    readonly property real length: player?.length ?? 0
    readonly property string trackTitle: player?.trackTitle ?? ""
    readonly property string trackArtist: player?.trackArtist ?? ""
    readonly property string trackArtUrl: player?.trackArtUrl ?? ""
    readonly property string sourceName: player?.identity ?? ""
    readonly property real volume: player?.volume ?? 0
    readonly property bool isPlaying: MprisController.isPlaying
    readonly property real progress: dock.length > 0 ? dock.position / dock.length : 0
    readonly property bool hasPlayer: dock.player !== null && dock.player !== undefined

    // Posición en vivo: Mpris no emite position en tiempo real; lo refrescamos.
    Timer {
        interval: 1000
        running: dock.isOpen && dock.isPlaying
        repeat: true
        onTriggered: {
            if (dock.player)
                dock.player.positionChanged()
        }
    }

    function formatTime(seconds) {
        if (!seconds || seconds < 0)
            return "0:00"
        const m = Math.floor(seconds / 60)
        const s = Math.floor(seconds % 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function seekRatio(r) {
        if (dock.player && dock.player.canSeek && dock.length > 0) {
            const clamped = Math.max(0, Math.min(1, r))
            dock.player.position = dock.length * clamped
        }
    }

    function setVolumeRatio(r) {
        if (dock.player && MprisController.canChangeVolume) {
            dock.player.volume = Math.max(0, Math.min(1, r))
        }
    }

    // ── Máscara: cerrado → click-through; abierto → cuerpo + hombros ──
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

    // Auto-cerrar tras 600ms de inactividad del cursor.
    Timer {
        id: closeTimer
        interval: 600
        repeat: false
        onTriggered: GlobalStates.musicPanelOpen = false
    }

    Item {
        id: dockContainer
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: dock.dockWidth
        height: dock.panelHeight
        opacity: dock.isOpen ? 1 : 0
        visible: opacity > 0.001

        HoverHandler {
            onHoveredChanged: {
                if (!hovered && dock.isOpen)
                    closeTimer.restart();
                else
                    closeTimer.stop();
            }
        }

        // Sube desde el borde inferior.
        transform: Translate {
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

        // Cuerpo del panel — bg matugen, esquinas SUPERIORES redondeadas.
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

        // Hombro cóncavo inferior-izquierdo.
        Item {
            width: dock.shoulderSize
            height: dock.shoulderSize
            anchors.bottom: dockBg.bottom
            anchors.right: dockBg.left
            RoundCorner {
                anchors.fill: parent
                corner: RoundCorner.CornerEnum.BottomRight
                size: dock.shoulderSize
                color: dockBg.color
            }
        }
        // Hombro cóncavo inferior-derecho.
        Item {
            width: dock.shoulderSize
            height: dock.shoulderSize
            anchors.bottom: dockBg.bottom
            anchors.left: dockBg.right
            RoundCorner {
                anchors.fill: parent
                corner: RoundCorner.CornerEnum.BottomLeft
                size: dock.shoulderSize
                color: dockBg.color
            }
        }

        // ─────────────────────────── CONTENIDO ───────────────────────────

        // Cabecera: portada + título / artista / fuente
        Item {
            id: header
            anchors.top: dockBg.top
            anchors.left: dockBg.left
            anchors.right: dockBg.right
            anchors.topMargin: 20
            anchors.leftMargin: dock.hPadding
            anchors.rightMargin: dock.hPadding
            height: 110

            // Portada redondeada (MultiEffect mask)
            Item {
                id: artBox
                width: 110
                height: 110
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                Item {
                    id: artMask
                    anchors.fill: parent
                    layer.enabled: true
                    visible: false
                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 16
                    color: Colors.surfaceContainer
                    visible: dock.trackArtUrl === ""
                    Text {
                        anchors.centerIn: parent
                        text: Icons.player
                        font.family: Icons.font
                        font.pixelSize: 42
                        color: Colors.outline
                    }
                }
                Image {
                    id: artImg
                    anchors.fill: parent
                    source: dock.trackArtUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: artImg
                    maskEnabled: true
                    maskSource: artMask
                    visible: dock.trackArtUrl !== ""
                }
            }

            // Metadatos
            Column {
                anchors.left: artBox.right
                anchors.right: parent.right
                anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Text {
                    width: parent.width
                    text: dock.trackTitle !== "" ? dock.trackTitle : "Nothing playing"
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(4)
                    font.weight: Font.ExtraBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: dock.trackArtist
                    color: Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    elide: Text.ElideRight
                    visible: dock.trackArtist !== ""
                }
                Text {
                    width: parent.width
                    text: dock.sourceName
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(1)
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    topPadding: 6
                    visible: dock.sourceName !== ""
                }
            }
        }

        // Waveform = barra de seek (contenedor transparente, sin card).
        // Forma estática por pista (NO CAVA): parte reproducida en accent, resto
        // atenuado; click/arrastre adelanta. Una sola superficie, como la ref.
        Item {
            id: waveCard
            anchors.top: header.bottom
            anchors.bottom: volumeRow.top
            anchors.left: dockBg.left
            anchors.right: dockBg.right
            anchors.topMargin: 18
            anchors.bottomMargin: 18
            anchors.leftMargin: dock.hPadding
            anchors.rightMargin: dock.hPadding

            // Forma base determinista (silueta en reposo / pausa).
            function waveBase(i) {
                var v = Math.abs(Math.sin(i * 0.7) * 0.5
                               + Math.sin(i * 1.9 + 1.3) * 0.3
                               + Math.sin(i * 0.37) * 0.2);
                if (v > 1) v = 1;
                return 0.10 + 0.90 * v; // 0.10..1
            }

            readonly property int barCount: Math.max(24, Math.floor(width / 9))
            readonly property real slot: barCount > 0 ? width / barCount : 9

            // ── Simulación de espectro tipo CAVA ──────────────────────────────
            // Cada banda tiene su propia frecuencia/fase (no uniforme). Los graves
            // (izq) son lentos y potentes; los agudos (der) nerviosos y cortos.
            // Sumamos varios osciladores + un golpe de "energía" global pseudo-
            // aleatorio, y aplicamos gravedad (caída lenta) sobre el pico previo.
            property real phase: 0
            property real energy: 0.5
            property var levels: []
            property var peaks: []
            onBarCountChanged: { levels = []; peaks = []; }

            function rand01(seed) {
                var s = Math.sin(seed * 12.9898) * 43758.5453;
                return s - Math.floor(s); // hash determinista 0..1
            }

            function tick() {
                var n = barCount;
                // Energía global con caminata aleatoria suave → simula la dinámica
                // de la canción (estrofas suaves, drops fuertes).
                energy += (Math.random() - 0.5) * 0.5;
                if (energy < 0.15) energy = 0.15;
                if (energy > 1.0) energy = 1.0;
                phase += 0.18;

                var prevP = (peaks.length === n) ? peaks : null;
                var lv = new Array(n);
                var pk = new Array(n);
                for (var i = 0; i < n; i++) {
                    var t = i / Math.max(1, n - 1);
                    // Envolvente: graves pegan más que agudos (curva descendente).
                    var env = 0.45 + 0.55 * Math.pow(1 - t, 0.8);
                    // Velocidad por banda: agudos vibran más rápido que graves.
                    var spd = 0.6 + 3.4 * t;
                    var ph = waveCard.rand01(i + 1) * 6.283;
                    // Mezcla de osciladores desfasados → forma irregular, no senoidal limpia.
                    var osc = 0.5
                            + 0.30 * Math.sin(phase * spd + ph)
                            + 0.20 * Math.sin(phase * spd * 1.7 + ph * 2.1);
                    // Chispa aleatoria ocasional (transientes / percusión).
                    var spark = (Math.random() < 0.06) ? Math.random() * 0.5 : 0;
                    var target = Math.max(0, Math.min(1, env * energy * osc + spark));

                    // Gravedad: sube al instante, cae despacio (rebote tipo CAVA).
                    var prev = prevP ? prevP[i] : 0;
                    var val = (target >= prev) ? target : Math.max(target, prev - 0.06);
                    pk[i] = val;
                    lv[i] = val;
                }
                peaks = pk;
                levels = lv;
            }

            Timer {
                interval: 45
                repeat: true
                running: dock.isOpen && dock.isPlaying
                onTriggered: waveCard.tick()
            }

            Repeater {
                model: waveCard.barCount
                Rectangle {
                    id: wbar
                    required property int index
                    readonly property bool played: (index + 0.5) / waveCard.barCount <= dock.progress
                    readonly property real lvl: (waveCard.levels[index] !== undefined) ? waveCard.levels[index] : 0
                    readonly property real amp: dock.isPlaying ? (0.08 + 0.92 * lvl) : waveCard.waveBase(index)
                    width: Math.max(3, waveCard.slot * 0.42)
                    radius: width / 2
                    height: Math.max(width, waveCard.height * amp)
                    x: index * waveCard.slot + (waveCard.slot - width) / 2
                    y: (waveCard.height - height) / 2
                    color: wbar.played
                        ? Colors.primary
                        : Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.28)
                    Behavior on height { NumberAnimation { duration: 55; easing.type: Easing.OutQuad } }
                    Behavior on color { ColorAnimation { duration: 160 } }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: dock.player && dock.player.canSeek && dock.length > 0
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPressed: mouse => dock.seekRatio(mouse.x / width)
                onPositionChanged: mouse => { if (pressed) dock.seekRatio(mouse.x / width) }
            }
        }

        // Barra de volumen
        Item {
            id: volumeRow
            anchors.left: dockBg.left
            anchors.right: dockBg.right
            anchors.bottom: controlBar.top
            anchors.leftMargin: dock.hPadding
            anchors.rightMargin: dock.hPadding
            anchors.bottomMargin: 14
            height: 20

            Text {
                id: volIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: dock.volume <= 0.001 ? Icons.speakerX : (dock.volume < 0.5 ? Icons.speakerLow : Icons.speakerHigh)
                font.family: Icons.font
                font.pixelSize: 18
                color: Colors.overBackground
            }

            Item {
                id: volSlider
                anchors.left: volIcon.right
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: 20

                Rectangle {
                    id: volTrack
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 4
                    radius: 2
                    color: Qt.rgba(Colors.overBackground.r, Colors.overBackground.g, Colors.overBackground.b, 0.18)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        radius: 2
                        width: parent.width * Math.max(0, Math.min(1, dock.volume))
                        color: Colors.primary
                    }
                }
                Rectangle {
                    id: volHandle
                    width: 12
                    height: 12
                    radius: 6
                    color: Colors.primary
                    anchors.verticalCenter: parent.verticalCenter
                    x: (volSlider.width - width) * Math.max(0, Math.min(1, dock.volume))
                    visible: MprisController.canChangeVolume
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: MprisController.canChangeVolume
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onPressed: mouse => dock.setVolumeRatio(mouse.x / width)
                    onPositionChanged: mouse => { if (pressed) dock.setVolumeRatio(mouse.x / width) }
                }
            }
        }

        // Barra de controles
        Item {
            id: controlBar
            anchors.left: dockBg.left
            anchors.right: dockBg.right
            anchors.bottom: dockBg.bottom
            anchors.leftMargin: dock.hPadding
            anchors.rightMargin: dock.hPadding
            anchors.bottomMargin: 16
            height: 56

            // Grupo izquierdo: navegación + selector de player + shuffle/loop
            Row {
                id: leftControls
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                // Anterior
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.previous
                    font.family: Icons.font
                    font.pixelSize: 22
                    color: MprisController.canGoPrevious ? Colors.overBackground : Colors.outline
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MprisController.previous()
                    }
                }

                // Selector de player: ‹  [pill]  ›
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Icons.caretLeft
                        font.family: Icons.font
                        font.pixelSize: 18
                        color: MprisController.filteredPlayers.length > 1 ? Colors.overBackground : Colors.outline
                        MouseArea {
                            anchors.fill: parent
                            enabled: MprisController.filteredPlayers.length > 1
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MprisController.cyclePlayer(-1)
                        }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 32
                        width: pillLabel.implicitWidth + 24
                        radius: height / 2
                        color: Colors.surfaceContainer
                        Text {
                            id: pillLabel
                            anchors.centerIn: parent
                            text: dock.sourceName !== "" ? dock.sourceName.toLowerCase() : "no player"
                            color: Colors.overBackground
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Icons.caretRight
                        font.family: Icons.font
                        font.pixelSize: 18
                        color: MprisController.filteredPlayers.length > 1 ? Colors.overBackground : Colors.outline
                        MouseArea {
                            anchors.fill: parent
                            enabled: MprisController.filteredPlayers.length > 1
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MprisController.cyclePlayer(1)
                        }
                    }
                }

                // Siguiente
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.next
                    font.family: Icons.font
                    font.pixelSize: 22
                    color: MprisController.canGoNext ? Colors.overBackground : Colors.outline
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MprisController.next()
                    }
                }

                // Shuffle
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.shuffle
                    font.family: Icons.font
                    font.pixelSize: 18
                    color: MprisController.hasShuffle ? Colors.primary : Colors.outline
                    MouseArea {
                        anchors.fill: parent
                        enabled: MprisController.shuffleSupported
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MprisController.setShuffle(!MprisController.hasShuffle)
                    }
                }

                // Loop
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: MprisController.loopState === MprisLoopState.Track ? Icons.repeatOnce : Icons.repeat
                    font.family: Icons.font
                    font.pixelSize: 18
                    color: MprisController.loopState !== MprisLoopState.None ? Colors.primary : Colors.outline
                    MouseArea {
                        anchors.fill: parent
                        enabled: MprisController.loopSupported
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            let next = MprisController.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                                     : MprisController.loopState === MprisLoopState.Playlist ? MprisLoopState.Track
                                     : MprisLoopState.None
                            MprisController.setLoopState(next)
                        }
                    }
                }
            }

            // Grupo derecho: tiempo + play/pause grande
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: dock.formatTime(dock.position) + " / " + dock.formatTime(dock.length)
                    color: Colors.outline
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.monoFontSize(0)
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 52
                    height: 52
                    radius: width / 2
                    color: Colors.primary
                    Text {
                        anchors.centerIn: parent
                        text: dock.isPlaying ? Icons.pause : Icons.play
                        font.family: Icons.font
                        font.pixelSize: 24
                        color: Colors.background
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: MprisController.canTogglePlaying
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MprisController.togglePlaying()
                    }
                }
            }
        }
    }
}
