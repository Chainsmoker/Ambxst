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

    // Legacy compatibility
    property real amplitude: lineWidth * amplitudeMultiplier
    property real speed: 5
    property bool animationsEnabled: true

    // =========================================================================
    // Visualizer Config
    // =========================================================================
    property int numBars: 12
    property var barHeights: [0,0,0,0,0,0,0,0,0,0,0,0]

    // =========================================================================
    // CAVA Process (Real-time analyzer)
    // =========================================================================
    Process {
        id: cavaProcess
        // Only run CAVA when music is active/playing and widget is visible
        running: root.running && root.visible && root.active
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/cava/visualizer.conf"]

        stdout: SplitParser {
            onRead: data => {
                var heights = data.trim().split(';').map(Number);
                // CAVA raw ascii output ends with a trailing semicolon, producing an extra empty element.
                // We pop the last element if it is NaN.
                if (heights.length > 0 && isNaN(heights[heights.length - 1])) {
                    heights.pop();
                }
                if (heights.length === root.numBars) {
                    // Validate values
                    for (var i = 0; i < root.numBars; i++) {
                        if (isNaN(heights[i])) heights[i] = 0;
                    }
                    root.barHeights = heights;
                    root.requestPaint();
                }
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

        ctx.fillStyle = root.color;

        var barW = root.lineWidth;
        // Calculate spacing evenly across the canvas width
        var spacing = (width - (root.numBars * barW)) / (root.numBars - 1);
        if (spacing < 1) spacing = 1;

        var maxVal = 100.0; // matching ascii_max_range in cava config

        for (var i = 0; i < root.numBars; i++) {
            var barX = i * (barW + spacing);
            var rawH = root.barHeights[i] || 0;
            var hVal = (rawH / maxVal) * height;

            // Minimum height for aesthetic presence
            if (hVal < 2) hVal = 2;
            // Cap height
            if (hVal > height) hVal = height;

            var y = (height - hVal) / 2;

            ctx.beginPath();
            ctx.roundedRect(barX, y, barW, hVal, barW / 2, barW / 2);
            ctx.fill();
        }
    }
}
