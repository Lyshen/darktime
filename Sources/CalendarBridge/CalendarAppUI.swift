import AppKit
import EventKit
import Foundation

@MainActor
private enum CalendarAppStorage {
    static var delegate: CalendarAppDelegate?
}

@MainActor
func launchCalendarAppUI() {
    let app = NSApplication.shared
    let delegate = CalendarAppDelegate()
    CalendarAppStorage.delegate = delegate

    app.setActivationPolicy(.regular)
    app.delegate = delegate
    configureApplicationMenu()
    app.activate(ignoringOtherApps: true)
    app.run()
}

@MainActor
private func configureApplicationMenu() {
    let menu = NSMenu()
    let appMenuItem = NSMenuItem()
    let appMenu = NSMenu()

    appMenu.addItem(
        withTitle: "Quit Darktime",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
    appMenuItem.submenu = appMenu
    menu.addItem(appMenuItem)

    NSApplication.shared.mainMenu = menu
}

@MainActor
private final class CalendarAppDelegate: NSObject, NSApplicationDelegate {
    private let eventStore = EKEventStore()

    private var window: NSWindow?
    private let accessStatusLabel = NSTextField(labelWithString: "Checking...")
    private let accessDetailLabel = NSTextField(labelWithString: "")
    private let preferredCalendarLabel = NSTextField(labelWithString: "")
    private let calendarsTextView = NSTextView()
    private let serviceStatusLabel = NSTextField(labelWithString: "")
    private let agentsTextView = NSTextView()
    private let activityTextView = NSTextView()
    private let appPathField = NSTextField(labelWithString: "")
    private let dbPathField = NSTextField(labelWithString: "")
    private let mcpHintLabel = NSTextField(labelWithString: "")
    private let requestAccessButton = NSButton(title: "Grant Calendar Access", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let copyMCPHintButton = NSButton(title: "Copy MCP Command", target: nil, action: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        refreshState()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Darktime"
        window.minSize = NSSize(width: 760, height: 640)
        window.center()

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 14
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        rootStack.addArrangedSubview(makeHeader())
        rootStack.addArrangedSubview(makeStatusSection())
        rootStack.addArrangedSubview(makeSourcesSection())
        rootStack.addArrangedSubview(makeAgentSection())
        rootStack.addArrangedSubview(makeActivitySection())

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    private func makeHeader() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = label("Darktime", size: 24, weight: .semibold)
        let subtitle = label(
            "Your local time layer for Codex, Claude Code, and other agents.",
            size: 13,
            color: .secondaryLabelColor
        )

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        return stack
    }

    private func makeStatusSection() -> NSView {
        let box = makeSectionBox()
        let stack = sectionStack(in: box)

        let titleRow = horizontalStack(spacing: 10)
        let title = label("Status", size: 15, weight: .semibold)
        accessStatusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(makeSpacer())
        titleRow.addArrangedSubview(accessStatusLabel)

        serviceStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        serviceStatusLabel.textColor = .secondaryLabelColor
        serviceStatusLabel.lineBreakMode = .byWordWrapping
        serviceStatusLabel.maximumNumberOfLines = 2

        accessDetailLabel.font = NSFont.systemFont(ofSize: 12)
        accessDetailLabel.textColor = .secondaryLabelColor
        accessDetailLabel.lineBreakMode = .byWordWrapping
        accessDetailLabel.maximumNumberOfLines = 2

        requestAccessButton.title = "Connect Calendar"
        requestAccessButton.target = self
        requestAccessButton.action = #selector(requestAccess)
        requestAccessButton.bezelStyle = .rounded

        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        refreshButton.bezelStyle = .rounded

        let buttonRow = horizontalStack(spacing: 10)
        buttonRow.addArrangedSubview(requestAccessButton)
        buttonRow.addArrangedSubview(refreshButton)
        buttonRow.addArrangedSubview(makeSpacer())

        stack.addArrangedSubview(titleRow)
        stack.addArrangedSubview(serviceStatusLabel)
        stack.addArrangedSubview(accessDetailLabel)
        stack.addArrangedSubview(buttonRow)
        return box
    }

    private func makeSourcesSection() -> NSView {
        let box = makeSectionBox()
        let stack = sectionStack(in: box)

        let title = label("Sources", size: 15, weight: .semibold)

        preferredCalendarLabel.font = NSFont.systemFont(ofSize: 12)
        preferredCalendarLabel.textColor = .secondaryLabelColor
        preferredCalendarLabel.lineBreakMode = .byWordWrapping
        preferredCalendarLabel.maximumNumberOfLines = 2

        configureTextView(calendarsTextView)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = calendarsTextView
        scrollView.heightAnchor.constraint(equalToConstant: 170).isActive = true

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(preferredCalendarLabel)
        stack.addArrangedSubview(scrollView)
        return box
    }

    private func makeAgentSection() -> NSView {
        let box = makeSectionBox()
        let stack = sectionStack(in: box)

        let title = label("Agent Access", size: 15, weight: .semibold)
        mcpHintLabel.stringValue = """
        MCP command: \(mcpCommand())
        The server will find this app in dist/mac, ~/Applications, or /Applications.
        """
        mcpHintLabel.font = NSFont.systemFont(ofSize: 12)
        mcpHintLabel.textColor = .secondaryLabelColor
        mcpHintLabel.lineBreakMode = .byWordWrapping
        mcpHintLabel.maximumNumberOfLines = 3

        appPathField.stringValue = "App: \(Bundle.main.bundleURL.path)"
        appPathField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        appPathField.textColor = .secondaryLabelColor
        appPathField.lineBreakMode = .byTruncatingMiddle

        dbPathField.stringValue = "Store: \(DarktimeStorage.databasePath())"
        dbPathField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        dbPathField.textColor = .secondaryLabelColor
        dbPathField.lineBreakMode = .byTruncatingMiddle

        configureTextView(agentsTextView)
        let agentsScrollView = NSScrollView()
        agentsScrollView.translatesAutoresizingMaskIntoConstraints = false
        agentsScrollView.hasVerticalScroller = true
        agentsScrollView.borderType = .bezelBorder
        agentsScrollView.documentView = agentsTextView
        agentsScrollView.heightAnchor.constraint(equalToConstant: 118).isActive = true

        copyMCPHintButton.target = self
        copyMCPHintButton.action = #selector(copyMCPCommand)
        copyMCPHintButton.bezelStyle = .rounded

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(mcpHintLabel)
        stack.addArrangedSubview(appPathField)
        stack.addArrangedSubview(dbPathField)
        stack.addArrangedSubview(agentsScrollView)
        stack.addArrangedSubview(copyMCPHintButton)
        return box
    }

    private func makeActivitySection() -> NSView {
        let box = makeSectionBox()
        let stack = sectionStack(in: box)

        let title = label("Activity", size: 15, weight: .semibold)
        configureTextView(activityTextView)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = activityTextView
        scrollView.heightAnchor.constraint(equalToConstant: 138).isActive = true

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(scrollView)
        return box
    }

    @objc private func requestAccess() {
        requestAccessButton.isEnabled = false
        accessStatusLabel.stringValue = "Requesting..."
        accessDetailLabel.stringValue = "macOS may show a Calendar permission prompt."

        Task {
            do {
                _ = try await requestCalendarAccess()
            } catch {
                accessDetailLabel.stringValue = "Calendar access request failed: \(error.localizedDescription)"
            }
            requestAccessButton.isEnabled = true
            refreshState()
        }
    }

    @objc private func refresh() {
        refreshState()
    }

    @objc private func copyMCPCommand() {
        let command = mcpCommand()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copyMCPHintButton.title = "Copied"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.copyMCPHintButton.title = "Copy MCP Command"
        }
    }

    private func mcpCommand() -> String {
        let appURL = Bundle.main.bundleURL
        let candidateRepoRoot = appURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidateMCPServer = candidateRepoRoot
            .appendingPathComponent("dist")
            .appendingPathComponent("mcp-server.js")

        if FileManager.default.fileExists(atPath: candidateMCPServer.path) {
            return "node \(shellQuote(candidateMCPServer.path))"
        }

        return "node /path/to/darktime/dist/mcp-server.js"
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func refreshState() {
        refreshStorageState()

        let status = EKEventStore.authorizationStatus(for: .event)
        let canReadWrite = hasFullCalendarAccess(status)

        accessStatusLabel.stringValue = statusName(status)
        accessStatusLabel.textColor = canReadWrite ? .systemGreen : .systemOrange
        requestAccessButton.isEnabled = !canReadWrite

        if canReadWrite {
            accessDetailLabel.stringValue = "Calendar read/write is available to Darktime."
            refreshSources(canReadWrite: true)
        } else {
            accessDetailLabel.stringValue = "Grant full calendar access before MCP clients can read or write events."
            preferredCalendarLabel.stringValue = "No write target is available yet."
            refreshSources(canReadWrite: false)
        }
    }

    private func refreshStorageState() {
        do {
            try DarktimeStorage.ensureDatabase()
            let sessions = try DarktimeStorage.recentSessions()
            let actions = try DarktimeStorage.recentActions()

            serviceStatusLabel.stringValue = "MCP mode: stdio · storage: ready · recent sessions: \(sessions.count)"
            agentsTextView.string = sessions.isEmpty
                ? "No MCP sessions yet. Use Codex or Claude Code with the MCP command above."
                : sessions.map(agentLine).joined(separator: "\n\n")
            activityTextView.string = actions.isEmpty
                ? "No agent activity has been recorded yet."
                : actions.map(activityLine).joined(separator: "\n")
        } catch {
            serviceStatusLabel.stringValue = "MCP mode: stdio · storage: unavailable"
            agentsTextView.string = "Storage error: \(error)"
            activityTextView.string = "Storage error: \(error)"
        }
    }

    private func refreshSources(canReadWrite: Bool) {
        let calendars = (canReadWrite ? eventStore.calendars(for: .event) : [])
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        let snapshots = calendars.map(calendarSnapshot)
        let writableCalendars = snapshots.filter(\.allowsContentModifications)
        let syncWritableCalendars = writableCalendars.filter { $0.sourceType != "local" }

        if let preferred = syncWritableCalendars.first ?? writableCalendars.first {
            let syncHint = preferred.sourceType == "local" ? "local only; this may not sync to iPhone" : "sync-capable source"
            preferredCalendarLabel.stringValue = "Preferred write target: \(preferred.title) from \(preferred.sourceTitle) (\(syncHint))."
        } else {
            preferredCalendarLabel.stringValue = "No writable calendar found."
        }

        calendarsTextView.string = sourceLines(canReadWrite: canReadWrite, calendars: snapshots).joined(separator: "\n\n")
    }

    private func sourceLines(canReadWrite: Bool, calendars: [CalendarSnapshot]) -> [String] {
        let appleStatus = canReadWrite ? "connected" : "needs access"
        let appleLine = """
        Apple Calendar
          status: \(appleStatus)
          calendars: \(calendars.count)
          writable: \(calendars.filter(\.allowsContentModifications).count)
        """

        let calendarLines = calendars.map(calendarLine)
        let plannedLines = [
            plannedSourceLine("Google Calendar"),
            plannedSourceLine("Feishu Calendar"),
            plannedSourceLine("Outlook"),
            plannedSourceLine("WeCom")
        ]

        return [appleLine] + calendarLines + plannedLines
    }

    private func plannedSourceLine(_ name: String) -> String {
        """
        \(name)
          status: planned
          note: not implemented in dashboard v0
        """
    }

    private func calendarLine(_ calendar: CalendarSnapshot) -> String {
        let writable = calendar.allowsContentModifications ? "writable" : "read-only"
        let sync = calendar.sourceType == "local" ? "local/no phone sync" : "sync candidate"

        return """
        Apple Calendar / \(calendar.title)
          source: \(calendar.sourceTitle) / \(calendar.sourceType)
          type: \(calendar.type)
          status: \(writable), \(sync)
          id: \(calendar.calendarId)
        """
    }

    private func agentLine(_ session: MCPSessionSnapshot) -> String {
        let lastTool = session.lastToolName ?? "none"
        let status = session.lastToolStatus ?? "unknown"
        let version = session.clientVersion.map { " \($0)" } ?? ""

        return """
        \(session.clientName)\(version)
          transport: \(session.transport)
          last seen: \(session.lastSeenAt)
          last tool: \(lastTool) (\(status))
          calls: \(session.toolCallCount)
          session: \(session.id)
        """
    }

    private func activityLine(_ action: ActionLogSnapshot) -> String {
        let writeMarker = action.isWrite ? "WRITE" : "READ "
        let summary = action.summary ?? action.errorMessage ?? ""
        return "\(action.createdAt)  \(writeMarker)  \(action.status)  \(action.clientName ?? "agent")  \(action.action)  \(summary)"
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    private func makeSectionBox() -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderColor = NSColor.separatorColor
        box.cornerRadius = 8
        box.contentViewMargins = NSSize(width: 14, height: 14)
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func configureTextView(_ textView: NSTextView) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
    }

    private func sectionStack(in box: NSBox) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = box.contentView else {
            return stack
        }

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            box.widthAnchor.constraint(greaterThanOrEqualToConstant: 560)
        ])

        return stack
    }

    private func horizontalStack(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func makeSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return spacer
    }
}
