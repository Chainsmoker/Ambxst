pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Rectangle {
    id: root
    color: "transparent"
    implicitWidth: 400
    implicitHeight: 400

    readonly property var svc: SystemUpdatesService

    // Paquete seleccionado para el modal de actualización individual (null = cerrado)
    property var selected: null
    readonly property bool selIsAur: root.selected && root.selected.source === "aur"

    function relTime(ms) {
        if (!ms)
            return "—";
        var d = Date.now() - ms;
        if (d < 60000)
            return "just now";
        if (d < 3600000)
            return Math.floor(d / 60000) + "m ago";
        return Math.floor(d / 3600000) + "h ago";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 4
        spacing: 8

        // ─── HEADER ───
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle { width: 4; Layout.preferredHeight: hdr.implicitHeight; color: Colors.primary }

            Text {
                id: hdr
                text: "SYSTEM UPDATES"
                color: Colors.overBackground
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(2)
                font.weight: Font.ExtraBold
                font.letterSpacing: 1.5
            }

            Item { Layout.fillWidth: true }

            // Refresh (gira mientras chequea)
            Rectangle {
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                radius: 0
                color: refreshMa.containsMouse ? Colors.primary : "transparent"
                border.color: Colors.outline
                border.width: 1
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    id: refreshIco
                    anchors.centerIn: parent
                    text: Icons.sync
                    font.family: Icons.font
                    font.pixelSize: 15
                    color: refreshMa.containsMouse ? Colors.background : Colors.overBackground
                    RotationAnimation on rotation {
                        running: root.svc.checking
                        loops: Animation.Infinite
                        from: 0; to: 360; duration: 900
                        onStopped: refreshIco.rotation = 0
                    }
                }
                MouseArea {
                    id: refreshMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.svc.refresh()
                }
            }
        }

        // ─── STATUS ───
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Badge con el conteo (o check si está al día)
            Rectangle {
                Layout.preferredWidth: Math.max(44, badgeTxt.implicitWidth + 16)
                Layout.preferredHeight: 44
                radius: 0
                color: (root.svc.ready && root.svc.count === 0) ? Colors.surfaceContainer : Colors.primary

                Text {
                    id: badgeTxt
                    anchors.centerIn: parent
                    visible: !(root.svc.ready && root.svc.count === 0)
                    text: root.svc.count
                    color: Colors.background
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(6)
                    font.weight: Font.Black
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.svc.ready && root.svc.count === 0
                    text: Icons.shieldCheck
                    font.family: Icons.font
                    font.pixelSize: 22
                    color: Colors.overBackground
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (root.svc.checking && !root.svc.ready)
                            return "Checking for updates…";
                        if (root.svc.count === 0)
                            return "Up to date";
                        return root.svc.count === 1 ? "1 update available" : root.svc.count + " updates available";
                    }
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: {
                        if (!root.svc.ready)
                            return "—";
                        if (root.svc.count === 0)
                            return "Checked " + root.relTime(root.svc.lastCheck);
                        return root.svc.repoCount + " repos · " + root.svc.aurCount + " AUR · checked " + root.relTime(root.svc.lastCheck);
                    }
                    color: Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    elide: Text.ElideRight
                }
            }
        }

        // ─── LIST ───
        StyledRect {
            variant: "internalbg"
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 0

            // Estado vacío
            Text {
                anchors.centerIn: parent
                visible: root.svc.ready && root.svc.count === 0
                text: "Nothing to update."
                color: Colors.outline
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
            }

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 6
                clip: true
                spacing: 3
                model: root.svc.updates
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    id: rowDel
                    required property var modelData
                    width: list.width
                    height: 30
                    color: rowMa.containsMouse ? Qt.darker(Colors.surface, 1.4) : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        spacing: 8

                        // Tag de origen
                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 16
                            radius: 0
                            color: "transparent"
                            border.width: 1
                            border.color: rowDel.modelData.source === "aur" ? Colors.tertiary : Colors.primary
                            Text {
                                anchors.centerIn: parent
                                text: rowDel.modelData.source === "aur" ? "AUR" : "REPO"
                                color: rowDel.modelData.source === "aur" ? Colors.tertiary : Colors.primary
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-3)
                                font.weight: Font.Bold
                                font.letterSpacing: 0.5
                            }
                        }

                        // Nombre del paquete
                        Text {
                            Layout.fillWidth: true
                            text: rowDel.modelData.pkg
                            color: Colors.overBackground
                            font.family: Config.theme.monoFont
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        // old → new
                        Text {
                            text: rowDel.modelData.oldVer
                            color: Colors.outline
                            font.family: Config.theme.monoFont
                            font.pixelSize: Styling.fontSize(-2)
                            elide: Text.ElideLeft
                            Layout.maximumWidth: 80
                        }
                        Text {
                            text: "→"
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                        }
                        Text {
                            text: rowDel.modelData.newVer
                            color: Colors.primary
                            font.family: Config.theme.monoFont
                            font.pixelSize: Styling.fontSize(-2)
                            font.weight: Font.Bold
                            elide: Text.ElideLeft
                            Layout.maximumWidth: 80
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selected = rowDel.modelData
                    }
                }
            }
        }

        // ─── ACTION ───
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            visible: root.svc.count > 0
            radius: 0
            color: upMa.containsMouse ? Qt.lighter(Colors.primary, 1.12) : Colors.primary

            Row {
                anchors.centerIn: parent
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.cube
                    font.family: Icons.font
                    font.pixelSize: 16
                    color: Colors.background
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "UPDATE ALL"
                    color: Colors.background
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    font.weight: Font.ExtraBold
                    font.letterSpacing: 1
                }
            }
            MouseArea {
                id: upMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.svc.upgrade()
            }
        }
    }

    // ─── MODAL: update a single package ───
    Rectangle {
        anchors.fill: parent
        z: 50
        visible: root.selected !== null
        color: Qt.rgba(0, 0, 0, 0.55)

        // backdrop click cierra
        MouseArea {
            anchors.fill: parent
            onClicked: root.selected = null
        }

        StyledRect {
            variant: "internalbg"
            anchors.centerIn: parent
            width: parent.width - 56
            implicitHeight: modalCol.implicitHeight + 32
            radius: 0

            // accent bar
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 4
                color: root.selIsAur ? Colors.tertiary : Colors.primary
            }

            // absorbe clicks (no cerrar al clickear el card)
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: modalCol
                anchors.fill: parent
                anchors.margins: 16
                anchors.leftMargin: 20
                spacing: 12

                // tag + "Update package"
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 18
                        radius: 0
                        color: "transparent"
                        border.width: 1
                        border.color: root.selIsAur ? Colors.tertiary : Colors.primary
                        Text {
                            anchors.centerIn: parent
                            text: root.selIsAur ? "AUR" : "REPO"
                            color: root.selIsAur ? Colors.tertiary : Colors.primary
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-3)
                            font.weight: Font.Bold
                            font.letterSpacing: 0.5
                        }
                    }
                    Text {
                        text: "UPDATE PACKAGE"
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                    }
                }

                // package name
                Text {
                    Layout.fillWidth: true
                    text: root.selected ? root.selected.pkg : ""
                    color: Colors.overBackground
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(2)
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                // old → new
                Row {
                    spacing: 8
                    Text {
                        text: root.selected ? root.selected.oldVer : ""
                        color: Colors.outline
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.fontSize(-1)
                    }
                    Text { text: "→"; color: Colors.outline; font.family: Config.theme.font; font.pixelSize: Styling.fontSize(-1) }
                    Text {
                        text: root.selected ? root.selected.newVer : ""
                        color: Colors.primary
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Bold
                    }
                }

                // buttons
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 0
                        color: doMa.containsMouse ? Qt.lighter(Colors.primary, 1.12) : Colors.primary
                        Text {
                            anchors.centerIn: parent
                            text: "UPDATE"
                            color: Colors.background
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.ExtraBold
                            font.letterSpacing: 1
                        }
                        MouseArea {
                            id: doMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.selected)
                                    root.svc.upgradeOne(root.selected.pkg);
                                root.selected = null;
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 96
                        Layout.preferredHeight: 38
                        radius: 0
                        color: cancelMa.containsMouse ? Qt.darker(Colors.surface, 1.3) : "transparent"
                        border.width: 1
                        border.color: Colors.outline
                        Text {
                            anchors.centerIn: parent
                            text: "CANCEL"
                            color: Colors.overBackground
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            font.weight: Font.Bold
                            font.letterSpacing: 1
                        }
                        MouseArea {
                            id: cancelMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selected = null
                        }
                    }
                }
            }
        }
    }
}
