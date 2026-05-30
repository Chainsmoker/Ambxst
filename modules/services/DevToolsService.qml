pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Local dev encoder/converter. Pure-JS ops run inline; ops that need a tool
 * (base64, jq, hashes, uuid) shell out. One Process at a time (ops are quick).
 */
Singleton {
    id: root

    property string output: ""
    property string error: ""

    // Operations shown as chips in the UI.
    readonly property var ops: [
        { label: "Base64 ↑", key: "b64enc" },
        { label: "Base64 ↓", key: "b64dec" },
        { label: "URL ↑", key: "urlenc" },
        { label: "URL ↓", key: "urldec" },
        { label: "JSON", key: "jsonpretty" },
        { label: "Min", key: "jsonmin" },
        { label: "SHA-256", key: "sha256" },
        { label: "MD5", key: "md5" },
        { label: "Epoch ↔", key: "epoch" },
        { label: "UUID", key: "uuid" }
    ]

    function run(op, input) {
        root.error = "";
        input = input || "";
        switch (op) {
        case "urlenc":
            root.output = encodeURIComponent(input);
            return;
        case "urldec":
            try {
                root.output = decodeURIComponent(input);
            } catch (e) {
                root.error = "URL inválida";
            }
            return;
        case "epoch":
            root._epoch(input.trim());
            return;
        case "b64enc":
            root._sh("printf %s \"$1\" | base64 -w0", input);
            return;
        case "b64dec":
            root._sh("printf %s \"$1\" | base64 -d", input);
            return;
        case "jsonpretty":
            root._sh("printf %s \"$1\" | jq .", input);
            return;
        case "jsonmin":
            root._sh("printf %s \"$1\" | jq -c .", input);
            return;
        case "sha256":
            root._sh("printf %s \"$1\" | sha256sum | cut -d' ' -f1", input);
            return;
        case "md5":
            root._sh("printf %s \"$1\" | md5sum | cut -d' ' -f1", input);
            return;
        case "uuid":
            root._sh("cat /proc/sys/kernel/random/uuid", input);
            return;
        }
    }

    function _epoch(s) {
        if (s.length === 0) {
            root.output = "";
            return;
        }
        if (/^\d+$/.test(s)) {
            // numeric → treat as epoch (seconds unless it looks like ms)
            var n = parseInt(s, 10);
            var ms = s.length > 12 ? n : n * 1000;
            root.output = new Date(ms).toUTCString();
        } else {
            var t = Date.parse(s);
            if (isNaN(t))
                root.error = "Fecha inválida";
            else
                root.output = String(Math.floor(t / 1000));
        }
    }

    function _sh(cmd, input) {
        proc.command = ["bash", "-c", cmd, "--", input];
        proc.running = true;
    }

    Process {
        id: proc
        running: false
        stdout: StdioCollector { id: outC; waitForEnd: true }
        stderr: StdioCollector { id: errC; waitForEnd: true }
        onExited: code => {
            if (code === 0) {
                root.output = outC.text.replace(/\n+$/, "");
                root.error = "";
            } else {
                root.error = errC.text.trim() || ("Error (" + code + ")");
            }
        }
    }
}
