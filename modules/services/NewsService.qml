pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    // Exposed Feeds
    property var techNews: []
    property var cveFeed: []
    property var redditFeed: []

    // Loading States
    property bool isLoadingNews: false
    property bool isLoadingCve: false
    property bool isLoadingReddit: false

    // Failure States
    property bool newsFailed: false
    property bool cveFailed: false
    property bool redditFailed: false

    readonly property string pythonScript: Quickshell.shellDir + "/scripts/news_fetcher.py"

    // Timers for periodic background updates
    property Timer refreshTimer: Timer {
        interval: 900000 // 15 minutes
        running: true
        repeat: true
        onTriggered: {
            root.updateNews()
            root.updateCve()
            root.updateReddit()
        }
    }

    // Initialize data on startup
    Component.onCompleted: {
        root.updateNews()
        root.updateCve()
        root.updateReddit()
    }

    // Refresh functions
    function updateNews() {
        if (newsProcess.running) {
            newsProcess.running = false
        }
        root.isLoadingNews = true
        root.newsFailed = false
        newsProcess.running = true
    }

    function updateCve() {
        if (cveProcess.running) {
            cveProcess.running = false
        }
        root.isLoadingCve = true
        root.cveFailed = false
        cveProcess.running = true
    }

    function updateReddit() {
        if (redditProcess.running) {
            redditProcess.running = false
        }
        root.isLoadingReddit = true
        root.redditFailed = false
        redditProcess.running = true
    }

    // Processes
    property Process newsProcess: Process {
        running: false
        command: ["python3", root.pythonScript, "news"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.isLoadingNews = false
                var raw = text.trim()
                if (raw.length > 0) {
                    try {
                        var parsed = JSON.parse(raw)
                        if (parsed.error) {
                            console.warn("NewsService (news error):", parsed.error)
                            root.newsFailed = true
                        } else {
                            root.techNews = parsed
                        }
                    } catch (e) {
                        console.error("NewsService: Failed to parse news JSON", e)
                        root.newsFailed = true
                    }
                } else {
                    root.newsFailed = true
                }
            }
        }
    }

    property Process cveProcess: Process {
        running: false
        command: ["python3", root.pythonScript, "cve"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.isLoadingCve = false
                var raw = text.trim()
                if (raw.length > 0) {
                    try {
                        var parsed = JSON.parse(raw)
                        if (parsed.error) {
                            console.warn("NewsService (cve error):", parsed.error)
                            root.cveFailed = true
                        } else {
                            root.cveFeed = parsed
                        }
                    } catch (e) {
                        console.error("NewsService: Failed to parse cve JSON", e)
                        root.cveFailed = true
                    }
                } else {
                    root.cveFailed = true
                }
            }
        }
    }

    property Process redditProcess: Process {
        running: false
        command: ["python3", root.pythonScript, "reddit"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.isLoadingReddit = false
                var raw = text.trim()
                if (raw.length > 0) {
                    try {
                        var parsed = JSON.parse(raw)
                        if (parsed.error) {
                            console.warn("NewsService (reddit error):", parsed.error)
                            root.redditFailed = true
                        } else {
                            root.redditFeed = parsed
                        }
                    } catch (e) {
                        console.error("NewsService: Failed to parse reddit JSON", e)
                        root.redditFailed = true
                    }
                } else {
                    root.redditFailed = true
                }
            }
        }
    }
}
