pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Generates a QR PNG from arbitrary text via `qrencode`.
 * `revision` bumps on each render so the UI Image can bust Qt's cache.
 */
Singleton {
    id: root

    property string text: ""
    property bool ready: false
    property int revision: 0
    readonly property string outDir: "/tmp/ambxst-qr"
    readonly property string outPath: outDir + "/qr.png"

    function generate() {
        if (root.text.trim() === "") {
            root.ready = false;
            return;
        }
        mkdirProc.running = true;
    }

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.outDir]
        running: false
        onExited: code => {
            if (code === 0)
                root._render();
        }
    }

    function _render() {
        // black-on-white PNG, generous margin so it scans; text via $1 (safe).
        qrProc.command = ["bash", "-c", "printf %s \"$1\" | qrencode -o " + root.outPath + " -s 10 -m 2 -t PNG", "--", root.text];
        qrProc.running = true;
    }

    Process {
        id: qrProc
        running: false
        onExited: code => {
            if (code === 0) {
                root.revision++;
                root.ready = true;
            } else {
                root.ready = false;
            }
        }
    }
}
