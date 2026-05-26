pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.globals
import qs.config

// Overlay de anotación en vivo: dibujás sobre el escritorio (que sigue corriendo
// debajo) con una paleta-notch pegada al borde izquierdo. Patrón clonado de
// ScreenshotTool (overlay layer-shell fullscreen + foco exclusivo).
PanelWindow {
    id: paint

    required property var targetScreen
    screen: targetScreen

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst:paint"
    // Mientras cede a la tool de captura: suelta el teclado (deja que la maneje ella)
    WlrLayershell.keyboardFocus: (paint.visible && !paint.yielding) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // "Ceder": cuando se abre la tool de captura del sistema, paint oculta su UI y
    // suelta el input (pero deja el canvas visible para que grim capture los trazos).
    readonly property bool yielding: GlobalStates.screenshotToolVisible

    visible: GlobalStates.paintToolVisible

    // ── Estado del dibujo ──────────────────────────────────────────────
    // tool: pen | marker | line | rect | ellipse | arrow | number | text
    property string tool: "pen"
    property color drawColor: Colors.primary
    property int strokeWidth: 8

    // Cada op: { tool, color (string), width, points: [{x,y}, ...], n?, text? }
    property var ops: []
    property var redoStack: []
    property var currentOp: null
    property int numberCounter: 1

    // Edición de texto: punto activo mientras se escribe (null = no editando)
    property var editPoint: null

    // Freeze: captura un fondo estático para anotar sin que se mueva lo de abajo
    property bool frozen: false
    property string frozenSource: ""

    // Cierre tras ceder: cuando la tool de captura se abre y luego se cierra, paint ya
    // cumplió (los trazos quedaron en la captura) → cerrarse para liberar el preview.
    property bool _wasYielding: false
    onYieldingChanged: {
        if (paint.yielding)
            paint._wasYielding = true;
        else if (paint._wasYielding)
            paint.close();
    }

    // Asegura que el dir de screenshots exista (xdg-user-dir + mkdir -p) cuanto antes
    Component.onCompleted: Screenshot.initialize()

    function close() {
        GlobalStates.paintToolVisible = false;
    }

    function commitOp(op) {
        ops = ops.concat([op]);
        redoStack = [];
        if (op.tool === "number")
            numberCounter += 1;
        baseCanvas.requestPaint();
    }

    function clearAll() {
        ops = [];
        redoStack = [];
        numberCounter = 1;
        baseCanvas.requestPaint();
    }

    function undo() {
        if (ops.length === 0)
            return;
        const last = ops[ops.length - 1];
        ops = ops.slice(0, ops.length - 1);
        redoStack = redoStack.concat([last]);
        if (last.tool === "number")
            numberCounter = Math.max(1, numberCounter - 1);
        baseCanvas.requestPaint();
    }

    function redo() {
        if (redoStack.length === 0)
            return;
        const op = redoStack[redoStack.length - 1];
        redoStack = redoStack.slice(0, redoStack.length - 1);
        ops = ops.concat([op]);
        if (op.tool === "number")
            numberCounter += 1;
        baseCanvas.requestPaint();
    }

    // ── Edición de texto ──
    function startTextEdit(x, y) {
        editPoint = { x: x, y: y };
        textEditor.text = "";
        Qt.callLater(() => textEditor.forceActiveFocus());
    }

    function commitText() {
        if (editPoint && textEditor.text.length > 0) {
            commitOp({
                tool: "text",
                color: drawColor.toString(),
                width: strokeWidth,
                points: [{ x: editPoint.x, y: editPoint.y }],
                text: textEditor.text
            });
        }
        editPoint = null;
        textEditor.text = "";
        scope.forceActiveFocus();
    }

    function cancelText() {
        editPoint = null;
        textEditor.text = "";
        scope.forceActiveFocus();
    }

    function toggleFreeze() {
        if (frozen) {
            frozen = false;
            frozenSource = "";
        } else {
            Screenshot.initialize();
            Screenshot.freezeScreen();
        }
    }

    // 📷 → cede a la tool de captura del sistema (región/ventana/pantalla).
    // grim captura escritorio + trazos (la paleta ya se ocultó por `yielding`); paint
    // se cierra al terminar la captura (ver onYieldingChanged) liberando el preview.
    function captureViaTool() {
        if (editPoint !== null)
            commitText();
        Screenshot.initialize();
        Screenshot.captureMode = "region";
        GlobalStates.screenshotToolVisible = true;
    }

    // Devuelve negro/blanco según contraste con un color (para texto sobre badge)
    function contrastColor(colStr) {
        const c = Qt.color(colStr);
        const lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
        return lum > 0.55 ? "#000000" : "#ffffff";
    }

    // Dibuja una op en un contexto 2D dado (compartido por base + live canvas).
    function paintOp(ctx, op) {
        if (!op || !op.points || op.points.length === 0)
            return;
        ctx.globalAlpha = 1;
        ctx.strokeStyle = op.color;
        ctx.fillStyle = op.color;
        ctx.lineWidth = op.width;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";

        const p = op.points;
        const a = p[0];
        const b = p[p.length - 1];

        if (op.tool === "pen") {
            ctx.beginPath();
            ctx.moveTo(p[0].x, p[0].y);
            for (let i = 1; i < p.length; i++)
                ctx.lineTo(p[i].x, p[i].y);
            ctx.stroke();
        } else if (op.tool === "marker") {
            // Resaltador: trazo grueso semi-transparente, una sola pasada (alpha uniforme)
            ctx.globalAlpha = 0.35;
            ctx.lineWidth = op.width * 3;
            ctx.beginPath();
            ctx.moveTo(p[0].x, p[0].y);
            for (let i = 1; i < p.length; i++)
                ctx.lineTo(p[i].x, p[i].y);
            ctx.stroke();
            ctx.globalAlpha = 1;
        } else if (op.tool === "line") {
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
        } else if (op.tool === "rect") {
            ctx.strokeRect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y));
        } else if (op.tool === "ellipse") {
            const cx = (a.x + b.x) / 2;
            const cy = (a.y + b.y) / 2;
            const rx = Math.abs(b.x - a.x) / 2;
            const ry = Math.abs(b.y - a.y) / 2;
            ctx.beginPath();
            ctx.ellipse(cx - rx, cy - ry, rx * 2, ry * 2);
            ctx.stroke();
        } else if (op.tool === "arrow") {
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
            const ang = Math.atan2(b.y - a.y, b.x - a.x);
            const head = Math.max(op.width * 3.5, 16);
            ctx.beginPath();
            ctx.moveTo(b.x, b.y);
            ctx.lineTo(b.x - head * Math.cos(ang - Math.PI / 6), b.y - head * Math.sin(ang - Math.PI / 6));
            ctx.moveTo(b.x, b.y);
            ctx.lineTo(b.x - head * Math.cos(ang + Math.PI / 6), b.y - head * Math.sin(ang + Math.PI / 6));
            ctx.stroke();
        } else if (op.tool === "number") {
            // Badge numerado: círculo relleno + número contrastante
            const r = Math.max(op.width * 2.2, 15);
            ctx.beginPath();
            ctx.arc(a.x, a.y, r, 0, 2 * Math.PI);
            ctx.fill();
            ctx.fillStyle = paint.contrastColor(op.color);
            ctx.font = "bold " + Math.round(r * 1.2) + "px sans-serif";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText(String(op.n), a.x, a.y);
        } else if (op.tool === "text") {
            const fs = Math.max(op.width * 3, 16);
            ctx.font = "bold " + fs + "px sans-serif";
            ctx.textAlign = "left";
            ctx.textBaseline = "top";
            ctx.fillText(op.text || "", a.x, a.y);
        }
    }

    // ── Freeze: escuchar la captura por monitor (igual que ScreenshotTool) ──
    Connections {
        target: Screenshot
        function onMonitorScreenshotReady(monitorName, path) {
            // Ignorar cuando cedemos: ese freeze es de la tool de captura, no del botón freeze
            if (paint.yielding)
                return;
            if (monitorName === paint.targetScreen.name) {
                paint.frozenSource = "file://" + path;
                paint.frozen = true;
            }
        }
    }

    // El overlay captura todo el input mientras dibujás; al ceder suelta el input
    // (máscara vacía → click-through) para que la tool de captura lo reciba.
    mask: Region {
        item: (paint.visible && !paint.yielding) ? fullMask : emptyMask
    }
    Item {
        id: fullMask
        anchors.fill: parent
    }
    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    FocusGrab {
        id: focusGrab
        windows: [paint]
        active: paint.visible && !paint.yielding
    }

    FocusScope {
        id: scope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: paint.close()

        // Fondo congelado + trazos. Sigue visible al ceder (sin la paleta) para que
        // grim capture escritorio + anotaciones cuando corre la tool de captura.
        Item {
            id: captureArea
            anchors.fill: parent

            // 1. Fondo congelado (solo si frozen)
            Image {
                id: frozenImage
                anchors.fill: parent
                fillMode: Image.Stretch
                mipmap: true
                visible: paint.frozen && paint.frozenSource !== ""
                source: paint.frozenSource
            }

            // 2. Lienzo de trazos confirmados (se repinta al confirmar/undo/clear)
            Canvas {
                id: baseCanvas
                anchors.fill: parent
                renderStrategy: Canvas.Cooperative
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    for (let i = 0; i < paint.ops.length; i++)
                        paint.paintOp(ctx, paint.ops[i]);
                }
            }

            // 3. Lienzo en vivo (sólo la op en progreso, repinta en cada movimiento)
            Canvas {
                id: liveCanvas
                anchors.fill: parent
                renderStrategy: Canvas.Cooperative
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    if (paint.currentOp)
                        paint.paintOp(ctx, paint.currentOp);
                }
            }
        }

        // 4. Captura del dibujo (deshabilitada mientras se escribe texto o se cede)
        MouseArea {
            id: drawArea
            anchors.fill: parent
            enabled: paint.editPoint === null && !paint.yielding
            hoverEnabled: true
            cursorShape: paint.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
            acceptedButtons: Qt.LeftButton

            readonly property bool freehand: paint.tool === "pen" || paint.tool === "marker"

            onPressed: mouse => {
                if (paint.tool === "text") {
                    paint.startTextEdit(mouse.x, mouse.y);
                    return;
                }
                paint.currentOp = {
                    tool: paint.tool,
                    color: paint.drawColor.toString(),
                    width: paint.strokeWidth,
                    points: [{ x: mouse.x, y: mouse.y }]
                };
                if (paint.tool === "number")
                    paint.currentOp.n = paint.numberCounter;
                liveCanvas.requestPaint();
            }

            onPositionChanged: mouse => {
                if (!paint.currentOp)
                    return;
                const op = paint.currentOp;
                if (drawArea.freehand) {
                    op.points.push({ x: mouse.x, y: mouse.y });
                } else if (op.tool !== "number") {
                    // line/rect/ellipse/arrow: sólo importan inicio + fin
                    if (op.points.length === 1)
                        op.points.push({ x: mouse.x, y: mouse.y });
                    else
                        op.points[1] = { x: mouse.x, y: mouse.y };
                }
                liveCanvas.requestPaint();
            }

            onReleased: {
                if (!paint.currentOp)
                    return;
                const op = paint.currentOp;
                // number = click coloca; el resto requiere un trazo real
                const real = (op.tool === "number") ? true : op.points.length > 1;
                if (real)
                    paint.commitOp(op);
                paint.currentOp = null;
                liveCanvas.requestPaint();
            }
        }

        // 4b. Editor de texto en vivo (fuera de captureArea: lo confirmado se pinta al canvas)
        TextInput {
            id: textEditor
            visible: paint.editPoint !== null
            x: paint.editPoint ? paint.editPoint.x : 0
            y: paint.editPoint ? paint.editPoint.y : 0
            color: paint.drawColor
            font.family: Config.theme.font
            font.bold: true
            font.pixelSize: Math.max(paint.strokeWidth * 3, 16)
            cursorVisible: true
            onAccepted: paint.commitText()
            onActiveFocusChanged: {
                if (!activeFocus && paint.editPoint !== null)
                    paint.commitText();
            }
            Keys.onEscapePressed: event => {
                paint.cancelText();
                event.accepted = true;
            }
        }

        // 5. Paleta-notch pegada al borde izquierdo, centrada verticalmente.
        // Se oculta al ceder para no aparecer en la captura.
        StyledRect {
            id: palette
            variant: "popup"
            enableShadow: true
            enableBorder: true
            visible: !paint.yielding

            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter

            width: 64
            implicitHeight: paletteCol.implicitHeight + 24
            height: implicitHeight

            // Animación de entrada desde el borde (nace fuera y entra al montarse)
            property bool entered: false
            Component.onCompleted: entered = true
            transform: Translate {
                x: palette.entered ? 0 : -(palette.width + 24)
                Behavior on x {
                    NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                }
            }

            // Consumir input sobre la paleta para no dibujar debajo de ella
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.AllButtons
            }

            Column {
                id: paletteCol
                anchors.centerIn: parent
                width: 48
                spacing: 8

                // ── Freeze ──
                PaintButton {
                    glyph: Icons.image
                    active: paint.frozen
                    accent: Colors.tertiary
                    activeContent: Colors.overTertiary
                    onClicked: paint.toggleFreeze()
                }

                Rectangle { width: 36; height: 1; color: Colors.outline; anchors.horizontalCenter: parent.horizontalCenter; opacity: 0.4 }

                // ── Herramientas ──
                PaintButton {
                    glyph: Icons.paintBrush
                    active: paint.tool === "pen"
                    onClicked: paint.tool = "pen"
                }
                PaintButton {
                    active: paint.tool === "marker"
                    onClicked: paint.tool = "marker"
                    // Ícono dibujado: barra de resaltador
                    Rectangle {
                        anchors.centerIn: parent
                        width: 22; height: 9
                        radius: 3
                        color: parent.contentColor
                        opacity: 0.55
                    }
                }
                PaintButton {
                    active: paint.tool === "line"
                    onClicked: paint.tool = "line"
                    // Ícono dibujado: línea diagonal
                    Rectangle {
                        anchors.centerIn: parent
                        width: 24; height: 2.5
                        radius: 2
                        color: parent.contentColor
                        rotation: -35
                    }
                }
                PaintButton {
                    active: paint.tool === "rect"
                    onClicked: paint.tool = "rect"
                    // Ícono dibujado: rectángulo
                    Rectangle {
                        anchors.centerIn: parent
                        width: 20; height: 15
                        color: "transparent"
                        radius: 2
                        border.width: 2
                        border.color: parent.contentColor
                    }
                }
                PaintButton {
                    glyph: Icons.circle
                    active: paint.tool === "ellipse"
                    onClicked: paint.tool = "ellipse"
                }
                PaintButton {
                    glyph: Icons.arrowRight
                    active: paint.tool === "arrow"
                    onClicked: paint.tool = "arrow"
                }
                PaintButton {
                    active: paint.tool === "number"
                    onClicked: paint.tool = "number"
                    // Ícono dibujado: badge "1"
                    Text {
                        anchors.centerIn: parent
                        text: "1"
                        font.family: Config.theme.font
                        font.pixelSize: 18
                        font.weight: Font.ExtraBold
                        color: parent.contentColor
                    }
                }
                PaintButton {
                    glyph: Icons.textT
                    active: paint.tool === "text"
                    onClicked: paint.tool = "text"
                }

                Rectangle { width: 36; height: 1; color: Colors.outline; anchors.horizontalCenter: parent.horizontalCenter; opacity: 0.4 }

                // ── Colores ──
                Grid {
                    anchors.horizontalCenter: parent.horizontalCenter
                    columns: 2
                    spacing: 6
                    Repeater {
                        model: [Colors.primary, Colors.tertiary, Colors.error, Colors.white, Colors.green, Colors.blue]
                        delegate: Rectangle {
                            required property color modelData
                            width: 18; height: 18; radius: 9
                            color: modelData
                            border.width: paint.drawColor.toString() === modelData.toString() ? 3 : 1
                            border.color: paint.drawColor.toString() === modelData.toString() ? Colors.overBackground : Colors.outline
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: paint.drawColor = parent.modelData
                            }
                        }
                    }
                }

                Rectangle { width: 36; height: 1; color: Colors.outline; anchors.horizontalCenter: parent.horizontalCenter; opacity: 0.4 }

                // ── Grosor (presets) ──
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Repeater {
                        model: [4, 8, 16]
                        delegate: Rectangle {
                            required property int modelData
                            width: 22; height: 22; radius: 11
                            color: paint.strokeWidth === modelData ? Colors.primary : "transparent"
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.modelData * 0.8 + 2
                                height: width
                                radius: width / 2
                                color: paint.strokeWidth === parent.modelData ? Colors.overPrimary : Colors.overBackground
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: paint.strokeWidth = parent.modelData
                            }
                        }
                    }
                }

                Rectangle { width: 36; height: 1; color: Colors.outline; anchors.horizontalCenter: parent.horizontalCenter; opacity: 0.4 }

                // ── Acciones ──
                PaintButton {
                    glyph: Icons.arrowCounterClockwise
                    onClicked: paint.undo()
                }
                PaintButton {
                    glyph: Icons.arrowCounterClockwise
                    mirror: true
                    onClicked: paint.redo()
                }
                PaintButton {
                    glyph: Icons.broom
                    onClicked: paint.clearAll()
                }
                PaintButton {
                    glyph: Icons.camera
                    accent: Colors.tertiary
                    activeContent: Colors.overTertiary
                    onClicked: paint.captureViaTool()
                }
                PaintButton {
                    glyph: Icons.cancel
                    accent: Colors.error
                    onClicked: paint.close()
                }
            }
        }
    }

    // Botón cuadrado reutilizable de la paleta
    component PaintButton: Rectangle {
        id: btn
        property string glyph: ""
        property bool active: false
        property bool mirror: false
        property color accent: Colors.primary
        property color activeContent: Colors.overPrimary
        readonly property color contentColor: active ? btn.activeContent : Colors.overBackground
        signal clicked

        anchors.horizontalCenter: parent.horizontalCenter
        width: 40
        height: 40
        radius: Styling.radius(6)
        color: active ? btn.accent : (mouse.containsMouse ? Colors.surfaceContainerHighest : "transparent")

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Text {
            id: glyphText
            anchors.centerIn: parent
            visible: btn.glyph !== ""
            text: btn.glyph
            font.family: Icons.font
            font.pixelSize: 18
            color: btn.contentColor
            transform: Scale {
                origin.x: glyphText.width / 2
                xScale: btn.mirror ? -1 : 1
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
