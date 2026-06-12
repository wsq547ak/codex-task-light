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

struct DisplayPreferences: Codable {
    let display_mode: String
    let always_on_top: Bool
}

enum DisplayMode: String, CaseIterable {
    case menuBar
    case floating

    var title: String {
        switch self {
        case .menuBar:
            return "状态栏"
        case .floating:
            return "悬浮窗"
        }
    }
}

final class FloatingIndicatorView: NSView {
    var indicatorColor: NSColor = .systemRed {
        didSet {
            needsDisplay = true
        }
    }

    var clickHandler: (() -> Void)?

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        let backgroundRect = bounds.insetBy(dx: 1, dy: 1)
        NSColor(calibratedWhite: 0.08, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: backgroundRect, xRadius: 12, yRadius: 12).fill()

        let dotSize: CGFloat = 18
        let dotRect = NSRect(
            x: (bounds.width - dotSize) / 2,
            y: (bounds.height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        )
        indicatorColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    override func mouseDown(with event: NSEvent) {
        clickHandler?()
    }
}

final class CodexTrafficLightApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private let titleItem = NSMenuItem(title: "Codex 状态灯", action: nil, keyEquivalent: "")
    private let detailItem = NSMenuItem(title: "等待状态中", action: nil, keyEquivalent: "")
    private let sessionItem = NSMenuItem(title: "会话：-", action: nil, keyEquivalent: "")
    private let modeHeaderItem = NSMenuItem(title: "显示方式", action: nil, keyEquivalent: "")
    private let menuBarModeItem = NSMenuItem(title: DisplayMode.menuBar.title, action: #selector(selectMenuBarMode), keyEquivalent: "")
    private let floatingModeItem = NSMenuItem(title: DisplayMode.floating.title, action: #selector(selectFloatingMode), keyEquivalent: "")
    private let alwaysOnTopItem = NSMenuItem(title: "窗口置顶", action: #selector(toggleAlwaysOnTop), keyEquivalent: "")
    private var refreshTimer: Timer?
    private var missingCodexChecks = 0
    private var cachedLifecycleEvent: CodexLifecycleEvent?
    private var lastLifecycleRefresh = Date.distantPast
    private var currentDisplayMode: DisplayMode = .menuBar
    private var isAlwaysOnTop = true
    private var floatingPanel: NSPanel?
    private var floatingIndicatorView: FloatingIndicatorView?

    private let pluginData: URL = {
        if let path = ProcessInfo.processInfo.environment["PLUGIN_DATA"] {
            return URL(fileURLWithPath: path)
        }

        return Bundle.main.bundleURL.deletingLastPathComponent()
    }()

    private var preferencesURL: URL {
        pluginData.appendingPathComponent("preferences.json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        currentDisplayMode = loadDisplayMode()
        applyDisplayMode()
        refreshState()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.refreshState()
        }
    }

    private func setupMenu() {
        titleItem.isEnabled = false
        detailItem.isEnabled = false
        sessionItem.isEnabled = false
        modeHeaderItem.isEnabled = false

        menuBarModeItem.target = self
        floatingModeItem.target = self
        alwaysOnTopItem.target = self

        menu.addItem(titleItem)
        menu.addItem(detailItem)
        menu.addItem(sessionItem)
        menu.addItem(.separator())
        menu.addItem(modeHeaderItem)
        menu.addItem(menuBarModeItem)
        menu.addItem(floatingModeItem)
        menu.addItem(alwaysOnTopItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "退出",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
    }

    @objc private func selectMenuBarMode() {
        setDisplayMode(.menuBar)
    }

    @objc private func selectFloatingMode() {
        setDisplayMode(.floating)
    }

    @objc private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        savePreferences()
        applyDisplayMode()
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
        sessionItem.title = "会话：\(state.session_id ?? "-")"
        updateIndicators(color: resolvedState.indicatorColor)
    }

    private func resolveIndicatorState(from state: TrafficLightState) -> ResolvedIndicatorState {
        let stateDate = parseDate(state.updated_at)

        if state.color != "red" && state.color != "blue",
           let lifecycleEvent = latestLifecycleEvent(),
           let stateDate,
           lifecycleEvent.timestamp > stateDate {
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
            return ResolvedIndicatorState(label: state.label, detail: state.detail, indicatorColor: .systemGreen)
        case "blue":
            return ResolvedIndicatorState(label: state.label, detail: state.detail, indicatorColor: .systemBlue)
        case "yellow":
            return ResolvedIndicatorState(label: state.label, detail: state.detail, indicatorColor: .systemYellow)
        default:
            return ResolvedIndicatorState(label: state.label, detail: state.detail, indicatorColor: .systemRed)
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
            guard let year = components.year, let month = components.month, let day = components.day else {
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
                        (line.contains("\"type\":\"task_started\"")
                            || line.contains("\"type\":\"task_complete\"")
                            || line.contains("\"type\":\"turn_aborted\"")),
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

    private func updateIndicators(color: NSColor) {
        updateStatusItem(color: color)
        floatingIndicatorView?.indicatorColor = color
    }

    private func updateStatusItem(color: NSColor) {
        guard let button = statusItem?.button else {
            return
        }

        button.title = ""
        button.image = makeDotImage(color: color)
        button.imagePosition = .imageOnly
        button.toolTip = "CX Task Light"
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

    private func setDisplayMode(_ mode: DisplayMode) {
        guard currentDisplayMode != mode else {
            return
        }

        currentDisplayMode = mode
        savePreferences()
        applyDisplayMode()
    }

    private func applyDisplayMode() {
        updateDisplayModeMenuChecks()

        switch currentDisplayMode {
        case .menuBar:
            destroyFloatingPanel()
            ensureStatusItem()
        case .floating:
            removeStatusItem()
            ensureFloatingPanel(level: isAlwaysOnTop ? .statusBar : .normal)
        }
    }

    private func updateDisplayModeMenuChecks() {
        menuBarModeItem.state = currentDisplayMode == .menuBar ? .on : .off
        floatingModeItem.state = currentDisplayMode == .floating ? .on : .off
        alwaysOnTopItem.state = isAlwaysOnTop ? .on : .off
        alwaysOnTopItem.isEnabled = currentDisplayMode == .floating
    }

    private func ensureStatusItem() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusBar.system.thickness)
            item.menu = menu
            statusItem = item
        }
    }

    private func removeStatusItem() {
        guard let item = statusItem else {
            return
        }

        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    private func ensureFloatingPanel(level: NSWindow.Level) {
        let panel: NSPanel
        let indicatorView: FloatingIndicatorView

        if let existingPanel = floatingPanel, let existingView = floatingIndicatorView {
            panel = existingPanel
            indicatorView = existingView
        } else {
            panel = NSPanel(
                contentRect: NSRect(x: 120, y: 120, width: 46, height: 46),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true

            indicatorView = FloatingIndicatorView(frame: NSRect(x: 0, y: 0, width: 46, height: 46))
            indicatorView.clickHandler = { [weak self, weak indicatorView] in
                guard let self, let indicatorView else {
                    return
                }
                let location = NSPoint(x: indicatorView.bounds.midX, y: indicatorView.bounds.midY)
                self.menu.popUp(positioning: nil, at: location, in: indicatorView)
            }
            panel.contentView = indicatorView

            floatingPanel = panel
            floatingIndicatorView = indicatorView
        }

        panel.level = level
        panel.orderFrontRegardless()
        panel.collectionBehavior = level == .statusBar
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]
        indicatorView.toolTip = "CX Task Light"
    }

    private func destroyFloatingPanel() {
        floatingPanel?.close()
        floatingPanel = nil
        floatingIndicatorView = nil
    }

    private func loadDisplayMode() -> DisplayMode {
        guard
            let data = try? Data(contentsOf: preferencesURL),
            let preferences = try? JSONDecoder().decode(DisplayPreferences.self, from: data),
            let mode = DisplayMode(rawValue: preferences.display_mode)
        else {
            isAlwaysOnTop = true
            return .menuBar
        }

        isAlwaysOnTop = preferences.always_on_top
        return mode
    }

    private func savePreferences() {
        let preferences = DisplayPreferences(
            display_mode: currentDisplayMode.rawValue,
            always_on_top: isAlwaysOnTop
        )
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }

        try? data.write(to: preferencesURL, options: [.atomic])
    }

    private func isCodexRunning() -> Bool {
        commandSucceeded("/usr/bin/pgrep", arguments: ["-x", "Codex"])
            || commandSucceeded("/usr/bin/pgrep", arguments: ["-x", "codex"])
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
