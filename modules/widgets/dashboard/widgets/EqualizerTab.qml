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

    Component.onCompleted: {
        EasyEffectsService.initialize();
        // Load initial flat values
        loadPresetGains(presets["Flat"]);
    }

    // Band frequencies
    readonly property var frequencies: ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    // Sliders array reference to easily access values
    property var sliders: [s0, s1, s2, s3, s4, s5, s6, s7, s8, s9]

    // Predefined preset gain values (in dB, from -12 to +12)
    readonly property var presets: ({
        "Flat":    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        "Bass":    [6.0, 5.0, 4.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        "Treble":  [0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 4.0, 5.0, 6.0, 6.0],
        "Vocal":   [-2.0, -2.0, -1.0, 0.0, 2.0, 4.0, 4.0, 2.0, 0.0, -1.0],
        "Pop":     [-1.5, -1.0, 0.0, 2.0, 4.0, 4.0, 2.0, 0.0, -1.0, -1.5],
        "Rock":    [4.0, 3.0, 2.0, -1.0, -2.0, -1.0, 2.0, 3.0, 4.0, 4.0],
        "Jazz":    [3.0, 2.0, 1.0, 2.0, -1.0, -1.0, 0.0, 1.0, 2.0, 3.0],
        "Classic": [4.0, 3.0, 2.0, 2.0, -1.0, -1.0, 0.0, 2.0, 3.0, 4.0]
    })

    property string activePreset: "Flat"

    function loadPresetGains(gainsList) {
        for (let i = 0; i < 10; i++) {
            // Map dB (-12 to +12) to normalized slider value (0.0 to 1.0)
            let db = gainsList[i];
            let normVal = (db / 24.0) + 0.5;
            sliders[i].value = normVal;
        }
        canvas.requestPaint();
        debounceTimer.restart();
    }

    // Debounce timer to prevent spamming EasyEffects with file write operations
    Timer {
        id: debounceTimer
        interval: 200
        repeat: false
        onTriggered: {
            let gains = [];
            for (let i = 0; i < 10; i++) {
                // Map normalized slider value back to dB
                let norm = sliders[i].value;
                let db = (norm - 0.5) * 24.0;
                gains.push(db);
            }
            if (EasyEffectsService.available) {
                EasyEffectsService.applyEqualizer(gains);
            }
        }
    }

    function onSliderChanged() {
        activePreset = ""; // custom EQ curve
        canvas.requestPaint();
        debounceTimer.restart();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // Title and bypass controls
        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 2
                Text {
                    text: "Equalizer"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(2)
                    font.weight: Font.Bold
                    color: Colors.overBackground
                }
                Text {
                    text: EasyEffectsService.available ? (EasyEffectsService.bypassed ? "Equalizer bypassed" : "PipeWire EasyEffects active") : "EasyEffects not running"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.overBackground
                    opacity: 0.7
                }
            }

            Item { Layout.fillWidth: true }

            // Bypass toggle button
            Button {
                id: bypassBtn
                Layout.preferredHeight: 36
                Layout.preferredWidth: 100
                flat: true
                hoverEnabled: true
                enabled: EasyEffectsService.available

                background: StyledRect {
                    anchors.fill: parent
                    radius: Styling.radius(4)
                    variant: !EasyEffectsService.bypassed ? "primary" : (bypassBtn.hovered ? "focus" : "common")
                }

                contentItem: Text {
                    text: EasyEffectsService.bypassed ? "Enable" : "Bypass"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    font.bold: true
                    color: !EasyEffectsService.bypassed ? Styling.srItem("primary") : Colors.overBackground
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    EasyEffectsService.toggleBypass();
                }
            }
        }

        // Sliders View with curve drawing behind
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Canvas {
                id: canvas
                anchors.fill: parent
                z: 0

                onPaint: {
                    let ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    if (width <= 0 || height <= 0) return;

                    ctx.strokeStyle = Colors.primary;
                    ctx.lineWidth = 3;
                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";

                    // Drawing settings
                    let points = [];
                    let count = 10;
                    let spacing = width / count;
                    let startX = spacing / 2;

                    for (let i = 0; i < count; i++) {
                        let x = startX + i * spacing;
                        // Slider goes from top to bottom
                        // ProgressRatio is 0 at bottom, 1 at top
                        let ratio = sliders[i].progressRatio;
                        let sliderHeight = 180;
                        // Vertical center is around (height - sliderHeight)/2
                        let sliderTop = (height - sliderHeight) / 2;
                        let y = sliderTop + (1.0 - ratio) * sliderHeight;
                        points.push({x: x, y: y});
                    }

                    // Draw smooth curve using cubic bezier curves
                    ctx.beginPath();
                    ctx.moveTo(points[0].x, points[0].y);

                    for (let i = 0; i < points.length - 1; i++) {
                        let xc = (points[i].x + points[i + 1].x) / 2;
                        let yc = (points[i].y + points[i + 1].y) / 2;
                        ctx.quadraticCurveTo(points[i].x, points[i].y, xc, yc);
                    }
                    ctx.lineTo(points[points.length - 1].x, points[points.length - 1].y);
                    ctx.stroke();

                    // Fill gradient area below the curve
                    let grad = ctx.createLinearGradient(0, 0, 0, height);
                    let primaryHex = Colors.primary;
                    grad.addColorStop(0, primaryHex + "40"); // 25% opacity
                    grad.addColorStop(1, primaryHex + "00"); // 0% opacity
                    ctx.fillStyle = grad;

                    ctx.lineTo(points[points.length - 1].x, height);
                    ctx.lineTo(points[0].x, height);
                    ctx.closePath();
                    ctx.fill();
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0
                z: 1

                Repeater {
                    model: 10
                    delegate: Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8

                            StyledSlider {
                                id: sliderInstance
                                vertical: true
                                size: 180
                                thickness: 4
                                resizeParent: true
                                progressColor: Colors.primary
                                backgroundColor: Colors.surfaceVariant
                                tooltip: false

                                Component.onCompleted: {
                                    // Assign reference
                                    if (index === 0) s0 = sliderInstance;
                                    else if (index === 1) s1 = sliderInstance;
                                    else if (index === 2) s2 = sliderInstance;
                                    else if (index === 3) s3 = sliderInstance;
                                    else if (index === 4) s4 = sliderInstance;
                                    else if (index === 5) s5 = sliderInstance;
                                    else if (index === 6) s6 = sliderInstance;
                                    else if (index === 7) s7 = sliderInstance;
                                    else if (index === 8) s8 = sliderInstance;
                                    else if (index === 9) s9 = sliderInstance;
                                }

                                onValueChanged: {
                                    root.onSliderChanged();
                                }
                            }

                            Text {
                                text: root.frequencies[index]
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.bold: true
                                color: Colors.overBackground
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: {
                                    let db = (sliderInstance.progressRatio - 0.5) * 24.0;
                                    return (db > 0 ? "+" : "") + db.toFixed(1) + " dB";
                                }
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overBackground
                                opacity: 0.6
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }
            }
        }

        // Preset grid selection
        GridLayout {
            columns: 4
            rowSpacing: 8
            columnSpacing: 8
            Layout.fillWidth: true
            Layout.preferredHeight: 90

            Repeater {
                model: ["Flat", "Bass", "Treble", "Vocal", "Pop", "Rock", "Jazz", "Classic"]
                delegate: Button {
                    id: presetBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    flat: true
                    hoverEnabled: true

                    background: StyledRect {
                        anchors.fill: parent
                        radius: Styling.radius(3)
                        variant: root.activePreset === modelData ? "primary" : (presetBtn.hovered ? "focus" : "common")
                    }

                    contentItem: Text {
                        text: modelData
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        font.bold: root.activePreset === modelData
                        color: root.activePreset === modelData ? Styling.srItem("primary") : Colors.overBackground
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        root.activePreset = modelData;
                        root.loadPresetGains(root.presets[modelData]);
                    }
                }
            }
        }
    }

    // Sliders instances dummy properties for references
    property var s0
    property var s1
    property var s2
    property var s3
    property var s4
    property var s5
    property var s6
    property var s7
    property var s8
    property var s9
}
