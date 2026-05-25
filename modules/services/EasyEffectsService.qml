pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // EasyEffects availability
    property bool available: false
    
    // Bypass: false = active, true = bypassed
    property bool bypassed: false
    
    // Available presets
    property var outputPresets: []
    property var inputPresets: []
    
    // Currently active presets
    property string activeOutputPreset: ""
    property string activeInputPreset: ""

    // Toggle bypass state
    function toggleBypass() {
        bypassToggleProcess.command = ["easyeffects", "-b", bypassed ? "2" : "1"];
        bypassToggleProcess.running = true;
    }
    
    function setBypass(enable: bool) {
        bypassToggleProcess.command = ["easyeffects", "-b", enable ? "1" : "2"];
        bypassToggleProcess.running = true;
    }

    // Load preset (optimistic)
    function loadOutputPreset(name: string) {
        root.activeOutputPreset = name;  // Optimistic
        loadPresetProcess.command = ["easyeffects", "-l", name];
        loadPresetProcess.running = true;
    }

    // Write custom equalizer gains and load preset
    function applyEqualizer(gains) {
        let freqs = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
        let leftObj = {};
        let rightObj = {};
        for (let i = 0; i < 10; i++) {
            let gainVal = gains[i];
            let bandObj = {
                "frequency": freqs[i],
                "gain": gainVal,
                "mode": "RLC (BT)",
                "mute": false,
                "q": 1.41,
                "slope": "x1",
                "solo": false,
                "type": "Bell"
            };
            leftObj["band" + i] = bandObj;
            rightObj["band" + i] = bandObj;
        }

        let preset = {
            "output": {
                "blocklist": [],
                "equalizer": {
                    "input-gain": 0.0,
                    "left": leftObj,
                    "right": rightObj
                }
            }
        };

        root.activeOutputPreset = "ambxst_eq";
        writePresetProcess.command = [
            "bash", "-c", 
            "mkdir -p ~/.config/easyeffects/output && echo '" + JSON.stringify(preset) + "' > ~/.config/easyeffects/output/ambxst_eq.json && easyeffects -l ambxst_eq"
        ];
        writePresetProcess.running = true;
    }


    function loadInputPreset(name: string) {
        root.activeInputPreset = name;  // Optimistic
        loadPresetProcess.command = ["easyeffects", "-l", name];
        loadPresetProcess.running = true;
    }

    // Compatibility legacy function
    function loadPreset(name: string) {
        loadPresetProcess.command = ["easyeffects", "-l", name];
        loadPresetProcess.running = true;
    }

    // Refresh all data
    function refresh() {
        checkAvailableProcess.running = true;
    }

    // Open EasyEffects app
    function openApp() {
        Quickshell.execDetached(["easyeffects"]);
    }

    property bool _initialized: false

    function initialize() {
        if (_initialized) return;
        _initialized = true;
        checkAvailableProcess.running = true;
    }

    // Check EasyEffects availability
    Process {
        id: checkAvailableProcess
        command: ["which", "easyeffects"]
        running: false
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0);
            if (root.available) {
                // Fetch initial state
                bypassStateProcess.running = true;
                presetsProcess.running = true;
                activePresetsProcess.running = true;
            }
        }
    }

    // Get bypass state
    Process {
        id: bypassStateProcess
        command: ["easyeffects", "-b", "3"]
        running: false
        environment: ({ LANG: "C.UTF-8", LC_ALL: "C.UTF-8" })
        stdout: SplitParser {
            onRead: data => {
                const val = data.trim();
                root.bypassed = (val === "1");
            }
        }
    }

    // Toggle bypass
    Process {
        id: bypassToggleProcess
        running: false
        onExited: {
            bypassStateProcess.running = true;
        }
    }

    // Load preset
    Process {
        id: loadPresetProcess
        running: false
        onExited: {
            // Delay for preset application
            refreshDelayTimer.restart();
        }
    }

    // Write custom preset
    Process {
        id: writePresetProcess
        running: false
    }

    // Refresh delay after preset load
    property var refreshDelayTimer: Timer {
        id: refreshDelayTimer
        interval: 100
        repeat: false
        onTriggered: {
            activePresetsProcess.running = true;
            bypassStateProcess.running = true;
        }
    }

    // List presets
    Process {
        id: presetsProcess
        command: ["easyeffects", "-p"]
        running: false
        property string buffer: ""
        environment: ({ LANG: "C.UTF-8", LC_ALL: "C.UTF-8" })
        stdout: SplitParser {
            onRead: data => {
                presetsProcess.buffer += data + "\n";
            }
        }
        onExited: {
            const text = presetsProcess.buffer;
            presetsProcess.buffer = "";
            
            const lines = text.split("\n");
            let isOutput = false;
            let isInput = false;
            let outputList = [];
            let inputList = [];
            
            for (const line of lines) {
                const trimmed = line.trim();
                if (trimmed.toLowerCase().includes("output")) {
                    isOutput = true;
                    isInput = false;
                    // Check if presets follow colon
                    const parts = trimmed.split(":");
                    if (parts.length > 1 && parts[1].trim()) {
                        outputList = parts[1].trim().split(",").map(p => p.trim()).filter(p => p);
                    }
                } else if (trimmed.toLowerCase().includes("input")) {
                    isInput = true;
                    isOutput = false;
                    const parts = trimmed.split(":");
                    if (parts.length > 1 && parts[1].trim()) {
                        inputList = parts[1].trim().split(",").map(p => p.trim()).filter(p => p);
                    }
                } else if (trimmed && !trimmed.includes(":")) {
                    // Preset name on its own line
                    if (isOutput) outputList.push(trimmed);
                    else if (isInput) inputList.push(trimmed);
                }
            }
            
            root.outputPresets = outputList;
            root.inputPresets = inputList;
        }
    }

    // Get active presets
    Process {
        id: activePresetsProcess
        command: ["easyeffects", "-a"]
        running: false
        property string buffer: ""
        environment: ({ LANG: "C.UTF-8", LC_ALL: "C.UTF-8" })
        stdout: SplitParser {
            onRead: data => {
                activePresetsProcess.buffer += data + "\n";
            }
        }
        onExited: {
            const text = activePresetsProcess.buffer;
            activePresetsProcess.buffer = "";
            
            const lines = text.split("\n");
            for (const line of lines) {
                const trimmed = line.trim().toLowerCase();
                if (trimmed.includes("output")) {
                    const parts = line.split(":");
                    if (parts.length > 1) {
                        root.activeOutputPreset = parts[1].trim();
                    }
                } else if (trimmed.includes("input")) {
                    const parts = line.split(":");
                    if (parts.length > 1) {
                        root.activeInputPreset = parts[1].trim();
                    }
                }
            }
        }
    }

    // Periodically poll state
    property var pollTimer: Timer {
        interval: 5000
        running: root.available && !SuspendManager.isSuspending
        repeat: true
        onTriggered: {
            bypassStateProcess.running = true;
            activePresetsProcess.running = true;
        }
    }
}
