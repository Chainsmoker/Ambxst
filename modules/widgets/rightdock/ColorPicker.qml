pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.modules.theme
import qs.modules.components

Item {
    id: root

    property real hue: 0      // 0..1
    property real sat: 1      // 0..1
    property real val: 1      // 0..1

    readonly property color pureHueColor: Qt.hsva(hue, 1, 1, 1)
    readonly property color resultColor: Qt.hsva(hue, sat, val, 1)
    readonly property string hexValue: {
        function pad(n) { let s = Math.round(n * 255).toString(16); return s.length < 2 ? "0" + s : s; }
        return "#" + pad(resultColor.r) + pad(resultColor.g) + pad(resultColor.b);
    }

    implicitWidth: 300
    implicitHeight: column.implicitHeight

    function setFromHex(hex) {
        let s = hex.trim().replace(/^#/, "");
        if (s.length === 3) s = s.split("").map(c => c + c).join("");
        if (s.length !== 6) return false;
        let r = parseInt(s.substr(0, 2), 16) / 255;
        let g = parseInt(s.substr(2, 2), 16) / 255;
        let b = parseInt(s.substr(4, 2), 16) / 255;
        if (isNaN(r) || isNaN(g) || isNaN(b)) return false;
        let max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
        let h = 0;
        if (d !== 0) {
            if (max === r) h = ((g - b) / d) % 6;
            else if (max === g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h /= 6;
            if (h < 0) h += 1;
        }
        let v = max;
        let sat = max === 0 ? 0 : d / max;
        root.hue = h;
        root.sat = sat;
        root.val = v;
        return true;
    }

    function setFromColor(c) {
        let pad = n => { let s = Math.round(n * 255).toString(16); return s.length < 2 ? "0" + s : s; };
        root.setFromHex("#" + pad(c.r) + pad(c.g) + pad(c.b));
    }

    Component.onCompleted: setFromColor(Colors.primary)

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        // ── SV square ──────────────────────────────────────────────
        Item {
            id: svSquare
            Layout.fillWidth: true
            Layout.preferredHeight: width * 0.6
            clip: true

            // Horizontal gradient: white -> pure hue
            Rectangle {
                anchors.fill: parent
                radius: Styling.radius(2)
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "white" }
                    GradientStop { position: 1; color: root.pureHueColor }
                }
            }
            // Vertical gradient: transparent -> black
            Rectangle {
                anchors.fill: parent
                radius: Styling.radius(2)
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "black" }
                }
            }
            // Crosshair pointer
            Rectangle {
                id: svPointer
                width: 14
                height: 14
                radius: 7
                color: "transparent"
                border.color: "white"
                border.width: 2
                x: root.sat * (svSquare.width - width)
                y: (1 - root.val) * (svSquare.height - height)
                Behavior on x { enabled: !svMouse.pressed; NumberAnimation { duration: 80 } }
                Behavior on y { enabled: !svMouse.pressed; NumberAnimation { duration: 80 } }

                Rectangle {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    radius: 5
                    color: "transparent"
                    border.color: "black"
                    border.width: 1
                }
            }
            MouseArea {
                id: svMouse
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                preventStealing: true

                function updateFromMouse(mx, my) {
                    let s = Math.max(0, Math.min(1, mx / svSquare.width));
                    let v = 1 - Math.max(0, Math.min(1, my / svSquare.height));
                    root.sat = s;
                    root.val = v;
                }

                onPressed: e => updateFromMouse(e.x, e.y)
                onPositionChanged: e => { if (pressed) updateFromMouse(e.x, e.y); }
            }
        }

        // ── Hue slider ─────────────────────────────────────────────
        Item {
            id: hueSlider
            Layout.fillWidth: true
            Layout.preferredHeight: 16

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.00; color: "#ff0000" }
                    GradientStop { position: 0.17; color: "#ffff00" }
                    GradientStop { position: 0.33; color: "#00ff00" }
                    GradientStop { position: 0.50; color: "#00ffff" }
                    GradientStop { position: 0.67; color: "#0000ff" }
                    GradientStop { position: 0.83; color: "#ff00ff" }
                    GradientStop { position: 1.00; color: "#ff0000" }
                }
            }
            Rectangle {
                id: hueThumb
                width: 18
                height: 18
                radius: 9
                color: root.pureHueColor
                border.color: "white"
                border.width: 2
                y: (hueSlider.height - height) / 2
                Behavior on x { enabled: !hueMouse.pressed; NumberAnimation { duration: 80 } }
            }
            Binding {
                target: hueThumb
                property: "x"
                value: root.hue * (hueSlider.width - hueThumb.width)
            }

            MouseArea {
                id: hueMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                onPressed: e => root.hue = Math.max(0, Math.min(1, e.x / hueSlider.width))
                onPositionChanged: e => { if (pressed) root.hue = Math.max(0, Math.min(1, e.x / hueSlider.width)); }
            }
        }

        // ── Preview + hex input ───────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: Styling.radius(3)
                color: root.resultColor
                border.color: Colors.outline
                border.width: 1
            }

            StyledRect {
                variant: "internalbg"
                radius: Styling.radius(3)
                Layout.fillWidth: true
                Layout.preferredHeight: 36

                TextInput {
                    id: hexInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.hexValue
                    color: Colors.overBackground
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(0)
                    selectByMouse: true
                    onEditingFinished: root.setFromHex(text)
                }
            }

            StyledRect {
                id: copyBtn
                variant: copyHover.containsMouse ? "focus" : "internalbg"
                radius: Styling.radius(3)
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36

                Text {
                    anchors.centerIn: parent
                    text: Icons.copy
                    font.family: "MaterialSymbolsRounded"
                    font.pixelSize: 18
                    color: Colors.overBackground
                }

                MouseArea {
                    id: copyHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["wl-copy", root.hexValue]);
                        Quickshell.execDetached(["notify-send", "Color copiado", root.hexValue]);
                    }
                }
            }
        }

        // ── Material palette quick-pick swatches ─────────────────
        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { name: "primary",   hex: Colors.primary },
                    { name: "secondary", hex: Colors.secondary },
                    { name: "tertiary",  hex: Colors.tertiary },
                    { name: "error",     hex: Colors.error },
                    { name: "surface",   hex: Colors.surface },
                    { name: "outline",   hex: Colors.outline },
                    { name: "primaryC",  hex: Colors.primaryContainer },
                    { name: "secondaryC",hex: Colors.secondaryContainer }
                ]

                Rectangle {
                    id: swatch
                    required property var modelData
                    width: 26
                    height: 26
                    radius: Styling.radius(2)
                    color: modelData.hex
                    border.color: Colors.outline
                    border.width: 1

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.setFromColor(swatch.modelData.hex)
                    }
                }
            }
        }
    }
}
