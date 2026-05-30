pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Local password generator. Entropy comes from `openssl rand` (CSPRNG),
 * mapped to the chosen character set via rejection sampling for a uniform
 * distribution. Nothing is stored — the user keeps secrets in their own
 * password manager; this only generates + the UI copies.
 */
Singleton {
    id: root

    property int length: 20
    property bool useUpper: true
    property bool useLower: true
    property bool useDigits: true
    property bool useSymbols: true
    property bool avoidAmbiguous: true

    property string password: ""

    readonly property string _upper: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    readonly property string _lower: "abcdefghijklmnopqrstuvwxyz"
    readonly property string _digits: "0123456789"
    readonly property string _symbols: "!@#$%^&*()-_=+[]{};:,.?"
    readonly property string _ambiguous: "Il1O0o"

    function _filter(s) {
        if (!root.avoidAmbiguous)
            return s;
        var out = "";
        for (var i = 0; i < s.length; i++)
            if (root._ambiguous.indexOf(s[i]) === -1)
                out += s[i];
        return out;
    }

    function _classes() {
        var c = [];
        if (root.useUpper) c.push(root._filter(root._upper));
        if (root.useLower) c.push(root._filter(root._lower));
        if (root.useDigits) c.push(root._filter(root._digits));
        if (root.useSymbols) c.push(root._filter(root._symbols));
        return c.filter(s => s.length > 0);
    }

    // Live charset size + entropy estimate (updates with the toggles).
    readonly property int charsetSize: {
        var n = 0;
        var cs = root._classes();
        for (var i = 0; i < cs.length; i++)
            n += cs[i].length;
        return n;
    }
    readonly property real entropyBits: root.charsetSize > 1 ? root.length * (Math.log(root.charsetSize) / Math.log(2)) : 0
    // 0 weak · 1 fair · 2 strong · 3 very strong
    readonly property int strengthLevel: root.entropyBits < 40 ? 0 : (root.entropyBits < 70 ? 1 : (root.entropyBits < 100 ? 2 : 3))
    readonly property string strengthLabel: ["Weak", "Fair", "Strong", "Very Strong"][root.strengthLevel]

    signal generated()

    function generate() {
        // Plenty of bytes for rejection sampling + class coverage.
        var bytes = Math.max(256, root.length * 4);
        entropyProc.command = ["openssl", "rand", "-hex", String(bytes)];
        entropyProc.running = true;
    }

    Process {
        id: entropyProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._build(text.trim())
        }
        onExited: code => {
            if (code !== 0)
                console.warn("PasswordService: openssl rand failed", code);
        }
    }

    function _build(hex) {
        var classes = root._classes();
        if (classes.length === 0) {
            root.password = "";
            return;
        }
        var charset = classes.join("");

        var bytes = [];
        for (var i = 0; i + 1 < hex.length; i += 2)
            bytes.push(parseInt(hex.substr(i, 2), 16));

        var bi = 0;
        function nextIdx(mod) {
            var max = Math.floor(256 / mod) * mod;  // rejection bound for uniformity
            while (bi < bytes.length) {
                var b = bytes[bi++];
                if (b < max)
                    return b % mod;
            }
            return Math.floor(Math.random() * mod);  // fallback if pool exhausted
        }

        var out = [];
        for (var k = 0; k < root.length; k++)
            out.push(charset[nextIdx(charset.length)]);

        // Guarantee at least one char from each enabled class.
        if (root.length >= classes.length) {
            for (var ci = 0; ci < classes.length; ci++) {
                var cls = classes[ci];
                var present = false;
                for (var p = 0; p < out.length; p++) {
                    if (cls.indexOf(out[p]) !== -1) { present = true; break; }
                }
                if (!present)
                    out[nextIdx(out.length)] = cls[nextIdx(cls.length)];
            }
        }

        root.password = out.join("");
        root.generated();
    }
}
