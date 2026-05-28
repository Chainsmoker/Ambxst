pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.components
import qs.modules.theme
import qs.modules.services
import qs.config

// Pill flotante de grabación: aparece debajo del notch mientras
// ScreenRecorder.isRecording. Muestra punto REC + tiempo + visualizer; al hover
// revela pausa/resume, stop y una ✕ para ocultar el widget (sin cortar la
// grabación) por si tapa algo en pantalla.
PanelWindow {
    id: root

    property ShellScreen targetScreen
    screen: targetScreen

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ambxst:recording"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: 120
    color: "transparent"

    // Desmontar la ventana cuando no se muestra: si no, el Canvas del visualizer
    // sigue repintando de fondo y consume GPU aunque esté invisible.
    visible: root.shown

    // Espacio para librar el notch (notch arriba por defecto). Bien pegado.
    property int notchClearance: 36

    readonly property bool shown: ScreenRecorder.isRecording && ScreenRecorder.floatingOpen
    readonly property bool hovered: pillHover.containsMouse || pauseMA.containsMouse || stopMA.containsMouse || closeMA.containsMouse

    // Solo el pill captura input; el resto de la franja superior pasa de largo.
    mask: Region {
        item: root.shown ? pill : emptyMask
    }
    Item { id: emptyMask; width: 0; height: 0 }

    Item {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.notchClearance + (root.shown ? 0 : -10)

        implicitWidth: pillRow.implicitWidth + 32
        implicitHeight: 40
        width: implicitWidth
        height: implicitHeight

        opacity: root.shown ? 1 : 0
        scale: root.shown ? 1 : 0.9
        transformOrigin: Item.Top

        Behavior on anchors.topMargin {
            enabled: Config.animDuration > 0
            NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutBack }
        }
        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
        }
        Behavior on scale {
            enabled: Config.animDuration > 0
            NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutBack }
        }
        Behavior on width {
            enabled: Config.animDuration > 0
            NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
        }

        StyledRect {
            id: bg
            anchors.fill: parent
            variant: "popup"
            radius: Styling.radius(20)
            enableBorder: false
            enableShadow: true
        }

        MouseArea {
            id: pillHover
            anchors.fill: parent
            hoverEnabled: true
        }

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 9

            // Punto REC (pulsa mientras graba; fijo y atenuado en pausa)
            Rectangle {
                id: dot
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 11
                implicitHeight: 11
                radius: width / 2
                color: ScreenRecorder.paused ? Colors.outline : Colors.error

                SequentialAnimation on opacity {
                    running: root.shown && !ScreenRecorder.paused
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0;  duration: 700; easing.type: Easing.InOutSine }
                    onStopped: dot.opacity = 1
                }
            }

            // Estado: REC / PAUSED
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: ScreenRecorder.paused ? "PAUSED" : "REC"
                font.family: Config.theme.font
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 1.5
                color: Colors.overBackground
            }

            // Tiempo transcurrido (mono)
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: ScreenRecorder.duration.length > 0 ? ScreenRecorder.duration : "00:00"
                font.family: Config.theme.monoFont
                font.pixelSize: 14
                color: Colors.overBackground
                opacity: 0.85
            }

            // Visualizer (barras animadas tipo ecualizador mientras graba)
            WavyLine {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 48
                Layout.preferredHeight: 16
                color: ScreenRecorder.paused ? Colors.outline : Colors.error
                useCava: false
                barStyle: true
                numBars: 12
                visible: root.shown
                animationsEnabled: !ScreenRecorder.paused
                running: root.shown && !ScreenRecorder.paused
                active: !ScreenRecorder.paused
            }

            // Controles (se revelan al hover): pausa · stop · cerrar
            RowLayout {
                id: controls
                Layout.alignment: Qt.AlignVCenter
                spacing: 4
                clip: true
                opacity: root.hovered ? 1 : 0
                Layout.preferredWidth: root.hovered ? implicitWidth : 0

                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
                }
                Behavior on Layout.preferredWidth {
                    enabled: Config.animDuration > 0
                    NumberAnimation { duration: Config.animDuration; easing.type: Easing.OutQuart }
                }

                // Pausa / reanudar
                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: width / 2
                    color: pauseMA.containsMouse ? Colors.surfaceContainerHigh : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: ScreenRecorder.paused ? Icons.play : Icons.pause
                        font.family: Icons.font
                        font.pixelSize: 15
                        color: Colors.overBackground
                    }
                    MouseArea {
                        id: pauseMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ScreenRecorder.togglePause()
                    }
                }

                // Stop (corta y guarda la grabación)
                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: width / 2
                    color: stopMA.containsMouse ? Colors.error : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: Icons.stop
                        font.family: Icons.font
                        font.pixelSize: 15
                        color: stopMA.containsMouse ? Colors.background : Colors.overBackground
                    }
                    MouseArea {
                        id: stopMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ScreenRecorder.toggleRecording()
                    }
                }

                // Cerrar el widget (NO corta la grabación; vuelve al reiniciarla)
                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: width / 2
                    color: closeMA.containsMouse ? Colors.surfaceContainerHigh : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.family: Config.theme.font
                        font.pixelSize: 14
                        font.bold: true
                        color: Colors.overBackground
                        opacity: 0.7
                    }
                    MouseArea {
                        id: closeMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ScreenRecorder.floatingOpen = false
                    }
                }
            }
        }
    }
}
