import Cocoa

struct TrafficLightState: Decodable {
    let session_id: String?
    let event: String?
    let color: String
    let label: String
    let detail: String
    let updated_at: String
}

struct CodexLifecycleEvent {
    let timestamp: Date
    let type: String
}

struct ResolvedIndicatorState {
    let label: String
    let detail: String
    let indicatorColor: NSColor
}

final class CodexTrafficLightApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusBar.system.thickness)
    private let menu = NSMenu()
    private let titleItem = NSMenuItem(title: "Codex Traffic Light", action: nil, keyEquivalent: "")
    private let detailItem = NSMenuItem(title: "Waiting for state", action: nil, keyEquivalent: "")
    private let sessionItem = NSMenuItem(title: "Session: -", action: nil, keyEquivalent: "")
    private var refreshTimer: Timer?
    private var missingCodexChecks = 0
    private var cachedLifecycleEvent: CodexLifecycleEvent?
    private var lastLifecycleRefresh = Date.distantPast

    private let pluginData: URL = {
        if let path = ProcessInfo.processInfo.environment["PLUGIN_DATA"] {
            return URL(fileURLWithPath: path)
        }

        // When launched from the built app bundle, keep state next to the app.
        return Bundle.main.bundleURL.deletingLastPathComponent()
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        refreshState()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.refreshState()
        }
    }

    private func setupMenu() {
        titleItem.isEnabled = false
        detailItem.isEnabled = false
        sessionItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(detailItem)
        menu.addItem(sessionItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )

        statusItem.menu = menu
        statusItem.button?.toolTip = "CX Task Light"
        updateButton(color: .systemRed)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func refreshState() {
        if !isCodexRunning() {
            missingCodexChecks += 1
            if missingCodexChecks >= 15 {
                NSApp.terminate(nil)
                return
            }
        } else {
            missingCodexChecks = 0
        }

        let stateURL = pluginData.appendingPathComponent("state.json")
        guard
            let data = try? Data(contentsOf: stateURL),
            let state = try? JSONDecoder().decode(TrafficLightState.self, from: data)
        else {
            return
        }

        let resolvedState = resolveIndicatorState(from: state)
        titleItem.title = resolvedState.label
        detailItem.title = resolvedState.detail
        sessionItem.title = "Session: \(state.session_id ?? "-")"
        updateButton(color: resolvedState.indicatorColor)
    }

    private func resolveIndicatorState(from state: TrafficLightState) -> ResolvedIndicatorState {
        if state.color != "red" && state.color != "blue",
           let lifecycleEvent = latestLifecycleEvent() {
            switch lifecycleEvent.type {
            case "task_started":
                return ResolvedIndicatorState(
                    label: "Task in progress",
                    detail: "Codex is still running a task",
                    indicatorColor: .systemYellow
                )
            case "task_complete":
                return ResolvedIndicatorState(
                    label: "Task complete",
                    detail: "Codex finished the current turn",
                    indicatorColor: .systemGreen
                )
            case "turn_aborted":
                return ResolvedIndicatorState(
                    label: "Stopped",
                    detail: "Codex task was stopped",
                    indicatorColor: .systemGreen
                )
            default:
                break
            }
        }

        switch state.color {
        case "green":
            return ResolvedIndicatorState(
                label: state.label,
                detail: state.detail,
                indicatorColor: .systemGreen
            )
        case "blue":
            return ResolvedIndicatorState(
                label: state.label,
                detail: state.detail,
                indicatorColor: .systemBlue
            )
        case "yellow":
            return ResolvedIndicatorState(
                label: state.label,
                detail: state.detail,
                indicatorColor: .systemYellow
            )
        default:
            return ResolvedIndicatorState(
                label: state.label,
                detail: state.detail,
                indicatorColor: .systemRed
            )
        }
    }

    private func latestLifecycleEvent() -> CodexLifecycleEvent? {
        if Date().timeIntervalSince(lastLifecycleRefresh) < 2 {
            return cachedLifecycleEvent
        }

        lastLifecycleRefresh = Date()

        let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)

        let calendar = Calendar.current
        let candidateDates = [Date(), calendar.date(byAdding: .day, value: -1, to: Date())].compactMap { $0 }

        var latest: CodexLifecycleEvent?

        for date in candidateDates {
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard
                let year = components.year,
                let month = components.month,
                let day = components.day
            else {
                continue
            }

            let folder = sessionsRoot
                .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", day), isDirectory: true)

            guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
                continue
            }

            for fileURL in files where fileURL.pathExtension == "jsonl" {
                guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                    continue
                }

                for line in contents.split(separator: "\n") {
                    guard
                        line.contains("\"type\":\"event_msg\""),
                        (line.contains("\"type\":\"task_started\"") ||
                            line.contains("\"type\":\"task_complete\"") ||
                            line.contains("\"type\":\"turn_aborted\"")),
                        let data = line.data(using: .utf8),
                        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let timestampText = object["timestamp"] as? String,
                        let payload = object["payload"] as? [String: Any],
                        let type = payload["type"] as? String,
                        let timestamp = parseDate(timestampText)
                    else {
                        continue
                    }

                    if latest == nil || timestamp > latest!.timestamp {
                        latest = CodexLifecycleEvent(timestamp: timestamp, type: type)
                    }
                }
            }
        }

        cachedLifecycleEvent = latest
        return latest
    }

    private func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        return formatter.date(from: text) ?? fallbackFormatter.date(from: text)
    }

    private func updateButton(color: NSColor) {
        guard let button = statusItem.button else {
            return
        }
        button.title = ""
        button.image = makeDotImage(color: color)
        button.imagePosition = .imageOnly
    }

    private func makeDotImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func isCodexRunning() -> Bool {
        return commandSucceeded("/usr/bin/pgrep", arguments: ["-x", "Codex"]) ||
            commandSucceeded("/usr/bin/pgrep", arguments: ["-x", "codex"])
    }

    private func commandSucceeded(_ launchPath: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

@main
enum CodexTrafficLightMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = CodexTrafficLightApp()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
