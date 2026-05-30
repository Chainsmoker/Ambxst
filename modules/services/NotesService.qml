pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Quick notes — a local "pastebin" with per-note expiry.
 * Notes persist to a JSON file and are pruned once their TTL elapses.
 * Each note: { id, text, createdAt (ms), expiresAt (ms; 0 = never) }.
 */
Singleton {
    id: root

    property var notes: []
    property bool initialized: false

    readonly property string notesPath: Quickshell.dataPath("notes.json")

    // Expiry presets (ms). 0 = never. Default = 24 Hours.
    readonly property var ttlPresets: [
        { label: "1 Hour", ms: 3600000 },
        { label: "24 Hours", ms: 86400000 },
        { label: "7 Days", ms: 604800000 },
        { label: "30 Days", ms: 2592000000 },
        { label: "Never", ms: 0 }
    ]
    readonly property int defaultTtlIndex: 1  // 24 Hours

    function _now() {
        return Date.now();
    }

    // Read via Process (proven pattern in StateService/DesktopService).
    property Process readProcess: Process {
        command: ["cat", root.notesPath]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._load(text)
        }
        onExited: code => {
            if (code !== 0) {
                // File doesn't exist yet
                root.notes = [];
                root.initialized = true;
            }
        }
    }

    // Write via FileView.setText (no shell escaping of note bodies).
    FileView {
        id: notesFile
        path: root.notesPath
        printErrors: false
    }

    function load() {
        readProcess.running = true;
    }

    function _load(content) {
        try {
            const arr = content && content.trim() ? JSON.parse(content) : [];
            root.notes = Array.isArray(arr) ? arr : [];
        } catch (e) {
            console.warn("NotesService: failed to parse notes.json:", e);
            root.notes = [];
        }
        root.initialized = true;
        root.prune();
    }

    function _save() {
        notesFile.setText(JSON.stringify(root.notes));
    }

    function add(text, ttlMs) {
        const t = (text || "").trim();
        if (t.length === 0)
            return;
        const now = root._now();
        const note = {
            id: String(now) + "_" + Math.floor(Math.random() * 100000),
            text: t,
            createdAt: now,
            expiresAt: ttlMs > 0 ? now + ttlMs : 0
        };
        root.notes = [note].concat(root.notes);
        root._save();
    }

    function remove(id) {
        root.notes = root.notes.filter(n => n.id !== id);
        root._save();
    }

    // Edita el texto de una nota (mantiene su expiración).
    function update(id, text) {
        const t = (text || "").trim();
        if (t.length === 0)
            return;
        root.notes = root.notes.map(function (n) {
            return n.id === id ? { id: n.id, text: t, createdAt: n.createdAt, expiresAt: n.expiresAt } : n;
        });
        root._save();
    }

    function clear() {
        root.notes = [];
        root._save();
    }

    // Drop expired notes. Returns nothing; mutates + persists if anything changed.
    function prune() {
        const now = root._now();
        const kept = root.notes.filter(n => n.expiresAt === 0 || n.expiresAt > now);
        if (kept.length !== root.notes.length) {
            root.notes = kept;
            root._save();
        }
    }

    // Milliseconds left until expiry, or -1 if the note never expires.
    function timeLeft(note) {
        if (!note || note.expiresAt === 0)
            return -1;
        return Math.max(0, note.expiresAt - root._now());
    }

    // Human-readable remaining time for a note.
    function timeLeftLabel(note) {
        const ms = root.timeLeft(note);
        if (ms < 0)
            return "Never Expires";
        if (ms === 0)
            return "Expiring...";
        const mins = Math.floor(ms / 60000);
        if (mins < 60)
            return "Expires In " + Math.max(1, mins) + "m";
        const hours = Math.floor(mins / 60);
        if (hours < 24)
            return "Expires In " + hours + "h";
        const days = Math.floor(hours / 24);
        return "Expires In " + days + "d";
    }

    // Periodic pruning so stale notes vanish even while the dock stays open.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.prune()
    }

    property bool _initialized: false
    function initialize() {
        if (_initialized)
            return;
        _initialized = true;
        root.load();
    }
}
