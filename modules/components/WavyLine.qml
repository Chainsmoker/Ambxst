import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.theme

Canvas {
    id: root

    // =========================================================================
    // API Properties (Compatible with previous WavyLine)
    // =========================================================================
    property color color: Styling.srItem("overprimary")
    property real lineWidth: 3 // bar width
    property real frequency: 2
    property real amplitudeMultiplier: 0.5
    property real fullLength: width
    property bool running: true
    property bool active: true // Map playing state (isPlaying)
    // true  → visualizador real de cava (notch/player).
    // false → onda por-valor SIN lanzar cava (sliders/seekbars).
    property bool useCava: true
    // En modo no-cava: false = línea sinusoidal; true = barras animadas (ecualizador).
    property bool barStyle: false
    // Estilo del visualizador CAVA: "blocks" (brutal), "smooth", "bars" (grounded), "dots".
    property string cavaStyle: "blocks"

    // Legacy compatibility
    property real amplitude: lineWidth * amplitudeMultiplier
    property real speed: 5
    property bool animationsEnabled: true

    // =========================================================================
    // Visualizer Config
    // =========================================================================
    property int numBars: 20
    property var barHeights: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]


    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    // Anima la onda estática (modo no-cava) repintando periódicamente para que fluya.
    Timer {
        interval: 33
        repeat: true
        running: !root.useCava && root.visible && root.animationsEnabled
        onTriggered: root.requestPaint()
    }

    // =========================================================================
    // CAVA Process (Real-time analyzer)
    // =========================================================================
    Process {
        id: cavaProcess
        // Only run CAVA when music is active/playing, widget is visible, y en modo cava
        running: root.running && root.visible && root.active && root.useCava
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/cava/visualizer.conf"]

        onRunningChanged: {
            console.log("[WavyLine] CAVA running state changed:", running);
        }

        stdout: SplitParser {
            onRead: data => {
                var parts = data.trim().split(';');
                if (parts.length > 0 && parts[parts.length - 1] === "") {
                    parts.pop();
                }
                if (parts.length === root.numBars) {
                    var heights = parts.map(Number);
                    for (var i = 0; i < root.numBars; i++) {
                        if (isNaN(heights[i])) heights[i] = 0;
                    }
                    root.barHeights = heights;
                    root.requestPaint();
                }
            }
        }

        stderr: SplitParser {
            onRead: data => {
                console.warn("[WavyLine] CAVA Error:", data);
            }
        }
    }

    // Smoothly decay bars to 0 when music is paused / process not running
    Timer {
        id: decayTimer
        interval: 16
        running: !cavaProcess.running
        repeat: true
        onTriggered: {
            var allZero = true;
            var newHeights = [];
            for (var i = 0; i < root.numBars; i++) {
                var h = root.barHeights[i] || 0;
                if (h > 0) {
                    h = Math.max(0, h - 8); // Decay step
                    allZero = false;
                }
                newHeights.push(h);
            }
            root.barHeights = newHeights;
            root.requestPaint();
            if (allZero) {
                decayTimer.running = false;
            }
        }
    }

    // Trigger decay on startup/toggle
    onActiveChanged: {
        if (!active) {
            decayTimer.running = true;
        }
    }

    // =========================================================================
    // Rendering (Bouncing Bars across the entire Canvas width)
    // =========================================================================
    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        if (width <= 0 || height <= 0) return;

        // Modo no-cava (sliders/seekbars): barras animadas o línea sinusoidal.
        if (!root.useCava) {
            // --- Barras animadas (ecualizador suave, por-valor, sin cava) ---
            if (root.barStyle) {
                var bw = root.lineWidth;
                var gap = (width - (root.numBars * bw)) / (root.numBars - 1);
                if (gap < 1) gap = 1;
                var tt = Date.now() / 220.0;
                var level = Math.min(root.amplitudeMultiplier / 1.5, 1.0);
                ctx.fillStyle = root.color;
                for (var bi = 0; bi < root.numBars; bi++) {
                    var bx = bi * (bw + gap);
                    var wv = 0.5 + 0.5 * Math.sin(tt + bi * 0.55);
                    var hh = (0.18 + 0.72 * wv * (0.35 + 0.65 * level)) * height;
                    if (hh < 2) hh = 2;
                    if (hh > height) hh = height;
                    var by = (height - hh) / 2;
                    ctx.beginPath();
                    ctx.roundedRect(bx, by, bw, hh, bw / 2, bw / 2);
                    ctx.fill();
                }
                return;
            }

            var amp = root.lineWidth * root.amplitudeMultiplier;
            // Clamp: la onda nunca debe salirse de la caja (p.ej. micro a >100%).
            var maxAmp = (height - root.lineWidth) / 2;
            if (amp > maxAmp) amp = maxAmp;
            if (amp < 0) amp = 0;
            var freq = root.frequency;
            var phase = Date.now() / 400.0;
            var centerY = height / 2;
            ctx.strokeStyle = root.color;
            ctx.lineWidth = root.lineWidth;
            ctx.lineCap = "round";
            ctx.beginPath();
            for (var sx = ctx.lineWidth / 2; sx <= root.width - ctx.lineWidth / 2; sx += 1) {
                var waveY = centerY + amp * Math.sin(freq * 2 * Math.PI * sx / root.fullLength + phase);
                if (sx === ctx.lineWidth / 2)
                    ctx.moveTo(sx, waveY);
                else
                    ctx.lineTo(sx, waveY);
            }
            ctx.stroke();
            return;
        }

        // CAVA visualizer — selectable styles.
        ctx.fillStyle = root.color;
        var maxVal = 100.0; // matching ascii_max_range in cava config
        var slot = width / root.numBars;

        function normAt(idx, exp) {
            var v = (root.barHeights[idx] || 0) / maxVal;
            if (v < 0)
                v = 0;
            if (v > 1)
                v = 1;
            return exp !== 1 ? Math.pow(v, exp) : v;
        }

        if (root.cavaStyle === "smooth") {
            // Previous look: thinner rounded bars, centered, linear response.
            var sbw = Math.max(2, slot * 0.5);
            for (var si = 0; si < root.numBars; si++) {
                var sh = Math.max(2, normAt(si, 1) * height);
                ctx.beginPath();
                ctx.roundedRect(si * slot + (slot - sbw) / 2, (height - sh) / 2, sbw, sh, sbw / 2, sbw / 2);
                ctx.fill();
            }
        } else if (root.cavaStyle === "bars") {
            // Classic equalizer: sharp bars grounded at the bottom, growing up.
            var gbw = Math.max(2, slot * 0.7);
            for (var gi = 0; gi < root.numBars; gi++) {
                var gh = Math.max(2, normAt(gi, 1.3) * height);
                ctx.fillRect(gi * slot + (slot - gbw) / 2, height - gh, gbw, gh);
            }
        } else if (root.cavaStyle === "dots") {
            // A dot per band that rises with the level.
            var r = Math.max(2, Math.min(slot * 0.34, height * 0.45));
            for (var di = 0; di < root.numBars; di++) {
                var dcx = di * slot + slot / 2;
                var dcy = height - r - normAt(di, 1) * (height - 2 * r);
                ctx.beginPath();
                ctx.arc(dcx, dcy, r, 0, 2 * Math.PI);
                ctx.fill();
            }
        } else if (root.cavaStyle === "waves") {
            // Traveling wave of rounded bars (like the mic slider), amplitude
            // following the audio energy so it animates with the music.
            var energy = 0;
            for (var ei = 0; ei < root.numBars; ei++)
                energy += (root.barHeights[ei] || 0);
            energy = energy / (root.numBars * maxVal); // 0..1
            var level = Math.max(0.15, Math.min(1, energy * 2.2));
            var tt = Date.now() / 220.0;
            var wbw = Math.max(2, slot * 0.6);
            for (var wi = 0; wi < root.numBars; wi++) {
                var wv = 0.5 + 0.5 * Math.sin(tt + wi * 0.55);
                var wh = (0.18 + 0.72 * wv * (0.35 + 0.65 * level)) * height;
                if (wh < 2)
                    wh = 2;
                ctx.beginPath();
                ctx.roundedRect(wi * slot + (slot - wbw) / 2, (height - wh) / 2, wbw, wh, wbw / 2, wbw / 2);
                ctx.fill();
            }
        } else {
            // "blocks" (default): brutalist sharp thick bars, dry exaggerated peaks, centered.
            var bbw = Math.max(2, slot * 0.7);
            for (var bi = 0; bi < root.numBars; bi++) {
                var bh = Math.max(2, normAt(bi, 1.45) * height);
                ctx.fillRect(bi * slot + (slot - bbw) / 2, (height - bh) / 2, bbw, bh);
            }
        }
    }
}
