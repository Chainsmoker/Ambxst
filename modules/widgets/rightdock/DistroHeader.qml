pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.theme
import qs.modules.globals

Item {
    id: root

    // GIF / static image override. Default cae a la wallpaper actual.
    property string headerImage: ""
    property string distroName: "Linux"
    property string distroLogo: ""
    property string hostName: ""

    // HOSTNAME no se exporta al entorno (Quickshell.env lo ve null), así que
    // corremos el comando `hostname` como hacen UserInfo/MetricsTab.
    Process {
        command: ["hostname"]
        running: true
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.hostName = this.text.trim()
        }
    }

    readonly property string activeImage: {
        if (headerImage && headerImage.length > 0) return headerImage;
        if (GlobalStates.wallpaperManager) {
            const w = GlobalStates.wallpaperManager.currentWallpaper;
            if (w) return w;
        }
        return "";
    }

    // Lee /etc/os-release
    FileView {
        path: "/etc/os-release"
        onLoaded: {
            const lines = text().split("\n");
            let pretty = "", id = "", logo = "", idLike = "";
            const val = line => line.split("=").slice(1).join("=").replace(/^"|"$/g, "");
            for (let line of lines) {
                if (line.startsWith("PRETTY_NAME=")) pretty = val(line);
                else if (line.startsWith("ID=")) id = val(line);
                else if (line.startsWith("ID_LIKE=")) idLike = val(line);
                else if (line.startsWith("LOGO=")) logo = val(line);
            }
            if (pretty) root.distroName = pretty;

            // Nombres a probar, en orden de preferencia: LOGO (campo estándar de
            // os-release, p.ej. CachyOS define LOGO=cachyos) → ID → cada token de
            // ID_LIKE (deriva al logo del padre: cachyos/archcraft → arch) →
            // genérico freedesktop.
            const names = [];
            const push = n => { if (n && names.indexOf(n) < 0) names.push(n); };
            push(logo);
            push(id);
            for (const l of idLike.split(/\s+/)) push(l);
            push("distributor-logo");

            // Dónde: pixmaps + icon themes (CachyOS instala su icono en hicolor,
            // no en pixmaps con ese nombre).
            const bases = [
                "/usr/share/pixmaps/",
                "/usr/share/icons/hicolor/scalable/apps/",
                "/usr/share/icons/hicolor/256x256/apps/",
                "/usr/share/icons/hicolor/128x128/apps/"
            ];
            const suffixes = ["-logo.svg", ".svg", "-logo.png", ".png"];

            const candidates = [];
            for (const n of names)
                for (const b of bases)
                    for (const s of suffixes)
                        candidates.push(b + n + s);

            logoCheck.candidates = candidates;
            logoCheck.idx = 0;
            logoCheck.tryNext();
        }
    }

    Item {
        id: logoCheck
        property var candidates: []
        property int idx: 0

        function tryNext() {
            if (idx >= candidates.length) return;
            checkProcess.command = ["test", "-f", candidates[idx]];
            checkProcess.running = true;
        }

        Process {
            id: checkProcess
            onExited: code => {
                if (code === 0) {
                    root.distroLogo = "file://" + logoCheck.candidates[logoCheck.idx];
                } else {
                    logoCheck.idx++;
                    logoCheck.tryNext();
                }
            }
        }
    }

    // ── Imagen fondo ──
    AnimatedImage {
        id: animatedBg
        anchors.fill: parent
        source: root.activeImage.endsWith(".gif") ? root.activeImage : ""
        fillMode: Image.PreserveAspectCrop
        visible: source.toString().length > 0
        playing: visible
        cache: true
        asynchronous: true
    }

    Image {
        id: staticBg
        anchors.fill: parent
        source: !root.activeImage.endsWith(".gif") ? root.activeImage : ""
        fillMode: Image.PreserveAspectCrop
        visible: source.toString().length > 0 && !animatedBg.visible
        cache: true
        asynchronous: true
    }

    // Tinte oscuro + gradient inferior para legibilidad
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.25
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.7
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Colors.background }
        }
    }

    // ── Content ──
    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: 14
        spacing: 12

        Item {
            id: logoBox
            width: 44
            height: 44
            anchors.verticalCenter: parent.verticalCenter

            Image {
                anchors.fill: parent
                source: root.distroLogo
                visible: source.toString().length > 0
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 88
                sourceSize.height: 88
                smooth: true
            }

            Rectangle {
                anchors.fill: parent
                radius: 22
                color: Colors.primaryContainer
                visible: root.distroLogo.length === 0

                Text {
                    anchors.centerIn: parent
                    text: root.distroName.charAt(0).toUpperCase()
                    color: Colors.overPrimaryContainer
                    font.family: Config.theme.font
                    font.pixelSize: 22
                    font.weight: Font.Bold
                }
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                text: root.distroName
                color: "white"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(3)
                font.weight: Font.Bold
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.4)
            }

            Text {
                text: Quickshell.env("USER") + "@" + root.hostName
                color: Qt.rgba(1, 1, 1, 0.85)
                font.family: Config.theme.monoFont
                font.pixelSize: Styling.fontSize(-1)
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.4)
            }
        }
    }
}
