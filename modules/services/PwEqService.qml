pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Ecualizador de 10 bandas sobre un filter-chain NATIVO de PipeWire.
// Reemplaza la integración con EasyEffects (cuyo CLI no aplica el DSP en EE 8).
//
// Depende del sink virtual "ambxst_eq_sink" que crea
// ~/.config/pipewire/pipewire.conf.d/99-ambxst-eq.conf (10 filtros biquad).
// Las ganancias se cambian en vivo por params del nodo:
//   pw-cli set-param <id> Props '{ params = [ "eq_band_N:Gain" <dB> ] }'
Singleton {
    id: root

    // El sink del EQ existe (filter-chain cargado).
    property bool available: false
    // El audio del sistema pasa por el EQ (su sink es el default).
    property bool audioRouted: false
    // Bypass: aplica 0 dB en todas las bandas sin perder la curva del usuario.
    property bool bypassed: false

    // Última curva aplicada (dB por banda). Se persiste y se re-aplica al inicio
    // porque el filter-chain arranca en 0 tras cada reinicio de PipeWire.
    property var gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]

    // Estado de UI del EqualizerTab (sobrevive a la recarga del tab al cambiar de
    // pestaña; el tab se destruye y perdía la selección).
    property string uiPreset: ""
    property var uiBands: []
    property bool uiPending: false

    readonly property string sinkName: "ambxst_eq_sink"
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ambxst/eq-gains"

    property bool _initialized: false
    function initialize() {
        if (_initialized) return;
        _initialized = true;
        checkAvailableProcess.running = true;
    }

    function refresh() {
        checkAvailableProcess.running = true;
    }

    // Construye la lista de params "eq_band_N:Gain g" para pw-cli.
    function _paramsList(g) {
        let parts = [];
        for (let i = 0; i < 10; i++)
            parts.push('"eq_band_' + (i + 1) + ':Gain" ' + Number(g[i] || 0).toFixed(2));
        return parts.join(" ");
    }

    // Aplica la curva al filter-chain en vivo y la persiste.
    function applyEqualizer(g) {
        root.gains = g.slice();
        root.bypassed = false;
        _setParams(g, /*persist*/ true);
    }

    function toggleBypass() {
        root.bypassed = !root.bypassed;
        _setParams(root.bypassed ? [0,0,0,0,0,0,0,0,0,0] : root.gains, /*persist*/ false);
    }

    // Resuelve el id del nodo del sink por nombre (cambia por sesión) vía awk
    // sobre `pw-cli ls Node`. Las comillas dobles van literales dentro de /.../.
    readonly property string _resolveNode: 'node=$(pw-cli ls Node | awk \'/^[[:space:]]*id [0-9]+/{i=$2} /node.name = "' + root.sinkName + '"/{gsub(/,/,"",i); print i; exit}\')'

    function _setParams(g, persist) {
        // El persist guarda la curva real del usuario (no el bypass) en $2 desde $3.
        let persistCmd = persist
            ? '; mkdir -p "$(dirname "$2")"; printf %s "$3" > "$2"'
            : '';
        applyProcess.command = [
            "bash", "-c",
            root._resolveNode + '; [ -n "$node" ] && pw-cli set-param "$node" Props "{ params = [ $1 ] }"' + persistCmd,
            "ambxst", root._paramsList(g), root.stateFile, root.gains.join(" ")
        ];
        applyProcess.running = true;
    }

    // Pone el sink del EQ como salida por defecto (persiste vía WirePlumber).
    function routeToEq() {
        routeProcess.running = true;
    }
    // Alias por compatibilidad con el botón del tab.
    function routeThroughEE() { routeToEq(); }

    function checkRouting() {
        routingCheckProcess.buffer = "";
        routingCheckProcess.running = true;
    }

    // ── Procesos ──────────────────────────────────────────────────────────────

    // ¿Existe el sink del EQ? Si sí, carga la curva persistida y la aplica.
    Process {
        id: checkAvailableProcess
        command: ["bash", "-c", "pw-cli ls Node | grep -q 'node.name = \"" + root.sinkName + "\"'"]
        running: false
        onExited: code => {
            root.available = (code === 0);
            if (root.available) {
                loadStateProcess.running = true;
                root.checkRouting();
            }
        }
    }

    // Lee la curva persistida (si existe) y la aplica al filter-chain.
    Process {
        id: loadStateProcess
        command: ["bash", "-c", "cat \"" + root.stateFile + "\" 2>/dev/null"]
        running: false
        property string buffer: ""
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: loadStateProcess.buffer = this.text.trim()
        }
        onExited: {
            const t = loadStateProcess.buffer;
            loadStateProcess.buffer = "";
            if (t.length > 0) {
                const arr = t.split(/\s+/).map(x => parseFloat(x));
                if (arr.length === 10 && arr.every(x => !isNaN(x))) {
                    root.gains = arr;
                    root._setParams(arr, /*persist*/ false);
                }
            }
        }
    }

    Process {
        id: applyProcess
        running: false
    }

    // ¿El sink del EQ es el default?
    Process {
        id: routingCheckProcess
        command: ["wpctl", "inspect", "@DEFAULT_AUDIO_SINK@"]
        running: false
        property string buffer: ""
        environment: ({ LANG: "C.UTF-8", LC_ALL: "C.UTF-8" })
        stdout: SplitParser {
            onRead: data => routingCheckProcess.buffer += data + "\n"
        }
        onExited: code => {
            root.audioRouted = (code === 0 && routingCheckProcess.buffer.indexOf('node.name = "' + root.sinkName + '"') >= 0);
            routingCheckProcess.buffer = "";
        }
    }

    // Setea el sink del EQ como default (resuelve el id por nombre).
    Process {
        id: routeProcess
        command: ["bash", "-c", root._resolveNode + '; [ -n "$node" ] && wpctl set-default "$node"']
        running: false
        onExited: root.checkRouting()
    }

    // Poll suave del estado de ruteo.
    property var pollTimer: Timer {
        interval: 5000
        running: root.available && !SuspendManager.isSuspending
        repeat: true
        onTriggered: root.checkRouting()
    }
}
