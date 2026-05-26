pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.notifications
import qs.config

Rectangle {
    id: root
    color: "transparent"
    implicitWidth: 400
    implicitHeight: 400

    readonly property int count: Notifications.list.length

    function relTime(ms) {
        if (!ms)
            return "—";
        let d = Date.now() - ms;
        if (d < 60000)
            return "NOW";
        if (d < 3600000)
            return Math.floor(d / 60000) + "M";
        if (d < 86400000)
            return Math.floor(d / 3600000) + "H";
        return Math.floor(d / 86400000) + "D";
    }

    function urgencyColor(u) {
        if (u === "critical" || u === 2)
            return Colors.error;
        if (u === "low" || u === 0)
            return Colors.secondary;
        return Colors.primary;
    }

    function clearGroup(group) {
        if (!group || !group.notifications)
            return;
        Notifications.discardNotifications(group.notifications.map(n => n.id));
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 0

        // ══ Header bar ═══════════════════════════════════════════════════════
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: "INBOX"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(5)
                    font.weight: Font.Black
                    font.letterSpacing: 2
                    color: Colors.overBackground
                }
                Text {
                    text: root.count > 0 ? (root.count + " ACTIVE // " + Notifications.appNameList.length + " SRC") : "EMPTY // 0 SRC"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.monoFontSize(-1)
                    font.bold: true
                    font.letterSpacing: 1
                    color: Colors.primary
                }
            }

            BrutalBtn {
                label: Notifications.silent ? "DND" : "LIVE"
                active: Notifications.silent
                onClicked: Notifications.silent = !Notifications.silent
            }
            BrutalBtn {
                label: "CLEAR"
                enabled: root.count > 0
                danger: true
                onClicked: Notifications.discardAllNotifications()
            }
        }

        // thick rule under header
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 12
            implicitHeight: 3
            color: Colors.primary
        }

        // ══ Grouped list ═════════════════════════════════════════════════════
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Empty state
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 6
                visible: root.count === 0

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "[ ]"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(6)
                    font.bold: true
                    color: Colors.overBackground
                    opacity: 0.3
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "NO SIGNAL"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.monoFontSize(0)
                    font.bold: true
                    font.letterSpacing: 2
                    color: Colors.overBackground
                    opacity: 0.4
                }
            }

            ListView {
                id: groupsView
                anchors.fill: parent
                clip: true
                spacing: 18
                visible: root.count > 0
                model: Notifications.appNameList
                cacheBuffer: 800

                ScrollBar.vertical: ScrollBar {
                    policy: groupsView.contentHeight > groupsView.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }

                delegate: ColumnLayout {
                    id: groupCol
                    required property string modelData

                    readonly property var group: Notifications.groupsByAppName[modelData] ?? null
                    readonly property var notifs: group ? group.notifications : []

                    width: groupsView.width
                    spacing: 0
                    visible: group !== null && notifs.length > 0

                    // ── App label bar (solid block, UPPERCASE mono) ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Rectangle {
                            Layout.preferredHeight: 26
                            Layout.preferredWidth: appRow.implicitWidth + 20
                            color: Colors.primary
                            radius: 0

                            RowLayout {
                                id: appRow
                                anchors.centerIn: parent
                                spacing: 7

                                NotificationAppIcon {
                                    size: 16
                                    appName: groupCol.modelData
                                    appIcon: groupCol.group ? (groupCol.group.appIcon ?? "") : ""
                                    summary: ""
                                }
                                Text {
                                    text: groupCol.modelData.toUpperCase()
                                    font.family: Config.theme.monoFont
                                    font.pixelSize: Styling.monoFontSize(0)
                                    font.weight: Font.Black
                                    font.letterSpacing: 1
                                    color: Styling.srItem("primary")
                                }
                            }
                        }

                        // count block (outlined)
                        Rectangle {
                            Layout.preferredHeight: 26
                            Layout.preferredWidth: 30
                            color: "transparent"
                            border.width: 2
                            border.color: Colors.primary
                            Text {
                                anchors.centerIn: parent
                                text: groupCol.notifs.length
                                font.family: Config.theme.monoFont
                                font.pixelSize: Styling.monoFontSize(-1)
                                font.bold: true
                                color: Colors.primary
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "CLEAR ✕"
                            font.family: Config.theme.monoFont
                            font.pixelSize: Styling.monoFontSize(-1)
                            font.bold: true
                            font.letterSpacing: 1
                            color: clearGroupMa.containsMouse ? Colors.error : Colors.overBackground
                            opacity: clearGroupMa.containsMouse ? 1 : 0.5

                            MouseArea {
                                id: clearGroupMa
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.clearGroup(groupCol.group)
                            }
                        }
                    }

                    // ── Notifications: flat blocks, thick urgency bar, dividers ──
                    Repeater {
                        model: groupCol.notifs

                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            Layout.topMargin: card.index === 0 ? 6 : 0
                            implicitHeight: cardCol.implicitHeight + 18
                            color: cardMa.containsMouse ? Colors.surfaceContainer : "transparent"
                            radius: 0

                            readonly property color accent: root.urgencyColor(card.modelData.urgency)

                            // thick left urgency bar
                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 1
                                width: 5
                                color: card.accent
                            }
                            // bottom hairline divider
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 1
                                color: Colors.outline
                                opacity: 0.25
                            }

                            MouseArea {
                                id: cardMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }

                            ColumnLayout {
                                id: cardCol
                                anchors.fill: parent
                                anchors.topMargin: 9
                                anchors.bottomMargin: 9
                                anchors.leftMargin: 16
                                anchors.rightMargin: 6
                                spacing: 3

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        Layout.fillWidth: true
                                        text: card.modelData.summary ?? ""
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(1)
                                        font.weight: Font.Bold
                                        color: Colors.overBackground
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                    Text {
                                        text: root.relTime(card.modelData.time)
                                        font.family: Config.theme.monoFont
                                        font.pixelSize: Styling.monoFontSize(-2)
                                        font.bold: true
                                        color: card.accent
                                    }
                                    Text {
                                        text: "✕"
                                        font.family: Config.theme.monoFont
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: dismissMa.containsMouse ? Colors.error : Colors.overBackground
                                        opacity: dismissMa.containsMouse ? 1 : 0.4

                                        MouseArea {
                                            id: dismissMa
                                            anchors.fill: parent
                                            anchors.margins: -6
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Notifications.discardNotification(card.modelData.id)
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: card.modelData.body ?? ""
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    color: Colors.overBackground
                                    opacity: 0.75
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 2
                                    spacing: 6
                                    visible: (card.modelData.actions?.length ?? 0) > 0

                                    Repeater {
                                        model: card.modelData.actions ?? []

                                        delegate: Rectangle {
                                            id: actBtn
                                            required property var modelData
                                            implicitWidth: actTxt.implicitWidth + 18
                                            implicitHeight: 24
                                            color: actMa.containsMouse ? Colors.primary : "transparent"
                                            border.width: 1
                                            border.color: actMa.containsMouse ? Colors.primary : Colors.outline
                                            radius: 0

                                            Text {
                                                id: actTxt
                                                anchors.centerIn: parent
                                                text: (actBtn.modelData.text ?? "").toUpperCase()
                                                font.family: Config.theme.monoFont
                                                font.pixelSize: Styling.monoFontSize(-2)
                                                font.bold: true
                                                font.letterSpacing: 1
                                                color: actMa.containsMouse ? Styling.srItem("primary") : Colors.overBackground
                                            }

                                            MouseArea {
                                                id: actMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Notifications.attemptInvokeAction(card.modelData.id, actBtn.modelData.identifier, false)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Brutal square button ─────────────────────────────────────────────────
    component BrutalBtn: Rectangle {
        id: bb
        property string label
        property bool active: false
        property bool danger: false
        property bool enabled: true
        signal clicked

        implicitWidth: bbTxt.implicitWidth + 20
        implicitHeight: 30
        radius: 0
        opacity: bb.enabled ? 1 : 0.35
        color: bb.active ? Colors.primary : (bbMa.containsMouse ? (bb.danger ? Colors.error : Colors.surfaceContainerHigh) : "transparent")
        border.width: 2
        border.color: bb.active ? Colors.primary : (bb.danger ? Colors.error : Colors.outline)

        Text {
            id: bbTxt
            anchors.centerIn: parent
            text: bb.label
            font.family: Config.theme.monoFont
            font.pixelSize: Styling.monoFontSize(-1)
            font.weight: Font.Black
            font.letterSpacing: 1
            color: bb.active ? Styling.srItem("primary") : ((bbMa.containsMouse && bb.danger) ? Colors.overError : Colors.overBackground)
        }

        MouseArea {
            id: bbMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: bb.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: bb.clicked()
        }
    }
}
