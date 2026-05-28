pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property bool isRecording: false
    property bool paused: false
    // ¿Está abierta la pill flotante? Por defecto NO: al grabar sólo se ve el
    // punto en el notch; el usuario la abre con click en el punto y la cierra
    // con la ✕. Se resetea (cerrada) al iniciar/terminar cada grabación.
    property bool floatingOpen: false
    // Tiempo grabado contado INTERNAMENTE (no con `ps etime`), para poder
    // congelarlo en pausa — gsr sigue vivo aunque esté pausado, así que su
    // tiempo de proceso seguiría corriendo y parecería que la pausa no funciona.
    property int elapsedSeconds: 0
    readonly property string duration: {
        const s = root.elapsedSeconds;
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const sec = s % 60;
        const pad = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? (h + ":" + pad(m) + ":" + pad(sec)) : (pad(m) + ":" + pad(sec));
    }
    property Timer elapsedTimer: Timer {
        interval: 1000
        repeat: true
        running: root.isRecording && !root.paused && !SuspendManager.isSuspending
        onTriggered: root.elapsedSeconds++
    }
    property string lastError: ""
    property bool canRecordDirectly: true // Optimistic default

    property bool _initialized: false

    function initialize() {
        if (_initialized) return;
        _initialized = true;
        checkCapabilitiesProcess.running = true;
        xdgVideosProcess.running = true;
        checkProcess.running = true;
    }

    property Process checkCapabilitiesProcess: Process {
        id: checkCapabilitiesProcess
        command: ["bash", "-c", "if [ -f /run/current-system/sw/bin/nixos-version ]; then if [[ \"$(type -p gpu-screen-recorder)\" == *\"/run/wrappers/bin/\"* ]]; then echo true; else echo false; fi; else echo true; fi"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                root.canRecordDirectly = (text.trim() === "true");
            }
        }
    }

    property string videosDir: ""

    // Resolve Videos dir
    property Process xdgVideosProcess: Process {
        id: xdgVideosProcess
        command: ["bash", "-c", "xdg-user-dir VIDEOS"]
        running: false
        stdout: StdioCollector {
            onTextChanged: {
                // Handled in onExited
            }
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                var dir = xdgVideosProcess.stdout.text.trim();
                if (dir === "") {
                    dir = Quickshell.env("HOME") + "/Videos";
                }
                root.videosDir = dir + "/Recordings";
            } else {
                root.videosDir = Quickshell.env("HOME") + "/Videos/Recordings";
            }
        }
    }

    // Poll — only when actively recording
    property Timer statusTimer: Timer {
        interval: 1000
        repeat: true
        running: root.isRecording && !SuspendManager.isSuspending
        onTriggered: {
            checkProcess.running = true;
        }
    }

    property Process checkProcess: Process {
        id: checkProcess
        command: ["bash", "-c", "pgrep -f 'gpu-screen-recorder' | grep -v $$ > /dev/null"]
        onExited: exitCode => {
            var wasRecording = root.isRecording;
            root.isRecording = (exitCode === 0);

            if (root.isRecording && !wasRecording) {
                console.log("[ScreenRecorder] Detected running instance.");
                root.floatingOpen = false; // arranca en modo "punto en el notch"
            }

            if (!root.isRecording) {
                root.paused = false;
                root.floatingOpen = false;
                root.elapsedSeconds = 0;
            }
        }
    }

    function toggleRecording() {
        if (isRecording) {
            stopProcess.running = true;
        } else {
            // Default: Portal, no audio
            startRecording(false, false, "portal", "");
        }
    }

    // Pausa/reanuda gpu-screen-recorder con SIGUSR2 (toggle). El contador
    // interno (elapsedTimer) se congela porque deja de correr con `paused`.
    function togglePause() {
        if (!isRecording)
            return;
        pauseProcess.running = true;
        paused = !paused;
    }

    // Patrón anclado (^) como recomienda el man de gpu-screen-recorder: apunta
    // sólo al proceso del grabador, no a wrappers ni a otros procesos que
    // contengan "gpu-screen-recorder" en su línea de comando.
    property Process pauseProcess: Process {
        id: pauseProcess
        command: ["pkill", "-SIGUSR2", "-f", "^gpu-screen-recorder"]
    }

    function startRecording(recordAudioOutput, recordAudioInput, mode, regionStr) {
        if (isRecording)
            return;

        var outputFile = root.videosDir + "/" + new Date().toISOString().replace(/[:.]/g, "-") + ".mp4";
        var cmd = "gpu-screen-recorder -f 60";

        // Window mode
        if (mode === "portal") {
            cmd += " -w portal";
        } else if (mode === "screen") {
            cmd += " -w screen";
        } else if (mode === "region") {
            cmd += " -w region";
            if (regionStr) {
                cmd += " -region " + regionStr;
            }
        }

        // Audio sources
        var audioSources = [];
        if (recordAudioOutput)
            audioSources.push("default_output");
        if (recordAudioInput)
            audioSources.push("default_input");

        if (audioSources.length === 1) {
            cmd += " -a " + audioSources[0];
        } else if (audioSources.length > 1) {
            cmd += " -a \"" + audioSources.join("|") + "\"";
        }

        cmd += " -o \"" + outputFile + "\"";

        console.log("[ScreenRecorder] Starting with command: " + cmd);
        startProcess.command = ["bash", "-c", cmd];

        prepareProcess.running = true;
    }

    // 1. Create dir
    property Process prepareProcess: Process {
        id: prepareProcess
        command: ["mkdir", "-p", root.videosDir]
        onExited: exitCode => {
            // notifyStartProcess suprimido: el indicador animado bajo el notch
            // (RecordingIndicator.qml) reemplaza la notificación de inicio.
            startProcess.running = true;
            root.isRecording = true;
            root.paused = false;
            root.floatingOpen = false; // arranca oculta: sólo el punto en el notch
            root.elapsedSeconds = 0;
        }
    }

    // 2. Notify
    property Process notifyStartProcess: Process {
        id: notifyStartProcess
        command: ["notify-send", "Screen Recorder", "Starting recording..."]
    }

    // 3. Start
    property Process startProcess: Process {
        id: startProcess
        command: ["bash", "-c", "echo 'Error: Command not set'"]

        stdout: StdioCollector {
            onTextChanged: console.log("[ScreenRecorder] OUT: " + text)
        }
        stderr: StdioCollector {
            id: stderrCollector
            onTextChanged: {
                console.warn("[ScreenRecorder] ERR: " + text);
                // root.lastError = text // verbose
            }
        }

        onExited: exitCode => {
            console.log("[ScreenRecorder] Exited with code: " + exitCode);
            if (exitCode !== 0 && exitCode !== 130 && exitCode !== 2) { // 2 = SIGINT
                root.isRecording = false;
                notifyErrorProcess.running = true;
            } else {
                notifySavedProcess.running = true;
            }
        }
    }

    property Process notifyErrorProcess: Process {
        id: notifyErrorProcess
        command: ["notify-send", "-u", "critical", "Screen Recorder Error", "Failed to start. Check logs."]
    }

    property Process notifySavedProcess: Process {
        id: notifySavedProcess
        command: ["notify-send", "Screen Recorder", "Recording saved to " + root.videosDir]
    }

    property Process openVideosProcess: Process {
        id: openVideosProcess
        command: ["xdg-open", root.videosDir]
    }

    function openRecordingsFolder() {
        openVideosProcess.running = true;
    }

    property Process stopProcess: Process {
        id: stopProcess
        command: ["pkill", "-SIGINT", "-f", "gpu-screen-recorder"]
    }
}
