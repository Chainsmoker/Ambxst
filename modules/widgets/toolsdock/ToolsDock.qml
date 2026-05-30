pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.globals
import qs.modules.theme
import qs.modules.services
import qs.modules.components
import qs.modules.corners
import qs.config

PanelWindow {
    id: dock

    anchors {
        top: true
        bottom: true
        left: true
    }

    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "ambxst:toolsdock"
    // Permite escribir en los campos (chat/clipboard/notes/translate) cuando está abierto.
    WlrLayershell.keyboardFocus: GlobalStates.toolsDockOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    readonly property bool isOpen: GlobalStates.toolsDockOpen
    // Siempre visible para permitir que la máscara hoverStrip reciba eventos del cursor cuando está cerrado.
    visible: true

    readonly property int dockWidth: 420
    readonly property int hPadding: 18
    readonly property int shoulderSize: Config.roundness > 0 ? Config.roundness + 28 : 44

    // Tab activa: 0=Chat, 1=Clipboard
    property int currentTab: 0

    // Sub-tab del Chat: 0=conversación, 1=historial
    property int chatSubTab: 0

    readonly property var tabMeta: [
        { title: "Chat", sub: "Ambxst Ai Assistant", ico: Icons.robot },
        { title: "Clipboard", sub: "Clipboard History", ico: Icons.clipboard },
        { title: "Notes", sub: "Local Pastebin", ico: Icons.note },
        { title: "Translate", sub: "Groq · Llama 3.3 70B", ico: Icons.globe },
        { title: "Passwords", sub: "Generator · Local", ico: Icons.lock },
        { title: "Dev Tools", sub: "Encode · Convert · Hash", ico: Icons.terminal },
        { title: "QR Code", sub: "Generate · Scan With Phone", ico: Icons.qrCode }
    ]

    readonly property bool barAtTop: {
        const pos = Config.bar?.position ?? "top";
        return pos === "top";
    }

    readonly property int barReserved: {
        const enabled = (Config.bar && Config.bar.pinnedOnStartup !== undefined ? Config.bar.pinnedOnStartup : true);
        if (!enabled) return 0;
        const base = (Config.showBackground !== false) ? 44 : 40;
        return Config.bar?.position === "top" ? base : 0;
    }

    implicitWidth: dockWidth + dock.shoulderSize + 8

    mask: Region {
        regions: [
            Region { item: dock.isOpen ? fullMask : null },
            Region { item: (dock.isOpen && (!dock.barAtTop || Config.showBackground)) ? topRightShoulder : null },
            Region { item: (dock.isOpen && !dock.barAtTop && Config.showBackground) ? bottomRightShoulder : null }
        ]
    }
    Item {
        id: fullMask
        x: 0
        y: dock.barReserved
        width: dock.dockWidth
        height: dock.height - dock.barReserved
    }

    Timer {
        id: closeTimer
        interval: 800
        repeat: false
        onTriggered: GlobalStates.toolsDockOpen = false
    }

    onCurrentTabChanged: {
        ttlMenuOpen = false;
        trLangMenuOpen = false;
        if (currentTab === 1) ClipboardService.list();
        if (currentTab === 2) { notesNow = Date.now(); NotesService.load(); }
        if (currentTab === 4 && PasswordService.password === "") PasswordService.generate();
        if (isOpen) Qt.callLater(focusActiveInput);
    }
    onIsOpenChanged: {
        if (!isOpen) { ttlMenuOpen = false; trLangMenuOpen = false; }
        if (isOpen && currentTab === 1) ClipboardService.list();
        if (isOpen && currentTab === 2) { notesNow = Date.now(); NotesService.load(); }
        if (isOpen && currentTab === 4 && PasswordService.password === "") PasswordService.generate();
        if (isOpen) Qt.callLater(focusActiveInput);
    }
    Component.onCompleted: NotesService.initialize()

    // Enfoca el campo de texto del tab activo al abrir / cambiar de tab.
    function focusActiveInput() {
        if (!isOpen) return;
        if (currentTab === 0) chatInput.forceActiveFocus();
        else if (currentTab === 1) clipSearchInput.forceActiveFocus();
        else if (currentTab === 2) noteInput.forceActiveFocus();
        else if (currentTab === 3) srcInput.forceActiveFocus();
        else if (currentTab === 5) devInput.forceActiveFocus();
        else if (currentTab === 6) qrInput.forceActiveFocus();
    }

    readonly property int dockContainerWidth: dock.dockWidth

    // --- Clipboard state ---
    property string clipSearch: ""
    readonly property var clipItems: {
        var q = dock.clipSearch.toLowerCase();
        if (q.length === 0) return ClipboardService.items;
        return ClipboardService.items.filter(function (it) {
            return (it.preview || "").toLowerCase().includes(q) || (it.alias || "").toLowerCase().includes(q);
        });
    }

    Process { id: clipCopyProc; running: false }

    function copyClipItem(item) {
        if (item.isImage && item.binaryPath) {
            clipCopyProc.command = ["sh", "-c", "cat '" + item.binaryPath + "' | wl-copy --type '" + item.mime + "'"];
        } else if (item.isFile) {
            clipCopyProc.command = ["sh", "-c", "sqlite3 '" + ClipboardService.dbPath + "' \"SELECT full_content FROM clipboard_items WHERE id = " + item.id + ";\" | tr -d '\\r' | wl-copy --type text/uri-list"];
        } else {
            clipCopyProc.command = ["sh", "-c", "sqlite3 '" + ClipboardService.dbPath + "' \"SELECT full_content FROM clipboard_items WHERE id = " + item.id + ";\" | wl-copy"];
        }
        clipCopyProc.running = true;
        GlobalStates.toolsDockOpen = false;
    }

    function clipIconFor(item) {
        if (item.isImage) return Icons.image;
        if (item.isFile) return Icons.file;
        return Icons.clip;
    }

    // --- Notes state ---
    property int notesTtlIndex: NotesService.defaultTtlIndex
    property bool ttlMenuOpen: false
    property double notesNow: Date.now()

    // --- Translator state ---
    property int trLangIndex: TranslatorService.defaultLangIndex
    property bool trLangMenuOpen: false

    Process { id: notesCopyProc; running: false }

    function copyNoteText(t) {
        // $1 passes the text safely (no shell interpolation of the note body).
        notesCopyProc.command = ["sh", "-c", "printf '%s' \"$1\" | wl-copy", "--", t];
        notesCopyProc.running = true;
    }

    // Remaining-time label that re-evaluates when dock.notesNow ticks.
    function noteTimeLabel(note) {
        var now = dock.notesNow;
        if (!note || note.expiresAt === 0)
            return "Never Expires";
        var ms = Math.max(0, note.expiresAt - now);
        var mins = Math.floor(ms / 60000);
        if (mins < 60)
            return "Expires In " + Math.max(1, mins) + "m";
        var hours = Math.floor(mins / 60);
        if (hours < 24)
            return "Expires In " + hours + "h";
        return "Expires In " + Math.floor(hours / 24) + "d";
    }

    Item {
        id: dockContainer
        width: dock.dockContainerWidth
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: dock.barReserved
        anchors.bottom: parent.bottom
        opacity: dock.isOpen ? 1 : 0
        visible: opacity > 0.001

        HoverHandler {
            id: dockHoverHandler
            onHoveredChanged: {
                if (!hovered && dock.isOpen) {
                    closeTimer.restart();
                } else {
                    closeTimer.stop();
                }
            }
        }

        transform: Translate {
            id: slideTransform
            x: dock.isOpen ? 0 : -dock.dockContainerWidth
            Behavior on x {
                NumberAnimation {
                    duration: Config.animDuration > 0 ? Config.animDuration : 220
                    easing.type: dock.isOpen ? Easing.OutCubic : Easing.InCubic
                }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Config.animDuration > 0 ? Config.animDuration : 220
                easing.type: Easing.OutCubic
            }
        }

        // Fondo del dock — superficie matugen sólida, sin bordes.
        StyledRect {
            id: dockBg
            anchors.fill: parent
            variant: "bg"
            enableShadow: true
            radius: 0
            clip: true
        }

        // ===================== TAB BAR (estilo end-4: texto + subrayado) =====================
        Item {
            id: tabBar
            anchors.top: dockBg.top
            anchors.left: dockBg.left
            anchors.right: dockBg.right
            anchors.topMargin: 14
            anchors.leftMargin: dock.hPadding
            anchors.rightMargin: dock.hPadding
            height: 48
            z: 100

            Row {
                id: tabRow
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                height: parent.height
                spacing: 6

                Repeater {
                    id: tabRepeater
                    model: dock.tabMeta

                    Item {
                        id: tabItem
                        required property var modelData
                        required property int index
                        readonly property bool isActive: dock.currentTab === index
                        width: 48
                        height: tabRow.height

                        Text {
                            anchors.centerIn: parent
                            text: tabItem.modelData.ico
                            font.family: Icons.font
                            font.pixelSize: 21
                            color: tabItem.isActive ? Colors.primary : Colors.outline
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dock.currentTab = tabItem.index
                        }
                    }
                }
            }

            // Subrayado animado bajo el tab activo
            Rectangle {
                id: tabIndicator
                readonly property Item t: (tabRepeater.count, tabRepeater.itemAt(dock.currentTab))
                anchors.bottom: parent.bottom
                height: 3
                radius: 2
                color: Colors.primary
                x: t ? tabRow.x + t.x + (t.width - 22) / 2 : 0
                width: t ? 22 : 0
                Behavior on x { NumberAnimation { duration: Config.animDuration > 0 ? Config.animDuration : 250; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: Config.animDuration > 0 ? Config.animDuration : 250; easing.type: Easing.OutCubic } }
            }

            // Cerrar (X) — botón circular suave
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                height: 38
                radius: width / 2
                color: closeMouse.containsMouse ? Colors.surfaceContainerHigh : "transparent"
                Behavior on color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: Icons.cancel
                    font.family: Icons.font
                    font.pixelSize: 16
                    color: Colors.overBackground
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: GlobalStates.toolsDockOpen = false
                }
            }
        }

        // Separador tenue
        Rectangle {
            id: headerDivider
            anchors.top: tabBar.bottom
            anchors.left: dockBg.left
            anchors.right: dockBg.right
            anchors.topMargin: 12
            anchors.leftMargin: dock.hPadding
            anchors.rightMargin: dock.hPadding
            height: 1
            color: Colors.outlineVariant
            opacity: 0.5
        }

        // Título de la sección activa (los tabs son solo-icono)
        ColumnLayout {
            id: titleBlock
            anchors.top: headerDivider.bottom
            anchors.left: dockBg.left
            anchors.right: dockBg.right
            anchors.topMargin: 14
            anchors.leftMargin: dock.hPadding
            anchors.rightMargin: dock.hPadding
            spacing: 0

            Text {
                text: dock.tabMeta[dock.currentTab].title
                font.family: Config.theme.font
                font.capitalization: Font.Capitalize
                font.pixelSize: Styling.fontSize(6)
                font.weight: Font.Bold
                color: Colors.overBackground
            }

            Text {
                text: dock.tabMeta[dock.currentTab].sub
                font.family: Config.theme.font
                font.capitalization: Font.Capitalize
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.outline
            }
        }

        // Hombros cóncavos de unión al borde de la pantalla
        Item {
            id: topRightShoulder
            width: dock.shoulderSize
            height: dock.shoulderSize
            anchors.top: dockBg.top
            anchors.left: dockBg.right
            visible: !dock.barAtTop || Config.showBackground

            RoundCorner {
                anchors.fill: parent
                corner: RoundCorner.CornerEnum.TopLeft
                size: dock.shoulderSize
                color: dockBg.color
                Behavior on color { ColorAnimation { duration: 700 } }
            }
        }

        Item {
            id: bottomRightShoulder
            width: dock.shoulderSize
            height: dock.shoulderSize
            anchors.bottom: dockBg.bottom
            anchors.left: dockBg.right
            visible: !dock.barAtTop && Config.showBackground

            RoundCorner {
                anchors.fill: parent
                corner: RoundCorner.CornerEnum.BottomLeft
                size: dock.shoulderSize
                color: dockBg.color
                Behavior on color { ColorAnimation { duration: 700 } }
            }
        }

        // ===================== TAB 0: CHAT =====================
        Item {
            id: chatTabContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleBlock.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            visible: dock.currentTab === 0

            // Sub-toggle: Conversación / Historial
            Row {
                id: chatSubToggle
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.leftMargin: dock.hPadding
                anchors.topMargin: 2
                height: 32
                spacing: 6
                z: 10

                Repeater {
                    model: [
                        { t: "Conversación", i: 0 },
                        { t: "Historial", i: 1 }
                    ]
                    delegate: Rectangle {
                        id: subChip
                        required property var modelData
                        readonly property bool on: dock.chatSubTab === modelData.i
                        height: 32
                        width: subT.implicitWidth + 26
                        radius: height / 2
                        color: subChip.on ? Colors.primary : Colors.surfaceContainerHigh
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            id: subT
                            anchors.centerIn: parent
                            text: subChip.modelData.t
                            font.family: Config.theme.font
                            font.capitalization: Font.Capitalize
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: subChip.on ? Colors.overPrimary : Colors.overBackground
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                dock.chatSubTab = subChip.modelData.i;
                                if (subChip.modelData.i === 1)
                                    Ai.reloadHistory();
                            }
                        }
                    }
                }
            }

            // Welcome screen (sin mensajes)
            ColumnLayout {
                id: welcomeScreen
                anchors.top: chatSubToggle.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 4
                anchors.bottomMargin: 76
                visible: dock.chatSubTab === 0 && Ai.currentChat.length === 0
                spacing: 16

                Item { Layout.fillHeight: true }

                // Avatar circular con anillo suave
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    width: 84
                    height: 84

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.14)
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 62
                        height: 62
                        radius: width / 2
                        color: Colors.primaryContainer

                        Text {
                            anchors.centerIn: parent
                            text: Icons.robot
                            font.family: Icons.font
                            font.pixelSize: 30
                            color: Colors.overPrimaryContainer
                        }
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 3

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Ambxst Ai Assistant"
                        font.family: Config.theme.font
                        font.capitalization: Font.Capitalize
                        font.pixelSize: Styling.fontSize(4)
                        font.weight: Font.Bold
                        color: Colors.overBackground
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Ai.currentModel ? Ai.currentModel.name : "No Api Key Configured"
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.outline
                    }
                }

                // Pills de acción
                Flow {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Repeater {
                        model: [
                            { text: "Saludá", prompt: "Hola! Contame qué podés hacer." },
                            { text: "¿Qué sos?", prompt: "Hola, explicame qué es Ambxst shell." },
                            { text: "Limpiar", action: "clear" }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            width: chipText.implicitWidth + 28
                            height: 36
                            radius: height / 2
                            color: chipMouse.containsMouse ? Colors.primary : Colors.surfaceContainerHigh
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: parent.modelData.text
                                font.family: Config.theme.font
                                font.capitalization: Font.Capitalize
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: chipMouse.containsMouse ? Colors.overPrimary : Colors.overBackground
                            }

                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (parent.modelData.action === "clear") {
                                        Ai.createNewChat();
                                    } else if (parent.modelData.prompt) {
                                        Ai.sendMessage(parent.modelData.prompt);
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // Lista de mensajes
            ListView {
                id: chatListView
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: chatSubToggle.bottom
                anchors.bottom: inputBar.top
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 10
                anchors.bottomMargin: 8
                clip: true
                model: Ai.currentChat
                spacing: 12
                visible: dock.chatSubTab === 0 && Ai.currentChat.length > 0

                onCountChanged: Qt.callLater(() => chatListView.positionViewAtEnd())

                delegate: Item {
                    id: msgItem
                    required property var modelData
                    required property int index

                    readonly property bool isUser: modelData.role === "user"
                    readonly property real maxBubble: ListView.view ? ListView.view.width * 0.84 : 300
                    readonly property bool isStreaming: !isUser && Ai.isLoading && index === Ai.currentChat.length - 1
                    readonly property bool isEmpty: (modelData.content || "").length === 0

                    width: ListView.view ? ListView.view.width : 0
                    height: bubble.height + roleLbl.implicitHeight + 7

                    StyledRect {
                        id: bubble
                        anchors.left: msgItem.isUser ? undefined : parent.left
                        anchors.right: msgItem.isUser ? parent.right : undefined
                        width: (msgItem.isStreaming && msgItem.isEmpty) ? 64 : (bubbleText.width + 24)
                        height: (msgItem.isStreaming && msgItem.isEmpty) ? 38 : (bubbleText.height + 22)
                        radius: Styling.radius(2)
                        variant: msgItem.isUser ? "primary" : "pane"

                        // Indicador de "escribiendo" mientras streamea sin contenido
                        Row {
                            anchors.centerIn: parent
                            spacing: 5
                            visible: msgItem.isStreaming && msgItem.isEmpty
                            Repeater {
                                model: 3
                                delegate: Rectangle {
                                    required property int index
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: Styling.srItem("pane")
                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        running: msgItem.isStreaming && msgItem.isEmpty
                                        PauseAnimation { duration: index * 160 }
                                        NumberAnimation { from: 1.0; to: 0.25; duration: 350 }
                                        NumberAnimation { from: 0.25; to: 1.0; duration: 350 }
                                        PauseAnimation { duration: (2 - index) * 160 }
                                    }
                                }
                            }
                        }

                        TextEdit {
                            id: bubbleText
                            visible: !(msgItem.isStreaming && msgItem.isEmpty)
                            x: 12
                            y: 11
                            width: Math.min(implicitWidth, msgItem.maxBubble - 24)
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            textFormat: msgItem.isUser ? TextEdit.PlainText : TextEdit.MarkdownText
                            text: msgItem.modelData.content || ""
                            color: msgItem.isUser ? Styling.srItem("primary") : Styling.srItem("pane")
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            onLinkActivated: l => Qt.openUrlExternally(l)
                        }
                    }

                    Text {
                        id: roleLbl
                        anchors.top: bubble.bottom
                        anchors.topMargin: 3
                        anchors.left: msgItem.isUser ? undefined : parent.left
                        anchors.right: msgItem.isUser ? parent.right : undefined
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        text: msgItem.isUser ? "Tú" : (msgItem.modelData.model || "Hermes")
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.capitalization: Font.Capitalize
                        font.pixelSize: Styling.fontSize(-3)
                    }
                }
            }

            // Barra de input redondeada
            Item {
                id: inputBar
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.bottomMargin: 16
                height: 48
                visible: dock.chatSubTab === 0

                RowLayout {
                    anchors.fill: parent
                    spacing: 8

                    // Nuevo chat (limpiar)
                    Rectangle {
                        Layout.preferredWidth: 48
                        Layout.preferredHeight: 48
                        radius: width / 2
                        color: clearMouse.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: Icons.trash
                            font.family: Icons.font
                            font.pixelSize: 17
                            color: Colors.overBackground
                        }

                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Ai.createNewChat();
                                chatInput.text = "";
                            }
                        }
                    }

                    // Campo + enviar dentro de un pill
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: height / 2
                        color: Colors.surfaceContainerHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 6
                            spacing: 6

                            TextInput {
                                id: chatInput
                                Layout.fillWidth: true
                                verticalAlignment: TextInput.AlignVCenter
                                color: Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                                selectByMouse: true
                                clip: true

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: "Preguntale algo a Ambxst..."
                                    color: Colors.outline
                                    opacity: chatInput.text.length === 0 ? 0.7 : 0
                                    font: chatInput.font
                                }

                                Keys.onPressed: (event) => {
                                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        if (chatInput.text.trim() !== "") {
                                            Ai.sendMessage(chatInput.text);
                                            chatInput.text = "";
                                        }
                                        event.accepted = true;
                                    }
                                }
                            }

                            // Enviar / Stop (circular)
                            Rectangle {
                                id: sendBtn
                                readonly property bool act: Ai.isLoading || chatInput.text.trim() !== ""
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                Layout.alignment: Qt.AlignVCenter
                                radius: width / 2
                                color: Ai.isLoading ? Colors.error : (sendBtn.act ? Colors.primary : Colors.surfaceContainerHighest)
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: Ai.isLoading ? Icons.stop : Icons.caretRight
                                    font.family: Icons.font
                                    font.pixelSize: 16
                                    color: Ai.isLoading ? Colors.overError : (sendBtn.act ? Colors.overPrimary : Colors.outline)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (Ai.isLoading) {
                                            Ai.stopGeneration();
                                        } else if (chatInput.text.trim() !== "") {
                                            Ai.sendMessage(chatInput.text);
                                            chatInput.text = "";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Sugerencias de slash-commands (aparece al tipear "/")
            Rectangle {
                id: slashPopup
                readonly property string tok: chatInput.text.split(" ")[0]
                visible: chatInput.text.startsWith("/") && !Ai.isLoading
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: inputBar.top
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.bottomMargin: 8
                height: slashCol.implicitHeight + 8
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh
                z: 200

                Column {
                    id: slashCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 4

                    Repeater {
                        model: [
                            { cmd: "/new", desc: "Nuevo chat", instant: true },
                            { cmd: "/model", desc: "Cambiar o listar modelos", instant: false },
                            { cmd: "/help", desc: "Ayuda y comandos", instant: true }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            visible: modelData.cmd.indexOf(slashPopup.tok) === 0
                            width: parent.width
                            height: visible ? 40 : 0
                            radius: Styling.radius(-6)
                            color: cmdMouse.containsMouse ? Colors.primaryContainer : "transparent"

                            Row {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Text {
                                    text: modelData.cmd
                                    font.family: Config.theme.monoFont
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.Bold
                                    color: cmdMouse.containsMouse ? Colors.overPrimaryContainer : Colors.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.desc
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: cmdMouse.containsMouse ? Colors.overPrimaryContainer : Colors.outline
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: cmdMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.instant) {
                                        Ai.sendMessage(modelData.cmd);
                                        chatInput.text = "";
                                    } else {
                                        chatInput.text = modelData.cmd + " ";
                                        chatInput.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Historial de conversaciones
            ListView {
                id: historyList
                anchors.top: chatSubToggle.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 10
                anchors.bottomMargin: 16
                clip: true
                spacing: 8
                visible: dock.chatSubTab === 1
                model: Ai.chatHistory
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: histCard
                    required property var modelData
                    required property int index
                    readonly property bool current: modelData.id === Ai.currentChatId

                    width: ListView.view ? ListView.view.width : 0
                    height: 52
                    radius: Styling.radius(2)
                    color: (histMouse.containsMouse || histCard.current) ? Colors.primaryContainer : Colors.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: 150 } }

                    MouseArea {
                        id: histMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Ai.loadChat(histCard.modelData.id);
                            dock.chatSubTab = 0;
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        spacing: 10

                        Text {
                            text: Icons.robot
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: (histMouse.containsMouse || histCard.current) ? Colors.overPrimaryContainer : Colors.primary
                        }
                        Text {
                            Layout.fillWidth: true
                            text: histCard.modelData.title || "Nuevo Chat"
                            color: (histMouse.containsMouse || histCard.current) ? Colors.overPrimaryContainer : Colors.overBackground
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                        Text {
                            visible: histCard.current
                            text: "●"
                            font.pixelSize: 9
                            color: Colors.overPrimaryContainer
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            Layout.alignment: Qt.AlignVCenter
                            radius: width / 2
                            color: histDel.containsMouse ? Colors.error : "transparent"
                            opacity: (histMouse.containsMouse || histDel.containsMouse) ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                anchors.centerIn: parent
                                text: Icons.trash
                                font.family: Icons.font
                                font.pixelSize: 13
                                color: histDel.containsMouse ? Colors.background : Colors.overPrimaryContainer
                            }
                            MouseArea {
                                id: histDel
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Ai.deleteChat(histCard.modelData.id)
                            }
                        }
                    }
                }
            }

            // Estado vacío del historial
            ColumnLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                visible: dock.chatSubTab === 1 && Ai.chatHistory.length === 0

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Icons.robot
                    font.family: Icons.font
                    font.pixelSize: 40
                    color: Colors.outlineVariant
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Sin Conversaciones"
                    font.family: Config.theme.font
                    font.capitalization: Font.Capitalize
                    font.pixelSize: Styling.fontSize(0)
                    font.weight: Font.Medium
                    color: Colors.outline
                }
            }
        }

        // ===================== TAB 1: CLIPBOARD =====================
        Item {
            id: clipboardTabContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleBlock.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            visible: dock.currentTab === 1

            // Búsqueda + limpiar
            RowLayout {
                id: clipTopBar
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 14
                spacing: 8
                height: 46

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    radius: height / 2
                    color: Colors.surfaceContainerHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10

                        Text {
                            text: Icons.clip
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: Colors.outline
                        }

                        TextInput {
                            id: clipSearchInput
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.overBackground
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            selectByMouse: true
                            clip: true
                            onTextChanged: dock.clipSearch = text

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "Buscar en el portapapeles..."
                                color: Colors.outline
                                opacity: clipSearchInput.text.length === 0 ? 0.7 : 0
                                font: clipSearchInput.font
                            }
                        }
                    }
                }

                // Limpiar todo
                Rectangle {
                    Layout.preferredWidth: 46
                    Layout.preferredHeight: 46
                    radius: width / 2
                    color: clipClearMouse.containsMouse ? Colors.errorContainer : Colors.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: Icons.broom
                        font.family: Icons.font
                        font.pixelSize: 17
                        color: clipClearMouse.containsMouse ? Colors.overErrorContainer : Colors.overBackground
                    }

                    MouseArea {
                        id: clipClearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ClipboardService.clear()
                    }
                }
            }

            // Estado vacío
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 10
                visible: dock.clipItems.length === 0

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Icons.clipboard
                    font.family: Icons.font
                    font.pixelSize: 42
                    color: Colors.outlineVariant
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: dock.clipSearch.length > 0 ? "Sin Resultados" : "Portapapeles Vacío"
                    font.family: Config.theme.font
                    font.capitalization: Font.Capitalize
                    font.pixelSize: Styling.fontSize(0)
                    font.weight: Font.Medium
                    color: Colors.outline
                }
            }

            // Lista del clipboard
            ListView {
                id: clipList
                anchors.top: clipTopBar.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 12
                anchors.bottomMargin: 16
                clip: true
                spacing: 8
                model: dock.clipItems
                visible: dock.clipItems.length > 0
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: clipCard
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    height: 58
                    radius: Styling.radius(2)
                    color: cardMouse.containsMouse ? Colors.primaryContainer : Colors.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: 150 } }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dock.copyClipItem(clipCard.modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12

                        // Icono en chip redondeado
                        Rectangle {
                            Layout.preferredWidth: 38
                            Layout.preferredHeight: 38
                            radius: Styling.radius(-4)
                            color: cardMouse.containsMouse ? Qt.rgba(Colors.overPrimaryContainer.r, Colors.overPrimaryContainer.g, Colors.overPrimaryContainer.b, 0.15) : Colors.surfaceContainerHighest

                            Text {
                                anchors.centerIn: parent
                                text: dock.clipIconFor(clipCard.modelData)
                                font.family: Icons.font
                                font.pixelSize: 18
                                color: cardMouse.containsMouse ? Colors.overPrimaryContainer : Colors.overBackground
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                var p = clipCard.modelData.alias || clipCard.modelData.preview || "";
                                return p.replace(/\n/g, " ").replace(/\r/g, "");
                            }
                            color: cardMouse.containsMouse ? Colors.overPrimaryContainer : Colors.overBackground
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        // Pin
                        Text {
                            visible: clipCard.modelData.pinned
                            text: "●"
                            font.pixelSize: 9
                            color: cardMouse.containsMouse ? Colors.overPrimaryContainer : Colors.primary
                            Layout.alignment: Qt.AlignVCenter
                        }

                        // Borrar (aparece en hover)
                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            radius: width / 2
                            color: delMouse.containsMouse ? Colors.error : "transparent"
                            opacity: cardMouse.containsMouse || delMouse.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: Icons.trash
                                font.family: Icons.font
                                font.pixelSize: 14
                                color: delMouse.containsMouse ? Colors.background : Colors.overPrimaryContainer
                            }

                            MouseArea {
                                id: delMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ClipboardService.deleteItem(clipCard.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // ===================== TAB 2: NOTES =====================
        Item {
            id: notesTabContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleBlock.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            visible: dock.currentTab === 2

            // Refresca el "expira en…" mientras el tab está visible
            Timer {
                running: notesTabContent.visible && dock.isOpen
                interval: 30000
                repeat: true
                onTriggered: dock.notesNow = Date.now()
            }

            // Caja para escribir/pegar
            Rectangle {
                id: composeBox
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 14
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                height: 96
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 14
                    clip: true
                    contentHeight: noteInput.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    TextArea {
                        id: noteInput
                        width: parent.width
                        wrapMode: TextEdit.Wrap
                        padding: 0
                        background: null
                        color: Colors.overBackground
                        placeholderText: "Pegá o escribí una nota..."
                        placeholderTextColor: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        selectByMouse: true
                    }
                }
            }

            // Lista de notas (declarada antes que los controles para que el dropdown la solape)
            ListView {
                id: notesList
                anchors.top: controlsRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 12
                anchors.bottomMargin: 16
                clip: true
                spacing: 8
                model: NotesService.notes
                visible: NotesService.notes.length > 0
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: noteCard
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    height: noteCol.implicitHeight + 24
                    radius: Styling.radius(2)
                    color: noteMouse.containsMouse ? Colors.primaryContainer : Colors.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: 150 } }

                    MouseArea {
                        id: noteMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dock.copyNoteText(noteCard.modelData.text)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        ColumnLayout {
                            id: noteCol
                            Layout.fillWidth: true
                            spacing: 5

                            Text {
                                Layout.fillWidth: true
                                text: noteCard.modelData.text
                                color: noteMouse.containsMouse ? Colors.overPrimaryContainer : Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    text: Icons.timer
                                    font.family: Icons.font
                                    font.pixelSize: 12
                                    color: noteMouse.containsMouse ? Colors.overPrimaryContainer : Colors.outline
                                }
                                Text {
                                    text: dock.noteTimeLabel(noteCard.modelData)
                                    font.family: Config.theme.font
                                    font.capitalization: Font.Capitalize
                                    font.pixelSize: Styling.fontSize(-3)
                                    color: noteMouse.containsMouse ? Colors.overPrimaryContainer : Colors.outline
                                }
                            }
                        }

                        // Borrar
                        Rectangle {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            Layout.alignment: Qt.AlignTop
                            radius: width / 2
                            color: noteDelMouse.containsMouse ? Colors.error : "transparent"
                            opacity: noteMouse.containsMouse || noteDelMouse.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Text {
                                anchors.centerIn: parent
                                text: Icons.trash
                                font.family: Icons.font
                                font.pixelSize: 14
                                color: noteDelMouse.containsMouse ? Colors.background : Colors.overPrimaryContainer
                            }
                            MouseArea {
                                id: noteDelMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: NotesService.remove(noteCard.modelData.id)
                            }
                        }
                    }
                }
            }

            // Estado vacío
            ColumnLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: controlsRow.bottom
                anchors.topMargin: 64
                spacing: 10
                visible: NotesService.notes.length === 0

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Icons.notepad
                    font.family: Icons.font
                    font.pixelSize: 42
                    color: Colors.outlineVariant
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Sin Notas"
                    font.family: Config.theme.font
                    font.capitalization: Font.Capitalize
                    font.pixelSize: Styling.fontSize(0)
                    font.weight: Font.Medium
                    color: Colors.outline
                }
            }

            // Controles (selector de expiración + guardar) — al final para que el popup solape la lista
            RowLayout {
                id: controlsRow
                anchors.top: composeBox.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 10
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                height: 44
                spacing: 8
                z: 50

                // Selector de expiración (dropdown)
                Rectangle {
                    id: ttlButton
                    Layout.preferredHeight: 44
                    Layout.preferredWidth: ttlRow.implicitWidth + 28
                    radius: height / 2
                    color: ttlMouse.containsMouse || dock.ttlMenuOpen ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        id: ttlRow
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: Icons.timer
                            font.family: Icons.font
                            font.pixelSize: 15
                            color: Colors.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: NotesService.ttlPresets[dock.notesTtlIndex].label
                            font.family: Config.theme.font
                            font.capitalization: Font.Capitalize
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overBackground
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: dock.ttlMenuOpen ? Icons.caretUp : Icons.caretDown
                            font.family: Icons.font
                            font.pixelSize: 12
                            color: Colors.outline
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: ttlMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dock.ttlMenuOpen = !dock.ttlMenuOpen
                    }

                }

                Item { Layout.fillWidth: true }

                // Guardar
                Rectangle {
                    Layout.preferredHeight: 44
                    Layout.preferredWidth: saveRow.implicitWidth + 28
                    radius: height / 2
                    color: noteInput.text.trim() !== "" ? Colors.primary : Colors.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        id: saveRow
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: Icons.plus
                            font.family: Icons.font
                            font.pixelSize: 15
                            color: noteInput.text.trim() !== "" ? Colors.overPrimary : Colors.outline
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "Guardar"
                            font.family: Config.theme.font
                            font.capitalization: Font.Capitalize
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Bold
                            color: noteInput.text.trim() !== "" ? Colors.overPrimary : Colors.outline
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (noteInput.text.trim() !== "") {
                                NotesService.add(noteInput.text, NotesService.ttlPresets[dock.notesTtlIndex].ms);
                                noteInput.text = "";
                                dock.ttlMenuOpen = false;
                                dock.notesNow = Date.now();
                            }
                        }
                    }
                }
            }

            // Scrim para cerrar al clickear afuera
            MouseArea {
                anchors.fill: parent
                visible: dock.ttlMenuOpen
                z: 900
                onClicked: dock.ttlMenuOpen = false
            }

            // Popup del selector de expiración (al nivel del tab → recibe clicks)
            Rectangle {
                anchors.top: controlsRow.bottom
                anchors.left: parent.left
                anchors.leftMargin: dock.hPadding
                anchors.topMargin: 6
                width: 176
                height: ttlMenuCol.implicitHeight + 8
                radius: Styling.radius(0)
                color: Colors.surfaceContainerHighest
                visible: dock.ttlMenuOpen
                z: 999

                Column {
                    id: ttlMenuCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 4

                    Repeater {
                        model: NotesService.ttlPresets
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 36
                            radius: Styling.radius(-6)
                            color: optMouse.containsMouse ? Colors.primaryContainer : "transparent"

                            Row {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12

                                Text {
                                    width: parent.width - 16
                                    text: modelData.label
                                    font.family: Config.theme.font
                                    font.capitalization: Font.Capitalize
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: dock.notesTtlIndex === index ? Font.Bold : Font.Normal
                                    color: dock.notesTtlIndex === index ? Colors.primary : (optMouse.containsMouse ? Colors.overPrimaryContainer : Colors.overBackground)
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    visible: dock.notesTtlIndex === index
                                    text: "●"
                                    font.pixelSize: 9
                                    color: Colors.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: optMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    dock.notesTtlIndex = index;
                                    dock.ttlMenuOpen = false;
                                }
                            }
                        }
                    }
                }
            }
        }

        // ===================== TAB 3: TRANSLATE =====================
        Item {
            id: translateTabContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleBlock.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            visible: dock.currentTab === 3

            // Texto de origen
            Rectangle {
                id: srcBox
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                height: 108
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 14
                    clip: true
                    contentHeight: srcInput.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    TextArea {
                        id: srcInput
                        width: parent.width
                        wrapMode: TextEdit.Wrap
                        padding: 0
                        background: null
                        color: Colors.overBackground
                        placeholderText: "Texto a traducir..."
                        placeholderTextColor: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        selectByMouse: true
                    }
                }
            }

            // Salida (declarada antes que los controles para que el dropdown la solape)
            Rectangle {
                id: outBox
                anchors.top: trControlsRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 12
                anchors.bottomMargin: 16
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh

                // Cargando
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    visible: TranslatorService.loading
                    Text {
                        text: Icons.circleNotch
                        font.family: Icons.font
                        font.pixelSize: 20
                        color: Colors.primary
                        RotationAnimation on rotation {
                            running: TranslatorService.loading
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 900
                        }
                    }
                    Text {
                        text: "Traduciendo..."
                        font.family: Config.theme.font
                        font.capitalization: Font.Capitalize
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.outline
                    }
                }

                // Error / sin key
                Text {
                    anchors.fill: parent
                    anchors.margins: 18
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    visible: !TranslatorService.loading && TranslatorService.error !== ""
                    text: TranslatorService.error
                    color: Colors.error
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    wrapMode: Text.WordWrap
                }

                // Placeholder
                Text {
                    anchors.centerIn: parent
                    visible: !TranslatorService.loading && TranslatorService.error === "" && TranslatorService.output === ""
                    text: "La Traducción Aparece Acá"
                    color: Colors.outline
                    font.family: Config.theme.font
                    font.capitalization: Font.Capitalize
                    font.pixelSize: Styling.fontSize(-1)
                }

                // Resultado
                Flickable {
                    anchors.fill: parent
                    anchors.margins: 14
                    anchors.rightMargin: 46
                    clip: true
                    visible: !TranslatorService.loading && TranslatorService.output !== ""
                    contentHeight: outText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: outText
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        text: TranslatorService.output
                        color: Colors.overBackground
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                    }
                }

                // Copiar
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    width: 32
                    height: 32
                    radius: width / 2
                    visible: TranslatorService.output !== "" && !TranslatorService.loading
                    color: outCopyMouse.containsMouse ? Colors.primary : Colors.surfaceContainerHighest
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: Icons.copy
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: outCopyMouse.containsMouse ? Colors.overPrimary : Colors.overBackground
                    }
                    MouseArea {
                        id: outCopyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dock.copyNoteText(TranslatorService.output)
                    }
                }
            }

            // Controles: idioma destino + traducir (al final → el popup solapa la salida)
            RowLayout {
                id: trControlsRow
                anchors.top: srcBox.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 10
                height: 44
                spacing: 8
                z: 50

                // Selector de idioma
                Rectangle {
                    id: trLangButton
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: height / 2
                    color: trLangMouse.containsMouse || dock.trLangMenuOpen ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 14
                        spacing: 8
                        Text {
                            text: Icons.globe
                            font.family: Icons.font
                            font.pixelSize: 15
                            color: Colors.primary
                        }
                        Text {
                            Layout.fillWidth: true
                            text: TranslatorService.languages[dock.trLangIndex].label
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: Colors.overBackground
                            elide: Text.ElideRight
                        }
                        Text {
                            text: dock.trLangMenuOpen ? Icons.caretUp : Icons.caretDown
                            font.family: Icons.font
                            font.pixelSize: 12
                            color: Colors.outline
                        }
                    }

                    MouseArea {
                        id: trLangMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dock.trLangMenuOpen = !dock.trLangMenuOpen
                    }

                }

                // Traducir
                Rectangle {
                    Layout.preferredHeight: 44
                    Layout.preferredWidth: trRow.implicitWidth + 28
                    radius: height / 2
                    color: (srcInput.text.trim() !== "" && !TranslatorService.loading) ? Colors.primary : Colors.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        id: trRow
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: TranslatorService.loading ? Icons.circleNotch : Icons.globe
                            font.family: Icons.font
                            font.pixelSize: 15
                            color: (srcInput.text.trim() !== "" && !TranslatorService.loading) ? Colors.overPrimary : Colors.outline
                            anchors.verticalCenter: parent.verticalCenter
                            RotationAnimation on rotation {
                                running: TranslatorService.loading
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 900
                            }
                        }
                        Text {
                            text: "Traducir"
                            font.family: Config.theme.font
                            font.capitalization: Font.Capitalize
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Bold
                            color: (srcInput.text.trim() !== "" && !TranslatorService.loading) ? Colors.overPrimary : Colors.outline
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (srcInput.text.trim() !== "" && !TranslatorService.loading) {
                                dock.trLangMenuOpen = false;
                                TranslatorService.translate(srcInput.text, TranslatorService.languages[dock.trLangIndex].label);
                            }
                        }
                    }
                }
            }

            // Scrim para cerrar al clickear afuera
            MouseArea {
                anchors.fill: parent
                visible: dock.trLangMenuOpen
                z: 900
                onClicked: dock.trLangMenuOpen = false
            }

            // Popup de idiomas (al nivel del tab → recibe clicks)
            Rectangle {
                anchors.top: trControlsRow.bottom
                anchors.left: parent.left
                anchors.leftMargin: dock.hPadding
                anchors.topMargin: 6
                width: trLangButton.width
                height: trLangCol.implicitHeight + 8
                radius: Styling.radius(0)
                color: Colors.surfaceContainerHighest
                visible: dock.trLangMenuOpen
                z: 999

                Column {
                    id: trLangCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 4

                    Repeater {
                        model: TranslatorService.languages
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: parent.width
                            height: 34
                            radius: Styling.radius(-6)
                            color: langOptMouse.containsMouse ? Colors.primaryContainer : "transparent"

                            Row {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12

                                Text {
                                    width: parent.width - 16
                                    text: modelData.label
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.weight: dock.trLangIndex === index ? Font.Bold : Font.Normal
                                    color: dock.trLangIndex === index ? Colors.primary : (langOptMouse.containsMouse ? Colors.overPrimaryContainer : Colors.overBackground)
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: dock.trLangIndex === index
                                    text: "●"
                                    font.pixelSize: 9
                                    color: Colors.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: langOptMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    dock.trLangIndex = index;
                                    dock.trLangMenuOpen = false;
                                }
                            }
                        }
                    }
                }
            }
        }

        // ===================== TAB 4: PASSWORDS =====================
        Item {
            id: passwordTabContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleBlock.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            visible: dock.currentTab === 4

            // Display de la contraseña
            Rectangle {
                id: pwDisplay
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                height: 112
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 16
                    anchors.bottomMargin: 44
                    clip: true
                    contentHeight: pwText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: pwText
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        text: PasswordService.password
                        color: Colors.overBackground
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.fontSize(2)
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 16
                    visible: PasswordService.password === ""
                    text: "—"
                    color: Colors.outline
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(2)
                }

                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 10
                    spacing: 8

                    Rectangle {
                        width: 34
                        height: 34
                        radius: width / 2
                        color: regenMouse.containsMouse ? Colors.surfaceContainerHighest : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            anchors.centerIn: parent
                            text: Icons.arrowCounterClockwise
                            font.family: Icons.font
                            font.pixelSize: 16
                            color: Colors.overBackground
                        }
                        MouseArea {
                            id: regenMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PasswordService.generate()
                        }
                    }

                    Rectangle {
                        width: 34
                        height: 34
                        radius: width / 2
                        color: pwCopyMouse.containsMouse ? Colors.primary : Colors.surfaceContainerHighest
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            anchors.centerIn: parent
                            text: Icons.copy
                            font.family: Icons.font
                            font.pixelSize: 15
                            color: pwCopyMouse.containsMouse ? Colors.overPrimary : Colors.overBackground
                        }
                        MouseArea {
                            id: pwCopyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: dock.copyNoteText(PasswordService.password)
                        }
                    }
                }
            }

            // Medidor de fuerza
            ColumnLayout {
                id: strengthCol
                anchors.top: pwDisplay.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 14
                spacing: 6

                readonly property color lvlColor: [Colors.error, Colors.tertiary, Colors.primary, Colors.primary][PasswordService.strengthLevel]

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            required property int index
                            Layout.fillWidth: true
                            height: 5
                            radius: 3
                            color: index <= PasswordService.strengthLevel ? strengthCol.lvlColor : Colors.surfaceContainerHighest
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }
                }

                Text {
                    text: PasswordService.strengthLabel + " · " + Math.round(PasswordService.entropyBits) + " Bits"
                    font.family: Config.theme.font
                    font.capitalization: Font.Capitalize
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.outline
                }
            }

            // Largo
            ColumnLayout {
                id: lengthCol
                anchors.top: strengthCol.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 18
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Length"
                        font.family: Config.theme.font
                        font.capitalization: Font.Capitalize
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Medium
                        color: Colors.overBackground
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: PasswordService.length
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.fontSize(-1)
                        font.weight: Font.Bold
                        color: Colors.primary
                    }
                }

                Item {
                    id: slider
                    Layout.fillWidth: true
                    height: 22
                    readonly property int from: 8
                    readonly property int to: 64
                    readonly property real frac: (PasswordService.length - from) / (to - from)

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 6
                        radius: 3
                        color: Colors.surfaceContainerHighest
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 6
                        radius: 3
                        color: Colors.primary
                        width: sHandle.x + sHandle.width / 2
                    }
                    Rectangle {
                        id: sHandle
                        width: 18
                        height: 18
                        radius: 9
                        color: Colors.primary
                        anchors.verticalCenter: parent.verticalCenter
                        x: slider.frac * (slider.width - width)
                    }

                    MouseArea {
                        anchors.fill: parent
                        function setFromX(mx) {
                            var t = Math.max(0, Math.min(1, (mx - sHandle.width / 2) / (slider.width - sHandle.width)));
                            PasswordService.length = Math.round(slider.from + t * (slider.to - slider.from));
                        }
                        onPressed: mouse => setFromX(mouse.x)
                        onPositionChanged: mouse => { if (pressed) setFromX(mouse.x); }
                        onReleased: PasswordService.generate()
                    }
                }
            }

            // Toggles de tipos de caracteres
            Flow {
                anchors.top: lengthCol.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 18
                spacing: 8

                Repeater {
                    model: [
                        { label: "A-Z", key: "useUpper" },
                        { label: "a-z", key: "useLower" },
                        { label: "0-9", key: "useDigits" },
                        { label: "!@#", key: "useSymbols" },
                        { label: "No Ambiguous", key: "avoidAmbiguous" }
                    ]
                    delegate: Rectangle {
                        id: tgChip
                        required property var modelData
                        readonly property bool on: PasswordService[modelData.key]
                        height: 36
                        width: tgText.implicitWidth + 28
                        radius: height / 2
                        color: tgChip.on ? Colors.primary : Colors.surfaceContainerHigh
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text {
                            id: tgText
                            anchors.centerIn: parent
                            text: tgChip.modelData.label
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: tgChip.on ? Colors.overPrimary : Colors.overBackground
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                PasswordService[tgChip.modelData.key] = !PasswordService[tgChip.modelData.key];
                                PasswordService.generate();
                            }
                        }
                    }
                }
            }
        }

        // ===================== TAB 5: DEV TOOLS =====================
        Item {
            id: devToolsTabContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleBlock.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            visible: dock.currentTab === 5

            Rectangle {
                id: devBox
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                height: 92
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 14
                    clip: true
                    contentHeight: devInput.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    TextArea {
                        id: devInput
                        width: parent.width
                        wrapMode: TextEdit.Wrap
                        padding: 0
                        background: null
                        color: Colors.overBackground
                        placeholderText: "Input (texto, JSON, etc)..."
                        placeholderTextColor: Colors.outline
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.fontSize(0)
                        selectByMouse: true
                    }
                }
            }

            Flow {
                id: opsFlow
                anchors.top: devBox.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 12
                spacing: 8

                Repeater {
                    model: DevToolsService.ops
                    delegate: Rectangle {
                        id: opChip
                        required property var modelData
                        height: 34
                        width: opText.implicitWidth + 24
                        radius: height / 2
                        color: opMouse.containsMouse ? Colors.primary : Colors.surfaceContainerHigh
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            id: opText
                            anchors.centerIn: parent
                            text: opChip.modelData.label
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            font.weight: Font.Medium
                            color: opMouse.containsMouse ? Colors.overPrimary : Colors.overBackground
                        }
                        MouseArea {
                            id: opMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: DevToolsService.run(opChip.modelData.key, devInput.text)
                        }
                    }
                }
            }

            Rectangle {
                id: devOut
                anchors.top: opsFlow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 12
                anchors.bottomMargin: 16
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh

                Text {
                    anchors.centerIn: parent
                    visible: DevToolsService.output === "" && DevToolsService.error === ""
                    text: "Resultado"
                    color: Colors.outline
                    font.family: Config.theme.font
                    font.capitalization: Font.Capitalize
                    font.pixelSize: Styling.fontSize(-1)
                }

                Text {
                    anchors.fill: parent
                    anchors.margins: 16
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    visible: DevToolsService.error !== ""
                    text: DevToolsService.error
                    color: Colors.error
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    wrapMode: Text.WordWrap
                }

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 14
                    anchors.rightMargin: 46
                    clip: true
                    visible: DevToolsService.output !== "" && DevToolsService.error === ""
                    contentHeight: devOutText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: devOutText
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        text: DevToolsService.output
                        color: Colors.overBackground
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.fontSize(-1)
                    }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    width: 32
                    height: 32
                    radius: width / 2
                    visible: DevToolsService.output !== ""
                    color: devCopyMouse.containsMouse ? Colors.primary : Colors.surfaceContainerHighest
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        anchors.centerIn: parent
                        text: Icons.copy
                        font.family: Icons.font
                        font.pixelSize: 14
                        color: devCopyMouse.containsMouse ? Colors.overPrimary : Colors.overBackground
                    }
                    MouseArea {
                        id: devCopyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dock.copyNoteText(DevToolsService.output)
                    }
                }
            }
        }

        // ===================== TAB 6: QR CODE =====================
        Item {
            id: qrTabContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: titleBlock.bottom
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            visible: dock.currentTab === 6

            Timer {
                id: qrDebounce
                interval: 280
                onTriggered: {
                    QrService.text = qrInput.text;
                    QrService.generate();
                }
            }

            Rectangle {
                id: qrInputBox
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                height: 88
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 14
                    clip: true
                    contentHeight: qrInput.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    TextArea {
                        id: qrInput
                        width: parent.width
                        wrapMode: TextEdit.Wrap
                        padding: 0
                        background: null
                        color: Colors.overBackground
                        placeholderText: "Texto o URL para el QR..."
                        placeholderTextColor: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        selectByMouse: true
                        onTextChanged: qrDebounce.restart()
                    }
                }
            }

            Rectangle {
                anchors.top: qrInputBox.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 14
                anchors.bottomMargin: 16
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    visible: !QrService.ready

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Icons.qrCode
                        font.family: Icons.font
                        font.pixelSize: 46
                        color: Colors.outlineVariant
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Escribí Algo Arriba"
                        font.family: Config.theme.font
                        font.capitalization: Font.Capitalize
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.outline
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 48, parent.height - 48, 260)
                    height: width
                    radius: Styling.radius(-4)
                    color: "#ffffff"
                    visible: QrService.ready

                    Image {
                        anchors.fill: parent
                        anchors.margins: 10
                        source: QrService.ready ? ("file://" + QrService.outPath + "?r=" + QrService.revision) : ""
                        cache: false
                        fillMode: Image.PreserveAspectFit
                        smooth: false
                    }
                }
            }
        }
    }
}
