pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Rectangle {
    id: root
    color: "transparent"
    implicitWidth: 600
    implicitHeight: 400

    // ── Band data (dB, -12..+12) ─────────────────────────────────────────────
    readonly property var frequencies: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    // Live UI band gains in dB
    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property string activePreset: "Flat"
    // pending = user changed the curve but hasn't committed it to EasyEffects yet
    property bool pending: false

    // Predefined preset gain values (dB, -12 to +12)
    readonly property var presets: ({
        "Flat":    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Bass":    [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
        "Treble":  [0, 0, 0, 0, 0, 2, 4, 5, 6, 6],
        "Vocal":   [-2, -2, -1, 0, 2, 4, 4, 2, 0, -1],
        "Pop":     [-1, -1, 0, 2, 4, 4, 2, 0, -1, -1],
        "Rock":    [4, 3, 2, -1, -2, -1, 2, 3, 4, 4],
        "Jazz":    [3, 2, 1, 2, -1, -1, 0, 1, 2, 3],
        "Classic": [4, 3, 2, 2, -1, -1, 0, 2, 3, 4]
    })

    Component.onCompleted: {
        EasyEffectsService.initialize();
        // Initialize the UI to Flat without auto-applying (don't clobber the
        // user's current EQ just by opening the tab).
        setBands(presets["Flat"]);
        activePreset = "Flat";
        pending = false;
    }

    function setBands(arr) {
        let a = [];
        for (let i = 0; i < 10; i++)
            a.push(arr[i]);
        root.bands = a;
    }

    // Commit the current curve to EasyEffects + fire the lightning strike
    function commit() {
        if (EasyEffectsService.available)
            EasyEffectsService.applyEqualizer(root.bands);
        root.pending = false;
        root.triggerEqLightning();
    }

    function applyPreset(name) {
        setBands(presets[name]);
        activePreset = name;
        commit();
    }

    // Restore the neutral default curve (flat, 0 dB on every band)
    function resetDefault() {
        setBands(presets["Flat"]);
        activePreset = "Flat";
        commit();
    }

    function onBandReleased(index, value) {
        let a = root.bands.slice();
        a[index] = value;
        root.bands = a;
        activePreset = "Custom";
        pending = true;
    }

    // ── Lightning animation state ────────────────────────────────────────────
    // progress sweeps 0 → 10 across the bands; fade dissipates the glow afterwards
    property real eqLightningProgress: 0.0
    property real eqLightningFade: 1.0  // 1.0 = fully faded out

    SequentialAnimation {
        id: eqLightningAnim
        running: false
        ScriptAction {
            script: {
                root.eqLightningFade = 0.0;
                root.eqLightningProgress = 0.0;
            }
        }
        NumberAnimation {
            target: root
            property: "eqLightningProgress"
            from: 0.0
            to: 10.0
            duration: 650
            easing.type: Easing.OutSine
        }
        PauseAnimation { duration: 150 }
        NumberAnimation {
            target: root
            property: "eqLightningFade"
            from: 0.0
            to: 1.0
            duration: 800
            easing.type: Easing.OutQuad
        }
        ScriptAction { script: root.eqLightningProgress = 0.0 }
    }

    function triggerEqLightning() {
        eqLightningAnim.restart();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // ── Header ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true

                Text {
                    text: "EQUALIZER"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(2)
                    font.weight: Font.Bold
                    color: Colors.primary
                }
                Text {
                    text: EasyEffectsService.available ? (EasyEffectsService.bypassed ? "Bypassed" : "PipeWire · EasyEffects active") : "EasyEffects not running"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.monoFontSize(-1)
                    color: Colors.overBackground
                    opacity: 0.6
                }
            }

            Item { Layout.fillWidth: true }

            // Reset to default (flat) curve
            Rectangle {
                id: resetBtn
                Layout.preferredHeight: 28
                Layout.preferredWidth: 28
                radius: Styling.radius(3)
                color: resetMa.containsMouse ? Colors.surfaceContainerHigh : Colors.surfaceContainer
                border.width: 1
                border.color: Colors.outline

                Text {
                    anchors.centerIn: parent
                    text: Icons.arrowCounterClockwise
                    font.family: Icons.font
                    font.pixelSize: 15
                    color: resetMa.containsMouse ? Colors.primary : Colors.overBackground
                }

                MouseArea {
                    id: resetMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.resetDefault()
                }

                StyledToolTip {
                    show: resetMa.containsMouse
                    tooltipText: "Reset to default (Flat)"
                }
            }

            // Bypass toggle
            Rectangle {
                id: bypassBtn
                Layout.preferredHeight: 28
                Layout.preferredWidth: bypassTxt.implicitWidth + 24
                radius: Styling.radius(3)
                color: !EasyEffectsService.bypassed ? Colors.surfaceContainer : Colors.surfaceContainerHigh
                border.width: 1
                border.color: Colors.outline
                opacity: EasyEffectsService.available ? 1 : 0.4

                Text {
                    id: bypassTxt
                    anchors.centerIn: parent
                    text: EasyEffectsService.bypassed ? "Enable" : "Bypass"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.monoFontSize(-1)
                    font.bold: true
                    color: Colors.overBackground
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: EasyEffectsService.available
                    cursorShape: Qt.PointingHandCursor
                    onClicked: EasyEffectsService.toggleBypass()
                }
            }

            // Apply / Saved button
            Rectangle {
                id: applyBtn
                Layout.preferredHeight: 28
                Layout.preferredWidth: applyTxt.implicitWidth + 24
                radius: Styling.radius(3)
                color: root.pending ? Colors.primary : Colors.surfaceContainer
                border.width: 1
                border.color: root.pending ? Colors.primary : Colors.outline

                Behavior on color {
                    enabled: Config.animDuration > 0
                    ColorAnimation { duration: Config.animDuration; easing.type: Easing.OutCubic }
                }

                // Glow while pending (begging to be applied)
                layer.enabled: root.pending
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Colors.primary
                    shadowOpacity: 0.45
                    shadowBlur: 0.6
                }

                Text {
                    id: applyTxt
                    anchors.centerIn: parent
                    text: root.pending ? "Apply" : "Saved"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.monoFontSize(-1)
                    font.bold: true
                    color: root.pending ? Styling.srItem("primary") : Colors.overBackground
                    Behavior on color {
                        enabled: Config.animDuration > 0
                        ColorAnimation { duration: Config.animDuration }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: root.pending ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (root.pending) root.commit()
                }
            }

            // Active preset name
            Text {
                Layout.leftMargin: 4
                text: root.activePreset
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.monoFontSize(0)
                font.bold: true
                color: Colors.tertiary
            }
        }

        // ── Sliders + lightning ──────────────────────────────────────────────
        Item {
            id: slidersArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: false

            // Vertical extent reserved for the freq/dB labels at the bottom
            readonly property real labelZone: 38
            readonly property real handleHalf: 9

            Row {
                id: eqRow
                anchors.fill: parent
                z: 1  // sliders + handles render above the lightning

                Repeater {
                    model: 10

                    delegate: Item {
                        id: col
                        required property int index

                        width: eqRow.width / 10
                        height: eqRow.height

                        // Lightning hit envelope as the bolt sweeps past this band
                        property real dist: root.eqLightningProgress - index
                        property real hitPulse: (dist >= 0 && dist < 1.0) ? Math.sin(dist * Math.PI) : 0.0

                        readonly property var glowColors: [Colors.primary, Colors.tertiary, Colors.secondary]
                        readonly property color glowColor: glowColors[index % 3]

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6

                            Slider {
                                id: eqSlider
                                Layout.fillHeight: true
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 28
                                orientation: Qt.Vertical
                                from: -12
                                to: 12
                                stepSize: 1

                                Component.onCompleted: value = root.bands[col.index]

                                // Re-sync from the model when not actively dragged
                                Connections {
                                    target: root
                                    function onBandsChanged() {
                                        if (!eqSlider.pressed)
                                            eqSlider.value = root.bands[col.index];
                                    }
                                }

                                Behavior on value {
                                    enabled: !eqSlider.pressed && Config.animDuration > 0
                                    NumberAnimation { duration: 350; easing.type: Easing.OutQuart }
                                }

                                onPressedChanged: {
                                    if (!pressed)
                                        root.onBandReleased(col.index, Math.round(value));
                                }

                                background: Item {
                                    Rectangle {
                                        id: trackBg
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: eqSlider.topPadding
                                        width: 10
                                        height: eqSlider.availableHeight
                                        radius: 5
                                        color: Qt.rgba(Colors.surfaceVariant.r, Colors.surfaceVariant.g, Colors.surfaceVariant.b, 0.6)

                                        // Fill from the handle down to the bottom
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: (1 - eqSlider.visualPosition) * parent.height
                                            radius: 5
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: Qt.lighter(Colors.tertiary, 1.1) }
                                                GradientStop { position: 1.0; color: Colors.primary }
                                            }
                                        }
                                    }
                                }

                                handle: Rectangle {
                                    x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                    y: eqSlider.topPadding + eqSlider.visualPosition * (eqSlider.availableHeight - height)
                                    implicitWidth: 18
                                    implicitHeight: 18
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: Colors.overBackground
                                    scale: 1.0 + col.hitPulse * 0.4 * (1.0 - root.eqLightningFade)

                                    // Glow flare that blooms as the bolt passes, fading with the strike
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width + 36 * col.hitPulse
                                        height: width
                                        radius: width / 2
                                        color: col.glowColor
                                        opacity: col.hitPulse * (1.0 - root.eqLightningFade)
                                        visible: opacity > 0.01
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            blurEnabled: true
                                            blurMax: 32
                                            blur: 1.0
                                        }
                                    }
                                }
                            }

                            Text {
                                text: root.frequencies[col.index]
                                font.family: Config.theme.monoFont
                                font.pixelSize: Styling.monoFontSize(-1)
                                font.bold: true
                                color: Colors.overBackground
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: {
                                    let v = Math.round(eqSlider.value);
                                    return (v > 0 ? "+" : "") + v;
                                }
                                font.family: Config.theme.monoFont
                                font.pixelSize: Styling.monoFontSize(-2)
                                color: Colors.overBackground
                                opacity: 0.55
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }

            // ── The fluid multi-strand lightning ─────────────────────────────
            Canvas {
                id: lightningCanvas
                anchors.fill: parent
                z: 0
                opacity: 1.0 - root.eqLightningFade
                renderTarget: Canvas.FramebufferObject

                // GPU bloom without locking the CPU with ctx.shadowBlur
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Colors.primary
                    shadowBlur: 1.0
                    shadowOpacity: 0.6
                }

                Timer {
                    interval: 16  // ~60fps while the bolt is alive
                    running: root.eqLightningFade < 1.0 && root.eqLightningProgress > 0.0
                    repeat: true
                    onTriggered: lightningCanvas.requestPaint()
                }

                onPaint: {
                    let ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    if (root.eqLightningProgress <= 0.0 || root.eqLightningFade >= 1.0)
                        return;
                    if (width <= 0 || height <= 0)
                        return;

                    let time = Date.now() / 1000;
                    let maxIdx = root.eqLightningProgress;  // 0..10

                    ctx.lineJoin = "round";
                    ctx.lineCap = "round";

                    // Map the 10 handle positions (math, matches the slider geometry)
                    let trackTop = slidersArea.handleHalf;
                    let trackBottom = height - slidersArea.labelZone - slidersArea.handleHalf;
                    let pts = [];
                    for (let i = 0; i < 10; i++) {
                        let val = Number(root.bands[i]);
                        if (isNaN(val)) val = 0;
                        let norm = (12 - val) / 24;  // 0 at +12 (top), 1 at -12 (bottom)
                        let py = trackTop + norm * (trackBottom - trackTop);
                        let px = (i + 0.5) * (width / 10);
                        pts.push({ x: px, y: py });
                    }

                    // Theme palette for the strands
                    let cOuter = Colors.primary;     // massive sweeping outer glow
                    let cMid = Colors.tertiary;       // medium sweeping wave
                    let cCore = Colors.secondary;     // tight crackling core
                    let cHot = Qt.rgba(1, 1, 1, 1);   // hot white center

                    for (let s = 0; s < 4; s++) {
                        ctx.beginPath();
                        ctx.moveTo(pts[0].x, pts[0].y);

                        for (let i = 0; i < pts.length - 1; i++) {
                            if (i > maxIdx) break;

                            let p1 = pts[i];
                            let p2 = pts[i + 1];

                            let fraction = 1.0;
                            if (maxIdx < i + 1)
                                fraction = maxIdx - i;

                            let steps = s === 3 ? 6 : 8;
                            for (let j = 1; j <= steps; j++) {
                                let t = j / steps;
                                if (t > fraction) t = fraction;

                                let cx = p1.x + (p2.x - p1.x) * t;
                                let cy = p1.y + (p2.y - p1.y) * t;

                                let envelope = Math.sin(t * Math.PI);

                                let noiseAmpX = s === 3 ? 1.0 : (4 - s) * 4;
                                let noiseAmpY = s === 3 ? 1.0 : (4 - s) * 5;

                                let sepWaveX = (s < 2) ? Math.sin(time * 3 + i + j + s) * 10 * envelope : 0;
                                let sepWaveY = (s < 2) ? Math.cos(time * 2.5 + i - j - s) * 15 * envelope : 0;

                                let fadeMul = 1 - root.eqLightningFade;
                                let noiseX = Math.sin(time * (10 + s) + i + j) * Math.cos(time * 8 - i + j) * noiseAmpX * envelope * fadeMul;
                                let noiseY = Math.cos(time * (9 - s) + i - j) * Math.sin(time * 7 + i - j) * noiseAmpY * envelope * fadeMul;

                                ctx.lineTo(cx + sepWaveX + noiseX, cy + sepWaveY + noiseY);

                                if (t === fraction) break;
                            }
                        }

                        if (s === 0) {
                            ctx.lineWidth = 20;
                            ctx.strokeStyle = cOuter;
                            ctx.globalAlpha = 0.2;
                        } else if (s === 1) {
                            ctx.lineWidth = 8;
                            ctx.strokeStyle = cMid;
                            ctx.globalAlpha = 0.45;
                        } else if (s === 2) {
                            ctx.lineWidth = 3.5;
                            ctx.strokeStyle = cCore;
                            ctx.globalAlpha = 0.85;
                        } else {
                            ctx.lineWidth = 1.0;
                            ctx.strokeStyle = cHot;
                            ctx.globalAlpha = 0.15;
                        }

                        ctx.stroke();
                    }
                }
            }
        }

        // ── Presets grid ─────────────────────────────────────────────────────
        GridLayout {
            columns: 4
            rowSpacing: 8
            columnSpacing: 8
            Layout.fillWidth: true
            Layout.preferredHeight: 80

            Repeater {
                model: ["Flat", "Bass", "Treble", "Vocal", "Pop", "Rock", "Jazz", "Classic"]

                delegate: Rectangle {
                    id: presetBtn
                    required property string modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: Styling.radius(3)

                    property bool isActive: root.activePreset === modelData
                    property bool isHovered: presetMa.containsMouse

                    color: isActive ? Colors.primary : (isHovered ? Colors.surfaceContainerHigh : Colors.surfaceContainer)
                    border.width: 1
                    border.color: isActive ? Colors.primary : (isHovered ? Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.55) : Colors.outline)
                    scale: isHovered && !isActive ? 1.05 : 1.0

                    // Soft glow while this preset is the active one
                    layer.enabled: isActive
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Colors.primary
                        shadowOpacity: 0.4
                        shadowBlur: 0.5
                    }

                    Behavior on color {
                        enabled: Config.animDuration > 0
                        ColorAnimation { duration: 200 }
                    }
                    Behavior on border.color {
                        enabled: Config.animDuration > 0
                        ColorAnimation { duration: 200 }
                    }
                    Behavior on scale {
                        enabled: Config.animDuration > 0
                        NumberAnimation { duration: 200; easing.type: Easing.OutBack }
                    }

                    // Leading accent stripe
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: parent.height - 14
                        radius: 1.5
                        color: presetBtn.isActive ? Styling.srItem("primary") : Colors.tertiary
                        opacity: presetBtn.isActive ? 0.95 : (presetBtn.isHovered ? 0.9 : 0.45)
                        Behavior on opacity {
                            enabled: Config.animDuration > 0
                            NumberAnimation { duration: 200 }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: presetBtn.modelData
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.monoFontSize(0)
                        font.bold: true
                        font.letterSpacing: 0.5
                        color: presetBtn.isActive ? Styling.srItem("primary") : Colors.overBackground
                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation { duration: 200 }
                        }
                    }

                    MouseArea {
                        id: presetMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.applyPreset(presetBtn.modelData)
                    }
                }
            }
        }
    }
}
