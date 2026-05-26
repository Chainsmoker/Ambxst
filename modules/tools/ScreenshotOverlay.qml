import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

PanelWindow {
    id: root

    // Screen property to be set by the Loader
    required property var targetScreen
    screen: targetScreen

    property string imagePath: ""
    // Destino permanente para el botón 💾 (la captura vive en /tmp hasta guardarse)
    property string savePath: ""
    // Si está fijado, el preview no se auto-oculta
    property bool pinned: false

    // Position: Top Right with margins
    anchors {
        right: true
        top: true
    }

    // Width/Height handled by content + margins
    implicitWidth: mainColumn.width + 20
    implicitHeight: mainColumn.height + 20

    color: "transparent"
    visible: imagePath !== ""

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property Process copyOverlayProcess: Process {
        id: copyOverlayProcess
        command: ["bash", "-c", "cat \"" + root.imagePath + "\" | wl-copy --type image/png"]
        onExited: exitCode => {
            if (exitCode !== 0) console.warn("Overlay Copy Failed (Exit code: " + exitCode + ")")
        }
    }

    // Timer to auto-hide after 5 seconds
    Timer {
        id: hideTimer
        interval: 5000
        repeat: false
        running: root.visible && !mouseAreaHover.containsMouse && !root.pinned
        onTriggered: root.imagePath = ""
    }

    // MouseArea to detect hover and prevent auto-hide
    MouseArea {
        id: mouseAreaHover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton // Pass clicks through
        propagateComposedEvents: true
    }

    // Listen for the saved signal from Screenshot service
    Connections {
        target: Screenshot
        function onImageSaved(path) {
            var s = root.targetScreen;
            var mx = Screenshot.selectionX;
            var my = Screenshot.selectionY;
            var logicalW = s.width;

            if (mx >= s.x && mx < (s.x + s.width) && my >= s.y && my < (s.y + s.height)) {
                root.imagePath = path;
                root.savePath = Screenshot.pendingSavePath;
            } else if (Screenshot.captureMode === "screen") {
                var cursor = Quickshell.cursor;
                if (cursor && cursor.screen && cursor.screen.name === s.name) {
                    root.imagePath = path;
                    root.savePath = Screenshot.pendingSavePath;
                }
            }
        }
    }

    Column {
        id: mainColumn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 20
        spacing: 8

        // Preview Image with Drag Support — tamaño FIJO (la imagen se recorta
        // para llenar la caja, así el preview no cambia de tamaño por captura)
        ClippingRectangle {
            id: imgContainer

            property real previewWidth: 320
            property real previewHeight: 200

            width: previewWidth
            height: previewHeight

            radius: Styling.radius(4)
            color: "transparent"
            border.width: 2
            border.color: Colors.primaryFixed

            Image {
                mipmap: true
                id: img
                anchors.fill: parent
                source: root.imagePath !== "" ? "file://" + root.imagePath : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true

                // Invisible item to handle the Drag attached property state
                Item {
                    id: dragTarget
                    Drag.active: dragArea.drag.active
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.mimeData: {
                        "text/uri-list": "file://" + root.imagePath
                    }
                    Drag.imageSource: img.source
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    hoverEnabled: true

                    // Show Grab Hand
                    cursorShape: Qt.DragCopyCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

                    // Bind drag target to initiate the drag sequence
                    drag.target: dragTarget

                    // Click to Open (Left) or Delete (Middle)
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) {
                            var proc = Qt.createQmlObject('import Quickshell; import Quickshell.Io; Process { }', root);
                            proc.command = ["rm", root.imagePath];
                            proc.running = true;
                            root.imagePath = "";
                        } else {
                            Qt.openUrlExternally("file://" + root.imagePath);
                        }
                    }
                }

                // Icon overlay on hover (optional, but requested "Icons.handGrab" context)
                Rectangle {
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    radius: 16
                    color: Colors.background
                    opacity: dragArea.containsMouse ? 0.8 : 0
                    visible: opacity > 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: Icons.handGrab // Assuming this exists per user request
                        font.family: Icons.font
                        color: Colors.overBackground
                    }
                }
            }
        }

        // Action Buttons — en fila, centrados debajo del preview
        Item {
            width: imgContainer.width
            height: 36

            Row {
                anchors.centerIn: parent
                spacing: 6

            // Copy
            ActionButton {
                icon: Icons.copy
                onTriggered: {
                    copyOverlayProcess.running = true
                }

                StyledToolTip {
                    show: parent.containsMouse
                    tooltipText: "Copy"
                }
            }

            ActionButton {
                icon: Icons.disk
                onTriggered: {
                    // Guardar al disco permanente (la captura vive en /tmp)
                    if (root.savePath !== "") {
                        var proc = Qt.createQmlObject('import Quickshell; import Quickshell.Io; Process { }', root);
                        proc.command = ["cp", root.imagePath, root.savePath];
                        proc.running = true;
                    }
                    root.imagePath = ""; // Hide overlay
                }
                StyledToolTip {
                    show: parent.containsMouse
                    tooltipText: "Save & Close"
                }
            }

            // Edit
            ActionButton {
                icon: Icons.edit
                onTriggered: {
                    // Abrir satty (anotador) flotante: lee el temp, guarda al disco
                    // permanente con Ctrl+S y copia con Ctrl+C (early-exit al terminar).
                    var proc = Qt.createQmlObject('import Quickshell; import Quickshell.Io; Process { }', root);
                    proc.command = ["hyprctl", "dispatch", "exec",
                        "[float;size 1100 760;center] satty --filename '" + root.imagePath
                        + "' --output-filename '" + root.savePath + "' --copy-command wl-copy --early-exit"];
                    proc.running = true;
                    root.imagePath = "";
                }
                StyledToolTip {
                    show: parent.containsMouse
                    tooltipText: "Edit with Satty"
                }
            }

            // Save as… (file dialog). GTK_USE_PORTAL=0 forces zenity's own dialog
            // (con campo de nombre editable) en vez del portal yazi/termfilechooser.
            ActionButton {
                icon: Icons.folder
                onTriggered: {
                    var proc = Qt.createQmlObject('import Quickshell; import Quickshell.Io; Process { }', root);
                    var src = root.imagePath;
                    // yad es GTK3 → diálogo propio con campo de nombre editable
                    // (zenity es GTK4 y siempre rutea al portal yazi/termfilechooser).
                    // Vía hyprctl dispatch exec para que flote (la regla aplica a yad);
                    // el cp va adentro (no necesitamos el stdout de vuelta).
                    proc.command = ["hyprctl", "dispatch", "exec",
                        "[float;center;size 950 620] dest=$(GTK_USE_PORTAL=0 yad --file --save --confirm-overwrite " +
                        "--filename=\"$(xdg-user-dir PICTURES)/Screenshots/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png\" 2>/dev/null); " +
                        "dest=\"${dest%|}\"; [ -n \"$dest\" ] && cp '" + src + "' \"$dest\""];
                    proc.running = true;
                }
                StyledToolTip {
                    show: parent.containsMouse
                    tooltipText: "Save as…"
                }
            }

            // Pin (keep the preview open, no auto-hide)
            ActionButton {
                icon: Icons.pin
                variant: root.pinned ? "primary" : "common"
                onTriggered: root.pinned = !root.pinned
                StyledToolTip {
                    show: parent.containsMouse
                    tooltipText: root.pinned ? "Unpin" : "Pin (keep open)"
                }
            }

            // Trash
            ActionButton {
                icon: Icons.trash
                hoverVariant: "error"
                clickVariant: "overerror"
                isTrash: true

                onTriggered: {
                    var proc = Qt.createQmlObject('import Quickshell; import Quickshell.Io; Process { }', root);
                    proc.command = ["rm", root.imagePath];
                    proc.running = true;
                    root.imagePath = "";
                }
                StyledToolTip {
                    show: parent.containsMouse
                    tooltipText: "Delete"
                }
            }
            } // Row
        } // Item
    } // mainColumn

    // Helper Component for Buttons
    component ActionButton: MouseArea {
        id: btn
        width: 36
        height: 36
        hoverEnabled: true

        property string icon
        property string variant: "common"
        property string hoverVariant: "focus"
        property string clickVariant: "primary"
        property bool isTrash: false

        signal triggered

        StyledRect {
            anchors.fill: parent
            radius: Styling.radius(0)
            variant: {
                if (btn.pressed)
                    return btn.clickVariant;
                if (btn.containsMouse)
                    return btn.hoverVariant;
                return btn.variant;
            }

            Text {
                anchors.centerIn: parent
                text: btn.icon
                font.family: Icons.font
                font.pixelSize: 16
                color: Styling.srItem(parent.variant) || Colors.overBackground
            }
        }

        onClicked: triggered()
    }
}
