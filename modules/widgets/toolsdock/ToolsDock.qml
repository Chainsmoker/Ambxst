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
    property string notesEditingId: ""

    // --- Translator state ---
    property int trLangIndex: TranslatorService.defaultLangIndex
    property bool trLangMenuOpen: false
    property bool trCopied: false

    // --- Dev Tools state ---
    property string devLastOp: ""

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

    // Parte un mensaje markdown en segmentos prosa/código (por fences ```).
    function msgSegments(text) {
        var t = text || "";
        var segs = [];
        var parts = t.split("```");
        for (var i = 0; i < parts.length; i++) {
            if (i % 2 === 0) {
                if (parts[i].trim().length > 0)
                    segs.push({ code: false, lang: "", body: parts[i].trim() });
            } else {
                var p = parts[i];
                var nl = p.indexOf("\n");
                var lang = "";
                var body = p;
                if (nl >= 0) {
                    var first = p.substring(0, nl).trim();
                    if (first.length > 0 && first.indexOf(" ") === -1 && first.length < 20) {
                        lang = first;
                        body = p.substring(nl + 1);
                    }
                }
                segs.push({ code: true, lang: lang, body: body.replace(/\n+$/, "") });
            }
        }
        if (segs.length === 0)
            segs.push({ code: false, lang: "", body: t });
        return segs;
    }

    // Password coloreado por tipo de carácter (RichText): mayús/números/símbolos/minús.
    function pwColored() {
        var pw = PasswordService.password;
        if (!pw)
            return "";
        var up = Colors.primary.toString();
        var dg = Colors.tertiary.toString();
        var sy = Colors.error.toString();
        var lo = Colors.overBackground.toString();
        var out = "";
        for (var i = 0; i < pw.length; i++) {
            var c = pw.charAt(i);
            var col = lo;
            if (c >= "A" && c <= "Z") col = up;
            else if (c >= "0" && c <= "9") col = dg;
            else if (!(c >= "a" && c <= "z")) col = sy;
            var e = c === "<" ? "&lt;" : (c === ">" ? "&gt;" : (c === "&" ? "&amp;" : c));
            out += "<span style=\"color:" + col + "\">" + e + "</span>";
        }
        return out;
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
                        { t: "Conversation", i: 0 },
                        { t: "History", i: 1 }
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
                    readonly property bool isStreaming: !isUser && Ai.isLoading && index === Ai.currentChat.length - 1
                    readonly property bool isEmpty: (modelData.content || "").length === 0

                    width: ListView.view ? ListView.view.width : 0
                    height: (msgItem.isUser ? userCol.implicitHeight : asstRow.implicitHeight) + 6

                    // ===== USER: burbuja a la derecha =====
                    Column {
                        id: userCol
                        visible: msgItem.isUser
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 3

                        StyledRect {
                            anchors.right: parent.right
                            width: Math.min(uText.implicitWidth + 24, msgItem.width * 0.82)
                            height: uText.implicitHeight + 20
                            radius: Styling.radius(2)
                            variant: "primary"
                            TextEdit {
                                id: uText
                                x: 12
                                y: 10
                                width: Math.min(implicitWidth, msgItem.width * 0.82 - 24)
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                text: msgItem.modelData.content || ""
                                color: Styling.srItem("primary")
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            text: "You"
                            color: Colors.outline
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-3)
                        }
                    }

                    // ===== ASSISTANT: avatar + nombre + segmentos =====
                    Row {
                        id: asstRow
                        visible: !msgItem.isUser
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 9

                        Rectangle {
                            width: 28
                            height: 28
                            radius: 14
                            color: Colors.primaryContainer
                            Text {
                                anchors.centerIn: parent
                                text: Icons.robot
                                font.family: Icons.font
                                font.pixelSize: 15
                                color: Colors.overPrimaryContainer
                            }
                        }

                        Column {
                            width: msgItem.width - 28 - 9
                            spacing: 6

                            Text {
                                text: msgItem.modelData.model || "Hermes"
                                color: Colors.primary
                                font.family: Config.theme.font
                                font.weight: Font.Bold
                                font.pixelSize: Styling.fontSize(-2)
                            }

                            // Indicador de escritura (streaming sin contenido)
                            Row {
                                spacing: 5
                                visible: msgItem.isStreaming && msgItem.isEmpty
                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        required property int index
                                        width: 7
                                        height: 7
                                        radius: 3.5
                                        color: Colors.outline
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

                            // Segmentos: prosa (markdown) + bloques de código
                            Repeater {
                                model: (msgItem.isStreaming && msgItem.isEmpty) ? [] : dock.msgSegments(msgItem.modelData.content)
                                delegate: Loader {
                                    required property var modelData
                                    width: parent ? parent.width : 0
                                    sourceComponent: modelData.code ? codeSeg : proseSeg

                                    Component {
                                        id: proseSeg
                                        TextEdit {
                                            width: parent.width
                                            readOnly: true
                                            selectByMouse: true
                                            wrapMode: TextEdit.Wrap
                                            textFormat: TextEdit.MarkdownText
                                            text: modelData.body
                                            color: Colors.overBackground
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(0)
                                            onLinkActivated: l => Qt.openUrlExternally(l)
                                        }
                                    }

                                    Component {
                                        id: codeSeg
                                        Rectangle {
                                            id: codeBox
                                            property bool cdCopied: false
                                            width: parent.width
                                            height: cdHeader.height + cdText.implicitHeight + 20
                                            radius: Styling.radius(-4)
                                            color: Colors.surfaceContainerLowest
                                            clip: true

                                            Timer { id: cdCopyTimer; interval: 1300; onTriggered: codeBox.cdCopied = false }

                                            Rectangle {
                                                id: cdHeader
                                                anchors.top: parent.top
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                height: 28
                                                color: Colors.surfaceContainerHighest
                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: 12
                                                    text: modelData.lang !== "" ? modelData.lang : "code"
                                                    font.family: Config.theme.monoFont
                                                    font.pixelSize: Styling.fontSize(-3)
                                                    color: Colors.outline
                                                }
                                                Rectangle {
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.rightMargin: 5
                                                    width: cdCopyRow.implicitWidth + 14
                                                    height: 22
                                                    radius: height / 2
                                                    color: cdCopyMouse.containsMouse ? Colors.primary : "transparent"
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                    Row {
                                                        id: cdCopyRow
                                                        anchors.centerIn: parent
                                                        spacing: 5
                                                        Text {
                                                            text: codeBox.cdCopied ? Icons.accept : Icons.copy
                                                            font.family: Icons.font
                                                            font.pixelSize: 11
                                                            color: codeBox.cdCopied ? Colors.primary : (cdCopyMouse.containsMouse ? Colors.overPrimary : Colors.outline)
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                        Text {
                                                            text: codeBox.cdCopied ? "Copied" : "Copy"
                                                            font.family: Config.theme.font
                                                            font.pixelSize: Styling.fontSize(-3)
                                                            color: codeBox.cdCopied ? Colors.primary : (cdCopyMouse.containsMouse ? Colors.overPrimary : Colors.outline)
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: cdCopyMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            dock.copyNoteText(modelData.body);
                                                            codeBox.cdCopied = true;
                                                            cdCopyTimer.restart();
                                                        }
                                                    }
                                                }
                                            }

                                            TextEdit {
                                                id: cdText
                                                anchors.top: cdHeader.bottom
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.margins: 10
                                                width: parent.width - 20
                                                readOnly: true
                                                selectByMouse: true
                                                wrapMode: TextEdit.WrapAnywhere
                                                text: modelData.body
                                                color: Colors.overBackground
                                                font.family: Config.theme.monoFont
                                                font.pixelSize: Styling.fontSize(-1)
                                            }
                                        }
                                    }
                                }
                            }
                        }
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
                                    text: "Ask Ambxst something..."
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
                            { cmd: "/new", desc: "New chat", instant: true },
                            { cmd: "/model", desc: "Switch or list models", instant: false },
                            { cmd: "/help", desc: "Help and commands", instant: true }
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
                    text: "No Conversations"
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
                                text: "Search clipboard..."
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
                    text: dock.clipSearch.length > 0 ? "No Results" : "Clipboard Empty"
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
                border.width: dock.notesEditingId !== "" ? 2 : 0
                border.color: Colors.primary
                Behavior on border.width { NumberAnimation { duration: 150 } }

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
                        placeholderText: "Paste or write a note..."
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
                    readonly property bool editing: dock.notesEditingId === modelData.id
                    property bool copied: false

                    width: ListView.view.width
                    height: noteCol.implicitHeight + 26
                    radius: Styling.radius(2)
                    color: noteCard.editing ? Colors.primaryContainer : (cardHover.hovered ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    HoverHandler { id: cardHover }
                    Timer { id: copyResetTimer; interval: 1300; onTriggered: noteCard.copied = false }

                    ColumnLayout {
                        id: noteCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 13
                        spacing: 10

                        // Texto de la nota
                        Text {
                            Layout.fillWidth: true
                            text: noteCard.modelData.text
                            color: noteCard.editing ? Colors.overPrimaryContainer : Colors.overBackground
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(0)
                            lineHeight: 1.15
                            wrapMode: Text.WordWrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }

                        // Footer: chip de expiración + acciones
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.preferredHeight: 24
                                Layout.preferredWidth: expRow.implicitWidth + 18
                                radius: height / 2
                                color: noteCard.editing ? Qt.rgba(Colors.overPrimaryContainer.r, Colors.overPrimaryContainer.g, Colors.overPrimaryContainer.b, 0.15) : Colors.surfaceContainerHighest
                                Row {
                                    id: expRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text {
                                        text: Icons.timer
                                        font.family: Icons.font
                                        font.pixelSize: 11
                                        color: noteCard.editing ? Colors.overPrimaryContainer : Colors.outline
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: dock.noteTimeLabel(noteCard.modelData)
                                        font.family: Config.theme.font
                                        font.capitalization: Font.Capitalize
                                        font.pixelSize: Styling.fontSize(-3)
                                        color: noteCard.editing ? Colors.overPrimaryContainer : Colors.outline
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Copiar (con feedback)
                            Rectangle {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: Styling.radius(-6)
                                color: copyBtnMouse.containsMouse ? Colors.primary : Colors.surfaceContainerHighest
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: noteCard.copied ? Icons.accept : Icons.copy
                                    font.family: Icons.font
                                    font.pixelSize: 13
                                    color: noteCard.copied ? Colors.primary : (copyBtnMouse.containsMouse ? Colors.overPrimary : Colors.overBackground)
                                }
                                MouseArea {
                                    id: copyBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        dock.copyNoteText(noteCard.modelData.text);
                                        noteCard.copied = true;
                                        copyResetTimer.restart();
                                    }
                                }
                            }

                            // Editar
                            Rectangle {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: Styling.radius(-6)
                                color: editBtnMouse.containsMouse ? Colors.primary : Colors.surfaceContainerHighest
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: Icons.edit
                                    font.family: Icons.font
                                    font.pixelSize: 13
                                    color: editBtnMouse.containsMouse ? Colors.overPrimary : Colors.overBackground
                                }
                                MouseArea {
                                    id: editBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        noteInput.text = noteCard.modelData.text;
                                        dock.notesEditingId = noteCard.modelData.id;
                                        noteInput.forceActiveFocus();
                                    }
                                }
                            }

                            // Borrar
                            Rectangle {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                radius: Styling.radius(-6)
                                color: delBtnMouse.containsMouse ? Colors.error : Colors.surfaceContainerHighest
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: Icons.trash
                                    font.family: Icons.font
                                    font.pixelSize: 13
                                    color: delBtnMouse.containsMouse ? Colors.background : Colors.overBackground
                                }
                                MouseArea {
                                    id: delBtnMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (dock.notesEditingId === noteCard.modelData.id) {
                                            dock.notesEditingId = "";
                                            noteInput.text = "";
                                        }
                                        NotesService.remove(noteCard.modelData.id);
                                    }
                                }
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
                    text: "No Notes"
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

                // Cancelar edición
                Rectangle {
                    visible: dock.notesEditingId !== ""
                    Layout.preferredHeight: 44
                    Layout.preferredWidth: 44
                    radius: height / 2
                    color: cancelMouse.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Text {
                        anchors.centerIn: parent
                        text: Icons.cancel
                        font.family: Icons.font
                        font.pixelSize: 15
                        color: Colors.overBackground
                    }
                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dock.notesEditingId = "";
                            noteInput.text = "";
                        }
                    }
                }

                // Guardar / Actualizar
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
                            text: dock.notesEditingId !== "" ? Icons.accept : Icons.plus
                            font.family: Icons.font
                            font.pixelSize: 15
                            color: noteInput.text.trim() !== "" ? Colors.overPrimary : Colors.outline
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: dock.notesEditingId !== "" ? "Update" : "Save"
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
                            if (noteInput.text.trim() === "")
                                return;
                            if (dock.notesEditingId !== "") {
                                NotesService.update(dock.notesEditingId, noteInput.text);
                                dock.notesEditingId = "";
                            } else {
                                NotesService.add(noteInput.text, NotesService.ttlPresets[dock.notesTtlIndex].ms);
                            }
                            noteInput.text = "";
                            dock.ttlMenuOpen = false;
                            dock.notesNow = Date.now();
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

            // Panel de origen
            Rectangle {
                id: srcBox
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
                    anchors.margins: 14
                    anchors.bottomMargin: 30
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
                        placeholderText: "Text to translate..."
                        placeholderTextColor: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        selectByMouse: true
                    }
                }

                // Contador de caracteres
                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 14
                    anchors.bottomMargin: 9
                    visible: srcInput.text.length > 0
                    text: srcInput.text.length + " chars"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.outline
                }

                // Limpiar origen
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 7
                    width: 26
                    height: 26
                    radius: width / 2
                    visible: srcInput.text.length > 0
                    color: srcClearMouse.containsMouse ? Colors.surfaceContainerHighest : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: Icons.cancel
                        font.family: Icons.font
                        font.pixelSize: 12
                        color: Colors.outline
                    }
                    MouseArea {
                        id: srcClearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            srcInput.text = "";
                            TranslatorService.clear();
                        }
                    }
                }
            }

            // Panel de salida — header (idioma destino + copiar) + cuerpo
            Rectangle {
                id: outBox
                anchors.top: translateBtn.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 12
                anchors.bottomMargin: 16
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh
                clip: true

                Timer { id: trCopyTimer; interval: 1300; onTriggered: dock.trCopied = false }

                // Header: idioma destino + copiar
                Rectangle {
                    id: outHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 38
                    color: Colors.surfaceContainerHighest

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 14
                        spacing: 7
                        Text {
                            text: Icons.globe
                            font.family: Icons.font
                            font.pixelSize: 14
                            color: Colors.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: TranslatorService.languages[dock.trLangIndex].label
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            font.weight: Font.Bold
                            color: Colors.overBackground
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 6
                        width: 28
                        height: 28
                        radius: width / 2
                        visible: TranslatorService.output !== "" && !TranslatorService.loading
                        color: outCopyMouse.containsMouse ? Colors.primary : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: dock.trCopied ? Icons.accept : Icons.copy
                            font.family: Icons.font
                            font.pixelSize: 13
                            color: dock.trCopied ? Colors.primary : (outCopyMouse.containsMouse ? Colors.overPrimary : Colors.overBackground)
                        }
                        MouseArea {
                            id: outCopyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                dock.copyNoteText(TranslatorService.output);
                                dock.trCopied = true;
                                trCopyTimer.restart();
                            }
                        }
                    }
                }

                // Cuerpo: estados
                Item {
                    anchors.top: outHeader.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom

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
                            text: "Translating..."
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
                        text: "Translation Appears Here"
                        color: Colors.outline
                        font.family: Config.theme.font
                        font.capitalization: Font.Capitalize
                        font.pixelSize: Styling.fontSize(-1)
                    }

                    // Resultado
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 14
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
                }
            }

            // === Barra de idiomas (chips horizontales, scroll/drag) ===
            ListView {
                id: langBar
                anchors.top: srcBox.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 12
                height: 36
                orientation: ListView.Horizontal
                spacing: 7
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: TranslatorService.languages

                delegate: Rectangle {
                    id: langChip
                    required property var modelData
                    required property int index
                    readonly property bool sel: dock.trLangIndex === index
                    height: 36
                    width: lbRow.implicitWidth + 24
                    radius: height / 2
                    color: langChip.sel ? Colors.primary : (lbMouse.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        id: lbRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            visible: langChip.sel
                            text: Icons.globe
                            font.family: Icons.font
                            font.pixelSize: 12
                            color: Colors.overPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: langChip.modelData.label
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            font.weight: langChip.sel ? Font.Bold : Font.Medium
                            color: langChip.sel ? Colors.overPrimary : Colors.overBackground
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        id: lbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dock.trLangIndex = langChip.index
                    }
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: e => { langBar.contentX = Math.max(0, Math.min(Math.max(0, langBar.contentWidth - langBar.width), langBar.contentX - e.angleDelta.y)); e.accepted = true; }
                }
            }

            // === Botón Translate (full-width, prominente) ===
            Rectangle {
                id: translateBtn
                anchors.top: langBar.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 12
                height: 46
                radius: height / 2
                readonly property bool ready: srcInput.text.trim() !== "" && !TranslatorService.loading
                color: translateBtn.ready ? Colors.primary : Colors.surfaceContainerHigh
                Behavior on color { ColorAnimation { duration: 150 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 9
                    Text {
                        text: TranslatorService.loading ? Icons.circleNotch : Icons.globe
                        font.family: Icons.font
                        font.pixelSize: 16
                        color: translateBtn.ready ? Colors.overPrimary : Colors.outline
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
                        text: TranslatorService.loading ? "Translating..." : "Translate"
                        font.family: Config.theme.font
                        font.capitalization: Font.Capitalize
                        font.pixelSize: Styling.fontSize(0)
                        font.weight: Font.Bold
                        color: translateBtn.ready ? Colors.overPrimary : Colors.outline
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (translateBtn.ready)
                            TranslatorService.translate(srcInput.text, TranslatorService.languages[dock.trLangIndex].label);
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

            readonly property color pwLvl: [Colors.error, Colors.tertiary, Colors.primary, Colors.primary][PasswordService.strengthLevel]

            // === Hero: password coloreado por tipo de carácter ===
            Rectangle {
                id: pwDisplay
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                height: 146
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh
                clip: true

                // Acento superior según la fuerza
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 4
                    color: passwordTabContent.pwLvl
                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                // Password (RichText coloreado)
                Flickable {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: pwFooter.top
                    anchors.margins: 18
                    clip: true
                    contentHeight: pwText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    Text {
                        id: pwText
                        width: parent.width
                        textFormat: Text.RichText
                        text: dock.pwColored()
                        wrapMode: Text.WrapAnywhere
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.fontSize(4)
                        lineHeight: 1.3
                    }
                }

                // Footer: fuerza + acciones
                Item {
                    id: pwFooter
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 46

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 18
                        spacing: 8
                        Rectangle {
                            width: 9
                            height: 9
                            radius: 4.5
                            color: passwordTabContent.pwLvl
                            anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Text {
                            text: PasswordService.strengthLabel + " · " + Math.round(PasswordService.entropyBits) + " bits"
                            font.family: Config.theme.font
                            font.capitalization: Font.Capitalize
                            font.pixelSize: Styling.fontSize(-2)
                            font.weight: Font.Bold
                            color: passwordTabContent.pwLvl
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 12
                        spacing: 8

                        Rectangle {
                            width: 36
                            height: 36
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
                            id: pwCopyBtn
                            property bool copied: false
                            width: 36
                            height: 36
                            radius: width / 2
                            color: pwCopyMouse.containsMouse ? Colors.primary : Colors.surfaceContainerHighest
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Timer { id: pwCopyTimer; interval: 1300; onTriggered: pwCopyBtn.copied = false }
                            Text {
                                anchors.centerIn: parent
                                text: pwCopyBtn.copied ? Icons.accept : Icons.copy
                                font.family: Icons.font
                                font.pixelSize: 15
                                color: pwCopyBtn.copied ? Colors.primary : (pwCopyMouse.containsMouse ? Colors.overPrimary : Colors.overBackground)
                            }
                            MouseArea {
                                id: pwCopyMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    dock.copyNoteText(PasswordService.password);
                                    pwCopyBtn.copied = true;
                                    pwCopyTimer.restart();
                                }
                            }
                        }
                    }
                }
            }

            // === Largo: número grande + slider ===
            RowLayout {
                id: lengthRow
                anchors.top: pwDisplay.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 20
                height: 52
                spacing: 16

                Column {
                    spacing: -2
                    Text {
                        text: "Length"
                        font.family: Config.theme.font
                        font.capitalization: Font.Capitalize
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.outline
                    }
                    Text {
                        text: PasswordService.length
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.fontSize(12)
                        font.weight: Font.Bold
                        color: Colors.primary
                    }
                }

                Item {
                    id: slider
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
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
                        width: 20
                        height: 20
                        radius: 10
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

            // === Toggles con color (legenda + control) ===
            Flow {
                anchors.top: lengthRow.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 20
                spacing: 8

                Repeater {
                    model: [
                        { label: "a-z", key: "useLower", sw: Colors.overBackground },
                        { label: "A-Z", key: "useUpper", sw: Colors.primary },
                        { label: "0-9", key: "useDigits", sw: Colors.tertiary },
                        { label: "!@#", key: "useSymbols", sw: Colors.error },
                        { label: "No Ambiguous", key: "avoidAmbiguous", sw: Colors.outline }
                    ]
                    delegate: Rectangle {
                        id: tgChip
                        required property var modelData
                        readonly property bool on: PasswordService[modelData.key]
                        height: 38
                        width: tgRow.implicitWidth + 26
                        radius: height / 2
                        color: tgChip.on ? Qt.rgba(modelData.sw.r, modelData.sw.g, modelData.sw.b, 0.22) : Colors.surfaceContainer
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Row {
                            id: tgRow
                            anchors.centerIn: parent
                            spacing: 8
                            Rectangle {
                                width: 9
                                height: 9
                                radius: 4.5
                                color: tgChip.modelData.sw
                                opacity: tgChip.on ? 1 : 0.3
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: tgChip.modelData.label
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: tgChip.on ? Font.Bold : Font.Medium
                                color: tgChip.on ? Colors.overBackground : Colors.outline
                                anchors.verticalCenter: parent.verticalCenter
                            }
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

            // === Input ===
            Rectangle {
                id: devBox
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                height: 96
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 14
                    anchors.bottomMargin: 28
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
                        placeholderText: "Input (text, JSON, etc)..."
                        placeholderTextColor: Colors.outline
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.fontSize(0)
                        selectByMouse: true
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 14
                    anchors.bottomMargin: 8
                    visible: devInput.text.length > 0
                    text: devInput.text.length + " chars"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.outline
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    width: 26
                    height: 26
                    radius: width / 2
                    visible: devInput.text.length > 0
                    color: devClearMouse.containsMouse ? Colors.surfaceContainerHighest : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: Icons.cancel
                        font.family: Icons.font
                        font.pixelSize: 12
                        color: Colors.outline
                    }
                    MouseArea {
                        id: devClearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            devInput.text = "";
                            dock.devLastOp = "";
                        }
                    }
                }
            }

            // === Operaciones (chip activo = último op) ===
            Flow {
                id: opsFlow
                anchors.top: devBox.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                anchors.topMargin: 12
                spacing: 7

                Repeater {
                    model: DevToolsService.ops
                    delegate: Rectangle {
                        id: opChip
                        required property var modelData
                        readonly property bool active: dock.devLastOp === modelData.label
                        height: 34
                        width: opText.implicitWidth + 24
                        radius: height / 2
                        color: opChip.active ? Colors.primary : (opMouse.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            id: opText
                            anchors.centerIn: parent
                            text: opChip.modelData.label
                            font.family: Config.theme.monoFont
                            font.pixelSize: Styling.fontSize(-2)
                            font.weight: opChip.active ? Font.Bold : Font.Medium
                            color: opChip.active ? Colors.overPrimary : Colors.overBackground
                        }
                        MouseArea {
                            id: opMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                dock.devLastOp = opChip.modelData.label;
                                DevToolsService.run(opChip.modelData.key, devInput.text);
                            }
                        }
                    }
                }
            }

            // === Output (header con el op + copiar) ===
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
                clip: true

                Timer { id: devCopyTimer; interval: 1300; onTriggered: devCopyBtn.copied = false }

                // Header
                Rectangle {
                    id: devOutHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 36
                    color: Colors.surfaceContainerHighest
                    visible: DevToolsService.output !== "" || DevToolsService.error !== ""

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 14
                        spacing: 7
                        Text {
                            text: Icons.terminal
                            font.family: Icons.font
                            font.pixelSize: 13
                            color: DevToolsService.error !== "" ? Colors.error : Colors.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: DevToolsService.error !== "" ? "Error" : (dock.devLastOp || "Output")
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            font.weight: Font.Bold
                            color: DevToolsService.error !== "" ? Colors.error : Colors.overBackground
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Rectangle {
                        id: devCopyBtn
                        property bool copied: false
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 6
                        width: 28
                        height: 28
                        radius: width / 2
                        visible: DevToolsService.output !== ""
                        color: devCopyMouse.containsMouse ? Colors.primary : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            anchors.centerIn: parent
                            text: devCopyBtn.copied ? Icons.accept : Icons.copy
                            font.family: Icons.font
                            font.pixelSize: 13
                            color: devCopyBtn.copied ? Colors.primary : (devCopyMouse.containsMouse ? Colors.overPrimary : Colors.overBackground)
                        }
                        MouseArea {
                            id: devCopyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                dock.copyNoteText(DevToolsService.output);
                                devCopyBtn.copied = true;
                                devCopyTimer.restart();
                            }
                        }
                    }
                }

                // Body
                Item {
                    anchors.top: (DevToolsService.output !== "" || DevToolsService.error !== "") ? devOutHeader.bottom : parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom

                    Text {
                        anchors.centerIn: parent
                        visible: DevToolsService.output === "" && DevToolsService.error === ""
                        text: "Pick an operation"
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

            // wl-paste → input
            Process {
                id: qrPasteProc
                running: false
                stdout: StdioCollector {
                    id: qrPasteOut
                    waitForEnd: true
                }
                onExited: code => { if (code === 0) qrInput.text = qrPasteOut.text.replace(/\n+$/, ""); }
            }
            // copiar PNG del QR al portapapeles
            Process { id: qrImgCopyProc; running: false }

            // === Input ===
            Rectangle {
                id: qrInputBox
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: dock.hPadding
                anchors.rightMargin: dock.hPadding
                height: 96
                radius: Styling.radius(2)
                color: Colors.surfaceContainerHigh

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 14
                    anchors.bottomMargin: 30
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
                        placeholderText: "Text or URL for the QR..."
                        placeholderTextColor: Colors.outline
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        selectByMouse: true
                        onTextChanged: qrDebounce.restart()
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 14
                    anchors.bottomMargin: 9
                    visible: qrInput.text.length > 0
                    text: qrInput.text.length + " chars"
                    font.family: Config.theme.monoFont
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.outline
                }

                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 7
                    spacing: 4

                    // Pegar del portapapeles
                    Rectangle {
                        width: 26
                        height: 26
                        radius: width / 2
                        color: qrPasteMouse.containsMouse ? Colors.surfaceContainerHighest : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Icons.clipboard
                            font.family: Icons.font
                            font.pixelSize: 12
                            color: Colors.outline
                        }
                        MouseArea {
                            id: qrPasteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { qrPasteProc.command = ["sh", "-c", "wl-paste -n"]; qrPasteProc.running = true; }
                        }
                    }
                    // Limpiar
                    Rectangle {
                        width: 26
                        height: 26
                        radius: width / 2
                        visible: qrInput.text.length > 0
                        color: qrClearMouse.containsMouse ? Colors.surfaceContainerHighest : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Icons.cancel
                            font.family: Icons.font
                            font.pixelSize: 12
                            color: Colors.outline
                        }
                        MouseArea {
                            id: qrClearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: qrInput.text = ""
                        }
                    }
                }
            }

            // === Área del QR ===
            Rectangle {
                id: qrArea
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
                clip: true

                // Placeholder
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    visible: !QrService.ready

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Icons.qrCode
                        font.family: Icons.font
                        font.pixelSize: 50
                        color: Colors.outlineVariant
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Type Something Above"
                        font.family: Config.theme.font
                        font.capitalization: Font.Capitalize
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.outline
                    }
                }

                // Card blanca con el QR
                Rectangle {
                    id: qrCard
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 18
                    width: Math.min(qrArea.width - 36, qrArea.height - 80, 280)
                    height: width
                    radius: Styling.radius(0)
                    color: "#ffffff"
                    visible: QrService.ready

                    Image {
                        anchors.fill: parent
                        anchors.margins: 12
                        source: QrService.ready ? ("file://" + QrService.outPath + "?r=" + QrService.revision) : ""
                        cache: false
                        fillMode: Image.PreserveAspectFit
                        smooth: false
                    }
                }

                // Footer: texto codificado + copiar imagen
                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    height: 42
                    visible: QrService.ready

                    Text {
                        anchors.left: parent.left
                        anchors.right: copyImgBtn.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 8
                        text: qrInput.text
                        font.family: Config.theme.monoFont
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.outline
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Rectangle {
                        id: copyImgBtn
                        property bool copied: false
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 30
                        width: copyImgRow.implicitWidth + 22
                        radius: height / 2
                        color: copyImgMouse.containsMouse ? Colors.primary : Colors.surfaceContainerHighest
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Timer { id: qrImgCopyTimer; interval: 1300; onTriggered: copyImgBtn.copied = false }
                        Row {
                            id: copyImgRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: copyImgBtn.copied ? Icons.accept : Icons.image
                                font.family: Icons.font
                                font.pixelSize: 13
                                color: copyImgBtn.copied ? Colors.primary : (copyImgMouse.containsMouse ? Colors.overPrimary : Colors.overBackground)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: copyImgBtn.copied ? "Copied" : "Copy image"
                                font.family: Config.theme.font
                                font.capitalization: Font.Capitalize
                                font.pixelSize: Styling.fontSize(-2)
                                font.weight: Font.Medium
                                color: copyImgBtn.copied ? Colors.primary : (copyImgMouse.containsMouse ? Colors.overPrimary : Colors.overBackground)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: copyImgMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                qrImgCopyProc.command = ["sh", "-c", "wl-copy --type image/png < " + QrService.outPath];
                                qrImgCopyProc.running = true;
                                copyImgBtn.copied = true;
                                qrImgCopyTimer.restart();
                            }
                        }
                    }
                }
            }
        }
    }
}
