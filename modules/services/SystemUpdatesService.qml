pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals

// Chequeo de actualizaciones de paquetes del sistema (repos oficiales + AUR).
// - `checkupdates` (pacman-contrib) usa una DB temporal aparte: NO toca la base de
//   pacman ni requiere sudo, y es seguro correrlo repetido.
// - `yay -Qua` lista updates de AUR.
// Ambos corren async vía Process y se pollean en un Timer gateado (no continuo).
Singleton {
    id: root

    // [{ source: "repo"|"aur", pkg, oldVer, newVer }]
    property var updates: []
    property int count: 0
    property int repoCount: 0
    property int aurCount: 0
    property bool checking: false
    property bool ready: false          // ya hubo al menos un resultado
    property double lastCheck: 0        // epoch ms

    readonly property int pollInterval: 3600000  // 1h

    function refresh() {
        if (checkProc.running)
            return;
        root.checking = true;
        checkProc.running = true;
    }

    // Abre una terminal kitty FLOTANTE y corre `yay -Syu` (repos + AUR).
    // --hold deja la ventana abierta al terminar para ver el resultado.
    // La contraseña de sudo se pide ahí, en la terminal (nunca en silencio).
    function upgrade() {
        Quickshell.execDetached(["hyprctl", "dispatch", "exec",
            "[float; size 1000 620; center] kitty --hold --class kitty-float -e yay -Syu"]);
    }

    // Igual que upgrade() pero para un solo paquete (yay -S <pkg>).
    function upgradeOne(pkg) {
        Quickshell.execDetached(["hyprctl", "dispatch", "exec",
            "[float; size 1000 620; center] kitty --hold --class kitty-float -e yay -S " + pkg]);
    }

    Process {
        id: checkProc
        running: false
        command: ["bash", "-c", "checkupdates 2>/dev/null | sed 's/^/R /'; yay -Qua 2>/dev/null | sed 's/^/A /'"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var lines = text.trim().split("\n");
                var list = [];
                var repo = 0, aur = 0;
                for (var i = 0; i < lines.length; i++) {
                    var ln = lines[i].trim();
                    if (ln.length === 0)
                        continue;
                    // formato: "R pkg old -> new"  o  "A pkg old -> new"
                    var p = ln.split(/\s+/);
                    if (p.length < 5)
                        continue;
                    var src = p[0] === "A" ? "aur" : "repo";
                    if (src === "aur") aur++; else repo++;
                    list.push({ source: src, pkg: p[1], oldVer: p[2], newVer: p[4] });
                }
                // repos primero, luego AUR; alfabético dentro de cada grupo
                list.sort(function (a, b) {
                    if (a.source !== b.source)
                        return a.source === "repo" ? -1 : 1;
                    return a.pkg.localeCompare(b.pkg);
                });
                root.updates = list;
                root.count = list.length;
                root.repoCount = repo;
                root.aurCount = aur;
                root.lastCheck = Date.now();
                root.ready = true;
                root.checking = false;
            }
        }

        onExited: function (code, status) {
            root.checking = false;
        }
    }

    // Poll throttled, gateado en suspend. Chequea al iniciar y cada hora.
    Timer {
        interval: root.pollInterval
        running: !SuspendManager.isSuspending
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
