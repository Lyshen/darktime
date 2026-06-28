import AppKit
import Combine
import EventKit
import Foundation
import SwiftUI

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
    private var window: NSWindow?
    private var model: DashboardModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = DashboardModel()
        self.model = model
        buildWindow(model: model)
        model.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func buildWindow(model: DashboardModel) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 840)
        let contentRect = visibleFrame.insetBy(dx: max(24, visibleFrame.width * 0.035), dy: max(24, visibleFrame.height * 0.05))
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Darktime"
        window.minSize = NSSize(width: 1060, height: 680)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: DarktimeDashboard(model: model))

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class DashboardModel: ObservableObject {
    @Published var authorizationStatus = "checking"
    @Published var canReadWrite = false
    @Published var calendars: [CalendarSnapshot] = []
    @Published var sessions: [MCPSessionSnapshot] = []
    @Published var actions: [ActionLogSnapshot] = []
    @Published var storageReady = false
    @Published var storageError: String?
    @Published var lastRefreshed: Date?
    @Published var isRequestingAccess = false
    @Published var copiedCommand = false

    private let eventStore = EKEventStore()

    var dbPath: String {
        DarktimeStorage.databasePath()
    }

    var writableCalendars: [CalendarSnapshot] {
        calendars.filter(\.allowsContentModifications)
    }

    var syncWritableCalendars: [CalendarSnapshot] {
        writableCalendars.filter { $0.sourceType != "local" }
    }

    var preferredCalendar: CalendarSnapshot? {
        syncWritableCalendars.first ?? writableCalendars.first
    }

    var serviceReady: Bool {
        storageReady
    }

    var lastActivity: ActionLogSnapshot? {
        actions.first
    }

    func refresh() {
        refreshStorage()
        refreshCalendar()
        lastRefreshed = Date()
    }

    func requestAccess() async {
        isRequestingAccess = true
        defer { isRequestingAccess = false }

        do {
            _ = try await requestCalendarAccess()
        } catch {
            storageError = "Calendar access request failed: \(error.localizedDescription)"
        }
        refresh()
    }

    func copyMCPCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mcpCommand(), forType: .string)
        copiedCommand = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.copiedCommand = false
        }
    }

    func mcpCommand() -> String {
        let appURL = Bundle.main.bundleURL
        let distRepoRoot = appURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildRepoRoot = appURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidates = [
            distRepoRoot.appendingPathComponent("dist").appendingPathComponent("mcp-server.js"),
            buildRepoRoot.appendingPathComponent("dist").appendingPathComponent("mcp-server.js")
        ]

        if let mcpServer = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return "node \(shellQuote(mcpServer.path))"
        }

        return "node /path/to/darktime/dist/mcp-server.js"
    }

    private func refreshStorage() {
        do {
            try DarktimeStorage.ensureDatabase()
            sessions = try DarktimeStorage.recentSessions(limit: 12)
            actions = try DarktimeStorage.recentActions(limit: 42)
            storageReady = true
            storageError = nil
        } catch {
            sessions = []
            actions = []
            storageReady = false
            storageError = String(describing: error)
        }
    }

    private func refreshCalendar() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = statusName(status)
        canReadWrite = hasFullCalendarAccess(status)

        if canReadWrite {
            calendars = eventStore.calendars(for: .event)
                .sorted { lhs, rhs in
                    lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                .map(calendarSnapshot)
        } else {
            calendars = []
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private struct DarktimeDashboard: View {
    @ObservedObject var model: DashboardModel
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            DTColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().overlay(DTColor.line)
                GeometryReader { geometry in
                    let rightWidth = min(450, max(380, geometry.size.width * 0.34))
                    let leftWidth = min(330, max(292, geometry.size.width * 0.26))

                    HStack(alignment: .top, spacing: 16) {
                        SourcesPanel(model: model)
                            .frame(width: leftWidth)
                        VStack(spacing: 16) {
                            StatusPanel(model: model)
                            AgentsPanel(model: model)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        ActivityPanel(model: model)
                            .frame(width: rightWidth)
                    }
                    .padding(20)
                }
            }
        }
        .foregroundStyle(DTColor.text)
        .onReceive(refreshTimer) { _ in
            model.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Darktime")
                    .font(.system(size: 26, weight: .semibold))
                Text("Local time control for agent calendar access")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DTColor.muted)
            }

            Spacer()

            HStack(spacing: 8) {
                StatusPill(
                    title: model.canReadWrite ? "Calendar ready" : "Needs access",
                    systemImage: model.canReadWrite ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tint: model.canReadWrite ? DTColor.green : DTColor.amber
                )
                StatusPill(
                    title: model.serviceReady ? "MCP stdio" : "Storage issue",
                    systemImage: model.serviceReady ? "terminal.fill" : "xmark.octagon.fill",
                    tint: model.serviceReady ? DTColor.cyan : DTColor.red
                )
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text("Auto refresh: 2s")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DTColor.muted)
                Text(model.lastRefreshed.map(formatClock) ?? "Not refreshed")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DTColor.dimmed)
            }

            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button {
                Task { await model.requestAccess() }
            } label: {
                Label(model.canReadWrite ? "Connected" : "Connect", systemImage: model.canReadWrite ? "lock.open.fill" : "lock.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.canReadWrite || model.isRequestingAccess)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(DTColor.header)
    }
}

private struct SourcesPanel: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        Pane(title: "Sources", systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 14) {
                SourceConnectionRow(
                    name: "Apple Calendar",
                    detail: appleDetail,
                    status: model.canReadWrite ? "connected" : model.authorizationStatus,
                    statusColor: model.canReadWrite ? DTColor.green : DTColor.amber,
                    systemImage: "apple.logo"
                )

                if let preferred = model.preferredCalendar {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionEyebrow("Write Target")
                        CalendarMiniRow(calendar: preferred, isPreferred: true)
                    }
                } else {
                    EmptyStateLine(
                        systemImage: "calendar.badge.exclamationmark",
                        title: "No writable target",
                        detail: "Grant Calendar access to enable Apple Calendar writes."
                    )
                }

                Divider().overlay(DTColor.line)

                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrow("Apple Calendars")
                    if model.calendars.isEmpty {
                        Text("No calendars visible yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(DTColor.muted)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(model.calendars, id: \.calendarId) { calendar in
                                    CalendarMiniRow(calendar: calendar, isPreferred: calendar.calendarId == model.preferredCalendar?.calendarId)
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }

                Divider().overlay(DTColor.line)

                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrow("Planned")
                    PlannedSourceRow(name: "Google Calendar")
                    PlannedSourceRow(name: "Feishu Calendar")
                    PlannedSourceRow(name: "Outlook")
                    PlannedSourceRow(name: "WeCom")
                }
            }
        }
    }

    private var appleDetail: String {
        if model.canReadWrite {
            return "\(model.calendars.count) visible, \(model.writableCalendars.count) writable"
        }
        return "Grant macOS permission before agents can read or write."
    }
}

private struct StatusPanel: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        Pane(title: "Local Service", systemImage: "dot.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    MetricTile(title: "MCP", value: "stdio", detail: "client-launched", tint: DTColor.cyan, systemImage: "terminal")
                    MetricTile(
                        title: "Store",
                        value: model.storageReady ? "ready" : "error",
                        detail: model.storageReady ? "SQLite" : "check logs",
                        tint: model.storageReady ? DTColor.green : DTColor.red,
                        systemImage: "cylinder.split.1x2"
                    )
                    MetricTile(
                        title: "Last Action",
                        value: model.lastActivity?.status ?? "none",
                        detail: model.lastActivity.map { formatRelative($0.createdAt) } ?? "waiting",
                        tint: model.lastActivity.map(statusColor) ?? DTColor.dimmed,
                        systemImage: "waveform.path.ecg"
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrow("MCP Command")
                    HStack(spacing: 10) {
                        Text(model.mcpCommand())
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(DTColor.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DTColor.codeBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button {
                            model.copyMCPCommand()
                        } label: {
                            Label(model.copiedCommand ? "Copied" : "Copy", systemImage: model.copiedCommand ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                InfoGrid(rows: [
                    ("Calendar permission", model.authorizationStatus),
                    ("Database", model.dbPath),
                    ("Service health", model.storageReady ? "ready" : (model.storageError ?? "unavailable"))
                ])
            }
        }
    }
}

private struct AgentsPanel: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        Pane(title: "Agent Access", systemImage: "person.crop.circle.badge.checkmark") {
            if model.sessions.isEmpty {
                EmptyStateLine(
                    systemImage: "terminal",
                    title: "No MCP sessions yet",
                    detail: "Start Codex, Claude Code, or another MCP client with the command above."
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.sessions, id: \.id) { session in
                            AgentRow(session: session)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct ActivityPanel: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        Pane(title: "Activity", systemImage: "list.bullet.rectangle") {
            if model.actions.isEmpty {
                EmptyStateLine(
                    systemImage: "clock.badge.questionmark",
                    title: "No recorded activity",
                    detail: "MCP reads and writes will appear here automatically."
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.actions, id: \.id) { action in
                            ActivityRow(action: action)
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
    }
}

private struct Pane<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DTColor.cyan)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DTColor.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DTColor.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct SourceConnectionRow: View {
    let name: String
    let detail: String
    let status: String
    let statusColor: Color
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(statusColor)
                .background(statusColor.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    SignalDot(color: statusColor)
                    Text(status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor)
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(DTColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CalendarMiniRow: View {
    let calendar: CalendarSnapshot
    let isPreferred: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Circle()
                .fill(Color(hex: calendar.color, fallback: DTColor.cyan))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(calendar.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if isPreferred {
                        Image(systemName: "scope")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DTColor.green)
                    }
                }
                Text("\(calendar.sourceTitle) / \(calendar.sourceType)")
                    .font(.system(size: 11))
                    .foregroundStyle(calendar.sourceType == "local" ? DTColor.amber : DTColor.muted)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: calendar.allowsContentModifications ? "pencil.circle.fill" : "lock.circle.fill")
                .foregroundStyle(calendar.allowsContentModifications ? DTColor.green : DTColor.dimmed)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DTColor.row)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct PlannedSourceRow: View {
    let name: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "clock")
                .foregroundStyle(DTColor.dimmed)
                .frame(width: 18)
            Text(name)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text("planned")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DTColor.dimmed)
        }
        .padding(.vertical, 5)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(.system(size: 19, weight: .semibold))
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DTColor.muted)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DTColor.dimmed)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(tint.opacity(0.09))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct InfoGrid: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.0)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DTColor.muted)
                        .frame(width: 132, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 11, design: row.1.contains("/") ? .monospaced : .default))
                        .foregroundStyle(DTColor.text)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
                if row.0 != rows.last?.0 {
                    Divider().overlay(DTColor.line)
                }
            }
        }
        .padding(.horizontal, 10)
        .background(DTColor.row)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct AgentRow: View {
    let session: MCPSessionSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor(session.lastToolStatus ?? "started"))
                .frame(width: 30, height: 30)
                .background(statusColor(session.lastToolStatus ?? "started").opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(session.clientName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(session.toolCallCount) calls")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DTColor.muted)
                }
                Text("\(session.transport) / \(session.lastToolName ?? "server_started") / \(session.lastToolStatus ?? "started")")
                    .font(.system(size: 12))
                    .foregroundStyle(DTColor.muted)
                    .lineLimit(1)
                Text("last seen \(formatRelative(session.lastSeenAt))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DTColor.dimmed)
            }
        }
        .padding(11)
        .background(DTColor.row)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct ActivityRow: View {
    let action: ActionLogSnapshot

    var body: some View {
        let presentation = activityPresentation(action)

        HStack(alignment: .top, spacing: 11) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(presentation.tint)
                .frame(width: 30, height: 30)
                .background(presentation.tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(presentation.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(formatRelative(action.createdAt))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DTColor.dimmed)
                }

                Text(presentation.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(DTColor.muted)
                    .lineLimit(2)

                HStack(spacing: 7) {
                    TinyTag(text: action.isWrite ? "WRITE" : "READ", tint: action.isWrite ? DTColor.amber : DTColor.cyan)
                    TinyTag(text: action.status, tint: presentation.tint)
                    Text(action.clientName ?? "agent")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DTColor.dimmed)
                        .lineLimit(1)
                }
            }
        }
        .padding(11)
        .background(DTColor.row)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(action.isWrite ? DTColor.amber.opacity(0.22) : DTColor.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct TinyTag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct EmptyStateLine: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DTColor.dimmed)
                .frame(width: 28, height: 28)
                .background(DTColor.row)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(DTColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(DTColor.row)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct SectionEyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(DTColor.dimmed)
            .tracking(0)
    }
}

private struct SignalDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.45), radius: 5)
    }
}

private enum DTColor {
    static let background = Color(red: 0.055, green: 0.058, blue: 0.066)
    static let header = Color(red: 0.078, green: 0.082, blue: 0.094)
    static let panel = Color(red: 0.095, green: 0.1, blue: 0.115)
    static let row = Color(red: 0.125, green: 0.13, blue: 0.148)
    static let codeBackground = Color(red: 0.048, green: 0.051, blue: 0.06)
    static let line = Color.white.opacity(0.08)
    static let text = Color.white.opacity(0.9)
    static let muted = Color.white.opacity(0.64)
    static let dimmed = Color.white.opacity(0.42)
    static let green = Color(red: 0.42, green: 0.86, blue: 0.62)
    static let cyan = Color(red: 0.35, green: 0.78, blue: 0.95)
    static let amber = Color(red: 0.94, green: 0.67, blue: 0.26)
    static let red = Color(red: 0.95, green: 0.38, blue: 0.42)
}

private struct ActivityPresentation {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
}

private func activityPresentation(_ action: ActionLogSnapshot) -> ActivityPresentation {
    let tint = statusColor(action.status)
    let request = jsonDictionary(action.requestJson)

    switch action.action {
    case "server_started":
        return ActivityPresentation(
            title: "MCP session started",
            detail: action.summary ?? "A local stdio MCP process was launched.",
            systemImage: "play.circle.fill",
            tint: DTColor.cyan
        )
    case "calendar_authorization_status":
        return ActivityPresentation(
            title: "Checked calendar permission",
            detail: action.summary ?? "Apple Calendar permission status was requested.",
            systemImage: "lock.open.fill",
            tint: tint
        )
    case "calendar_list_calendars":
        return ActivityPresentation(
            title: "Listed calendars",
            detail: action.summary ?? "Apple Calendar source list was requested.",
            systemImage: "calendar",
            tint: tint
        )
    case "calendar_list_events":
        return ActivityPresentation(
            title: "Read calendar events",
            detail: rangeDetail(from: request) ?? action.summary ?? "Calendar events were read.",
            systemImage: "calendar.day.timeline.left",
            tint: tint
        )
    case "calendar_find_free_slots":
        return ActivityPresentation(
            title: "Found free slots",
            detail: rangeDetail(from: request) ?? action.summary ?? "Free time was calculated.",
            systemImage: "clock.badge.checkmark",
            tint: tint
        )
    case "calendar_create_event":
        return ActivityPresentation(
            title: "Created event",
            detail: eventDetail(from: request) ?? action.summary ?? "A calendar event was created.",
            systemImage: "calendar.badge.plus",
            tint: tint
        )
    case "calendar_update_event":
        return ActivityPresentation(
            title: "Updated event",
            detail: eventDetail(from: request) ?? action.summary ?? "A calendar event was updated.",
            systemImage: "calendar.badge.clock",
            tint: tint
        )
    case "calendar_delete_event":
        return ActivityPresentation(
            title: "Deleted event",
            detail: stringValue(request["eventId"]) ?? action.summary ?? "A calendar event was deleted.",
            systemImage: "calendar.badge.minus",
            tint: tint
        )
    default:
        return ActivityPresentation(
            title: humanizeAction(action.action),
            detail: action.errorMessage ?? action.summary ?? action.source,
            systemImage: action.isWrite ? "pencil" : "eye",
            tint: tint
        )
    }
}

private func eventDetail(from request: [String: Any]) -> String? {
    guard let title = stringValue(request["title"]) else {
        return rangeDetail(from: request)
    }

    let range = rangeDetail(from: request)
    return range.map { "\"\(title)\" | \($0)" } ?? "\"\(title)\""
}

private func rangeDetail(from request: [String: Any]) -> String? {
    guard let start = stringValue(request["start"]) else {
        return nil
    }

    if let end = stringValue(request["end"]) {
        return "\(formatLocalDateTime(start)) - \(formatLocalTime(end))"
    }

    return formatLocalDateTime(start)
}

private func jsonDictionary(_ text: String?) -> [String: Any] {
    guard
        let text,
        let data = text.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data),
        let dictionary = object as? [String: Any]
    else {
        return [:]
    }
    return dictionary
}

private func stringValue(_ value: Any?) -> String? {
    guard let value = value as? String, !value.isEmpty else {
        return nil
    }
    return value
}

private func humanizeAction(_ action: String) -> String {
    action
        .split(separator: "_")
        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
}

private func statusColor(_ action: ActionLogSnapshot) -> Color {
    statusColor(action.status)
}

private func statusColor(_ status: String) -> Color {
    switch status {
    case "success", "ready", "fullAccess", "authorized":
        return DTColor.green
    case "blocked", "started":
        return DTColor.amber
    case "error", "denied", "restricted":
        return DTColor.red
    default:
        return DTColor.cyan
    }
}

private func formatClock(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}

private func formatRelative(_ isoString: String) -> String {
    guard let date = parseISODate(isoString) else {
        return isoString
    }

    let seconds = Int(Date().timeIntervalSince(date))
    if seconds < 60 {
        return "\(max(0, seconds))s ago"
    }
    if seconds < 3600 {
        return "\(seconds / 60)m ago"
    }
    if seconds < 86_400 {
        return "\(seconds / 3600)h ago"
    }

    return formatLocalDateTime(isoString)
}

private func formatLocalDateTime(_ isoString: String) -> String {
    guard let date = parseISODate(isoString) else {
        return isoString
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d HH:mm"
    return formatter.string(from: date)
}

private func formatLocalTime(_ isoString: String) -> String {
    guard let date = parseISODate(isoString) else {
        return isoString
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private func parseISODate(_ isoString: String) -> Date? {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractionalFormatter.date(from: isoString) {
        return date
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: isoString)
}

private extension Color {
    init(hex: String?, fallback: Color) {
        guard
            let hex,
            hex.hasPrefix("#"),
            hex.count == 7,
            let value = Int(hex.dropFirst(), radix: 16)
        else {
            self = fallback
            return
        }

        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}
