pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Translator backed by Groq (OpenAI-compatible) + Llama 3.3 70B.
 * Reuses the Groq API key stored in [[KeyStore]] (provider "groq").
 * A strong system prompt asks for idiomatic, register/variant-aware output
 * (not a literal/generic machine translation), and ONLY the translation.
 */
Singleton {
    id: root

    property string model: "llama-3.3-70b-versatile"
    readonly property string endpoint: "https://api.groq.com/openai/v1/chat/completions"
    readonly property string tmpDir: "/tmp/ambxst-translator"

    property string output: ""
    property bool loading: false
    property string error: ""

    readonly property bool hasKey: KeyStore.hasKey("groq")

    // Target languages — label drives the prompt, so regional variety matters.
    readonly property var languages: [
        { label: "English (US)" },
        { label: "English (UK)" },
        { label: "Spanish (Rioplatense, Argentina)" },
        { label: "Spanish (Spain)" },
        { label: "Spanish (Latin America, neutral)" },
        { label: "Portuguese (Brazil)" },
        { label: "French" },
        { label: "German" },
        { label: "Italian" },
        { label: "Japanese" }
    ]
    readonly property int defaultLangIndex: 0

    signal finished()

    function systemPrompt(targetLabel) {
        return "You are an expert literary translator. Translate the user's text into " + targetLabel + ". "
            + "Produce a natural, idiomatic translation exactly as a native speaker of that specific regional variety would phrase it — "
            + "match the accent/dialect, register (formal vs casual), tone, slang and punctuation of the target. "
            + "Never translate word-for-word; convey meaning and intent. Preserve line breaks and basic formatting. "
            + "If the input is already in the target language, refine it to sound native. "
            + "Output ONLY the translation: no quotes, no notes, no explanations, no language labels, no preamble.";
    }

    function translate(text, targetLabel) {
        const t = (text || "").trim();
        root.error = "";
        if (t.length === 0) {
            root.output = "";
            return;
        }
        if (!root.hasKey) {
            root.error = "No hay API key de Groq. Agregala en Ajustes → AI (provider \"groq\").";
            return;
        }
        root.loading = true;
        root.output = "";
        root._pendingBody = JSON.stringify({
            model: root.model,
            messages: [
                { role: "system", content: root.systemPrompt(targetLabel) },
                { role: "user", content: t }
            ],
            temperature: 0.3,
            max_completion_tokens: 1024,
            stream: false
        });
        mkdirProc.running = true;
    }

    property string _pendingBody: ""

    Process {
        id: mkdirProc
        command: ["/usr/bin/mkdir", "-p", root.tmpDir]
        running: false
        onExited: code => {
            if (code === 0) {
                root._writeBody();
            } else {
                root.error = "No se pudo crear el directorio temporal";
                root.loading = false;
            }
        }
    }

    FileView {
        id: bodyFile
        printErrors: false
    }

    function _writeBody() {
        bodyFile.path = root.tmpDir + "/body.json";
        bodyFile.setText(root._pendingBody);
        Qt.callLater(root._runCurl);
    }

    function _runCurl() {
        const key = KeyStore.getKey("groq");
        const cmd = "curl -s -X POST \"" + root.endpoint + "\""
            + " -H \"Content-Type: application/json\""
            + " -H \"Authorization: Bearer " + key + "\""
            + " -d @" + root.tmpDir + "/body.json";
        curlProc.command = ["/usr/bin/bash", "-c", cmd];
        curlProc.running = true;
    }

    Process {
        id: curlProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._parse(text)
        }
        onExited: code => {
            if (code !== 0 && root.loading) {
                root.loading = false;
                root.error = "Falló la petición (curl " + code + ")";
            }
        }
    }

    function _parse(resp) {
        root.loading = false;
        try {
            const j = JSON.parse(resp);
            if (j.error) {
                root.error = j.error.message || "Error de la API";
                return;
            }
            if (j.choices && j.choices.length > 0) {
                root.output = (j.choices[0].message.content || "").trim();
                root.finished();
            } else {
                root.error = "Respuesta vacía";
            }
        } catch (e) {
            root.error = "No se pudo parsear la respuesta";
        }
    }

    function clear() {
        root.output = "";
        root.error = "";
        root.loading = false;
    }
}
