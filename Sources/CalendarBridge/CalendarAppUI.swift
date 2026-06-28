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
        withTitle: "Quit Darktime Calendar Bridge",
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
    private let appPathField = NSTextField(labelWithString: "")
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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Darktime Calendar Bridge"
        window.minSize = NSSize(width: 620, height: 480)
        window.center()

        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = contentView

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 16
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        rootStack.addArrangedSubview(makeHeader())
        rootStack.addArrangedSubview(makeAccessSection())
        rootStack.addArrangedSubview(makeCalendarSection())
        rootStack.addArrangedSubview(makeMCPSection())

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    private func makeHeader() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = label("Darktime Calendar Bridge", size: 24, weight: .semibold)
        let subtitle = label(
            "Local Calendar access for Codex, Claude Code, and other MCP clients.",
            size: 13,
            color: .secondaryLabelColor
        )

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        return stack
    }

    private func makeAccessSection() -> NSView {
        let box = makeSectionBox()
        let stack = sectionStack(in: box)

        let titleRow = horizontalStack(spacing: 10)
        let title = label("Calendar Access", size: 15, weight: .semibold)
        accessStatusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(makeSpacer())
        titleRow.addArrangedSubview(accessStatusLabel)

        accessDetailLabel.font = NSFont.systemFont(ofSize: 12)
        accessDetailLabel.textColor = .secondaryLabelColor
        accessDetailLabel.lineBreakMode = .byWordWrapping
        accessDetailLabel.maximumNumberOfLines = 2

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
        stack.addArrangedSubview(accessDetailLabel)
        stack.addArrangedSubview(buttonRow)
        return box
    }

    private func makeCalendarSection() -> NSView {
        let box = makeSectionBox()
        let stack = sectionStack(in: box)

        let title = label("Visible Calendars", size: 15, weight: .semibold)

        preferredCalendarLabel.font = NSFont.systemFont(ofSize: 12)
        preferredCalendarLabel.textColor = .secondaryLabelColor
        preferredCalendarLabel.lineBreakMode = .byWordWrapping
        preferredCalendarLabel.maximumNumberOfLines = 2

        calendarsTextView.isEditable = false
        calendarsTextView.isSelectable = true
        calendarsTextView.drawsBackground = false
        calendarsTextView.textContainerInset = NSSize(width: 8, height: 8)
        calendarsTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        calendarsTextView.textColor = .labelColor

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = calendarsTextView
        scrollView.heightAnchor.constraint(equalToConstant: 160).isActive = true

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(preferredCalendarLabel)
        stack.addArrangedSubview(scrollView)
        return box
    }

    private func makeMCPSection() -> NSView {
        let box = makeSectionBox()
        let stack = sectionStack(in: box)

        let title = label("MCP Connection", size: 15, weight: .semibold)
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

        copyMCPHintButton.target = self
        copyMCPHintButton.action = #selector(copyMCPCommand)
        copyMCPHintButton.bezelStyle = .rounded

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(mcpHintLabel)
        stack.addArrangedSubview(appPathField)
        stack.addArrangedSubview(copyMCPHintButton)
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
        let status = EKEventStore.authorizationStatus(for: .event)
        let canReadWrite = hasFullCalendarAccess(status)

        accessStatusLabel.stringValue = statusName(status)
        accessStatusLabel.textColor = canReadWrite ? .systemGreen : .systemOrange
        requestAccessButton.isEnabled = !canReadWrite

        if canReadWrite {
            accessDetailLabel.stringValue = "Calendar read/write is available to the local bridge app."
            refreshCalendars()
        } else {
            accessDetailLabel.stringValue = "Grant full calendar access before MCP clients can read or write events."
            preferredCalendarLabel.stringValue = "No write target is available yet."
            calendarsTextView.string = "Calendar access is not granted."
        }
    }

    private func refreshCalendars() {
        let calendars = eventStore.calendars(for: .event)
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

        calendarsTextView.string = snapshots.map(calendarLine).joined(separator: "\n\n")
    }

    private func calendarLine(_ calendar: CalendarSnapshot) -> String {
        let writable = calendar.allowsContentModifications ? "writable" : "read-only"
        let sync = calendar.sourceType == "local" ? "local/no phone sync" : "sync candidate"

        return """
        \(calendar.title)
          source: \(calendar.sourceTitle) / \(calendar.sourceType)
          type: \(calendar.type)
          status: \(writable), \(sync)
          id: \(calendar.calendarId)
        """
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
