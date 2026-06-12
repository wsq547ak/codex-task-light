import Cocoa

struct TrafficLightState: Decodable {
    let session_id: String?
    let event: String?
    let color: String
    let label: String
    let detail: String
    let updated_at: String
}

struct ResolvedIndicatorState {
    let label: String
    let detail: String
    let menuSymbol: String
}

final class CodexTrafficLightApp: NSObject, NSApplicationDelegate {
    private let staleInProgressThreshold: TimeInterval = 20
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let titleItem = NSMenuItem(title: "Codex Traffic Light", action: nil, keyEquivalent: "")
    private let detailItem = NSMenuItem(title: "Waiting for state", action: nil, keyEquivalent: "")
    private let sessionItem = NSMenuItem(title: "Session: -", action: nil, keyEquivalent: "")
    private var refreshTimer: Timer?
    private var missingCodexChecks = 0

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
        statusItem.button?.title = "CX ⏺"
        statusItem.button?.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        statusItem.button?.toolTip = "Codex Traffic Light"
        updateButton(symbol: "🔴")
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
        updateButton(symbol: resolvedState.menuSymbol)
    }

    private func resolveIndicatorState(from state: TrafficLightState) -> ResolvedIndicatorState {
        if state.color == "yellow", isStale(updatedAt: state.updated_at) {
            return ResolvedIndicatorState(
                label: "Idle",
                detail: "No recent Codex activity",
                menuSymbol: "🟢"
            )
        }

        switch state.color {
        case "green":
            return ResolvedIndicatorState(
                label: state.label,
                detail: state.detail,
                menuSymbol: "🟢"
            )
        case "blue":
            return ResolvedIndicatorState(
                label: state.label,
                detail: state.detail,
                menuSymbol: "🔵"
            )
        case "yellow":
            return ResolvedIndicatorState(
                label: state.label,
                detail: state.detail,
                menuSymbol: "🟡"
            )
        default:
            return ResolvedIndicatorState(
                label: state.label,
                detail: state.detail,
                menuSymbol: "🔴"
            )
        }
    }

    private func isStale(updatedAt: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        guard
            let updatedDate = formatter.date(from: updatedAt) ?? fallbackFormatter.date(from: updatedAt)
        else {
            return false
        }

        return Date().timeIntervalSince(updatedDate) > staleInProgressThreshold
    }

    private func updateButton(symbol: String) {
        guard let button = statusItem.button else {
            return
        }
        button.title = "CX \(symbol)"
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
