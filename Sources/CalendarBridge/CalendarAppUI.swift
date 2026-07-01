import AppKit
import Carbon.HIToolbox
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
        withTitle: "Quick Capture",
        action: #selector(CalendarAppDelegate.showQuickCaptureFromMenu(_:)),
        keyEquivalent: "n"
    )
    appMenu.addItem(NSMenuItem.separator())
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
    private var quickCaptureWindow: NSPanel?
    private var model: DashboardModel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = DashboardModel()
        self.model = model
        buildWindow(model: model)
        registerQuickCaptureHotKey()
        model.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    @objc func showQuickCaptureFromMenu(_ sender: Any?) {
        showQuickCapture()
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

    private func registerQuickCaptureHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr, hotKeyID.id == 1 else {
                    return noErr
                }

                let appDelegate = Unmanaged<CalendarAppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    appDelegate.showQuickCapture()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: fourCharCode("DTQC"), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func showQuickCapture() {
        guard let model else {
            return
        }

        let panel = quickCaptureWindow ?? makeQuickCaptureWindow()
        quickCaptureWindow = panel
        panel.contentView = NSHostingView(
            rootView: QuickCapturePanel(model: model) { [weak self] in
                self?.quickCaptureWindow?.orderOut(nil)
            }
        )

        if let screen = NSScreen.main {
            let size = panel.frame.size
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - 96
            ))
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makeQuickCaptureWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 108),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }
}

private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case inbox
    case clear
    case rootbox
    case calendar
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .clear: return "Clear"
        case .rootbox: return "Rootbox"
        case .calendar: return "Calendar"
        case .activity: return "Activity"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: return "tray.fill"
        case .clear: return "sparkles"
        case .rootbox: return "tree.fill"
        case .calendar: return "calendar"
        case .activity: return "waveform.path.ecg"
        }
    }
}

@MainActor
private final class DashboardModel: ObservableObject {
    @Published var selectedSection: WorkspaceSection = .inbox
    @Published var authorizationStatus = "checking"
    @Published var canReadWrite = false
    @Published var calendars: [CalendarSnapshot] = []
    @Published var sessions: [MCPSessionSnapshot] = []
    @Published var actions: [ActionLogSnapshot] = []
    @Published var matters: [MatterSnapshot] = []
    @Published var matterLogs: [MatterLogSnapshot] = []
    @Published var storageReady = false
    @Published var storageError: String?
    @Published var lastRefreshed: Date?
    @Published var isRequestingAccess = false
    @Published var copiedCommand = false
    @Published var captureText = ""
    @Published var selectedMatterID: String?

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

    var inboxMatters: [MatterSnapshot] {
        matters.filter { $0.status == "inbox" }
    }

    var clearQueue: [MatterSnapshot] {
        matters.filter { ["inbox", "today", "later"].contains($0.status) }
    }

    var rootboxMatters: [MatterSnapshot] {
        matters.filter { $0.status == "rootbox" }
    }

    var selectedMatter: MatterSnapshot? {
        guard let selectedMatterID else {
            return matters.first
        }
        return matters.first { $0.id == selectedMatterID } ?? matters.first
    }

    var todayCount: Int {
        matters.filter { $0.status == "today" }.count
    }

    var droppedCount: Int {
        matters.filter { $0.status == "dropped" }.count
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

    func captureCurrentText() {
        capture(text: captureText, source: "manual")
        captureText = ""
    }

    func capture(text: String, source: String = "manual") {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        do {
            let matter = try DarktimeStorage.createMatter(text: trimmed, source: source)
            selectedMatterID = matter.id
            selectedSection = .inbox
            refresh()
        } catch {
            storageReady = false
            storageError = String(describing: error)
        }
    }

    func moveMatter(_ matter: MatterSnapshot, to status: String) {
        do {
            let updated = try DarktimeStorage.updateMatterStatus(id: matter.id, status: status)
            selectedMatterID = updated.id
            if status == "rootbox" {
                selectedSection = .rootbox
            } else if status == "dropped" || status == "done" {
                selectedSection = .clear
            }
            refresh()
        } catch {
            storageReady = false
            storageError = String(describing: error)
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
            matters = try DarktimeStorage.recentMatters(limit: 180)
            matterLogs = try DarktimeStorage.recentMatterLogs(limit: 50)
            storageReady = true
            storageError = nil
        } catch {
            sessions = []
            actions = []
            matters = []
            matterLogs = []
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
                    let rightWidth = min(360, max(300, geometry.size.width * 0.25))
                    let leftWidth: CGFloat = 230

                    HStack(alignment: .top, spacing: 0) {
                        WorkspaceRail(model: model)
                            .frame(width: leftWidth)

                        Divider().overlay(DTColor.line)

                        workspace
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                        if model.selectedSection != .calendar {
                            Divider().overlay(DTColor.line)
                            MatterInspector(model: model)
                                .frame(width: rightWidth)
                        }
                    }
                }
            }
        }
        .foregroundStyle(DTColor.text)
        .onReceive(refreshTimer) { _ in
            model.refresh()
        }
    }

    @ViewBuilder
    private var workspace: some View {
        switch model.selectedSection {
        case .inbox:
            InboxWorkspace(model: model)
        case .clear:
            ClearWorkspace(model: model)
        case .rootbox:
            RootboxWorkspace(model: model)
        case .calendar:
            CalendarWorkspace(model: model)
        case .activity:
            ActivityWorkspace(model: model)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Darktime")
                    .font(.system(size: 26, weight: .semibold))
                Text("Capture without thinking. Clear later. Keep only what matters.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DTColor.muted)
            }

            Spacer()

            HStack(spacing: 8) {
                StatusPill(
                    title: "\(model.inboxMatters.count) inbox",
                    systemImage: "tray.fill",
                    tint: model.inboxMatters.isEmpty ? DTColor.dimmed : DTColor.cyan
                )
                StatusPill(
                    title: "\(model.rootboxMatters.count) rootbox",
                    systemImage: "tree.fill",
                    tint: model.rootboxMatters.isEmpty ? DTColor.dimmed : DTColor.green
                )
                StatusPill(
                    title: model.canReadWrite ? "Calendar ready" : "Needs access",
                    systemImage: model.canReadWrite ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tint: model.canReadWrite ? DTColor.green : DTColor.amber
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
                (NSApp.delegate as? CalendarAppDelegate)?.showQuickCaptureFromMenu(nil)
            } label: {
                Label("Quick Capture", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(DTColor.header)
    }
}

private struct WorkspaceRail: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("WORKFLOW")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DTColor.dimmed)
                    .tracking(0)

                ForEach(WorkspaceSection.allCases) { section in
                    Button {
                        model.selectedSection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.systemImage)
                                .frame(width: 18)
                            Text(section.title)
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if let count = count(for: section), count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DTColor.dimmed)
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .foregroundStyle(model.selectedSection == section ? DTColor.text : DTColor.muted)
                        .background(model.selectedSection == section ? DTColor.row : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().overlay(DTColor.line)

            VStack(alignment: .leading, spacing: 8) {
                Text("CAPTURE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DTColor.dimmed)
                    .tracking(0)
                Text("Use Control + Option + Space anywhere, or capture from the main workspace.")
                    .font(.system(size: 12))
                    .foregroundStyle(DTColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            InfoGrid(rows: [
                ("Store", model.storageReady ? "ready" : "error"),
                ("MCP", "stdio"),
                ("DB", model.dbPath)
            ])
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(DTColor.header)
    }

    private func count(for section: WorkspaceSection) -> Int? {
        switch section {
        case .inbox: return model.inboxMatters.count
        case .clear: return model.clearQueue.count
        case .rootbox: return model.rootboxMatters.count
        case .calendar: return nil
        case .activity: return model.matterLogs.count + model.actions.count
        }
    }
}

private struct CaptureBar: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(DTColor.cyan)
            TextField("Capture a matter without deciding what it means...", text: $model.captureText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .onSubmit {
                    model.captureCurrentText()
                }
            Button {
                model.captureCurrentText()
            } label: {
                Label("Capture", systemImage: "tray.and.arrow.down.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .background(DTColor.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DTColor.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct InboxWorkspace: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CaptureBar(model: model)
            WorkspaceTitle(
                title: "Inbox",
                detail: "Everything captured lands here first. Do not classify at capture time.",
                systemImage: "tray.fill"
            )
            MatterList(
                matters: model.inboxMatters,
                emptyTitle: "Inbox is clear",
                emptyDetail: "Use quick capture to unload the next open loop.",
                model: model
            )
        }
        .padding(20)
    }
}

private struct ClearWorkspace: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceTitle(
                title: "Clear",
                detail: "Move one matter at a time. Most things should leave your head, not become new systems.",
                systemImage: "sparkles"
            )

            if let matter = model.clearQueue.first {
                VStack(alignment: .leading, spacing: 14) {
                    SectionEyebrow("Now Clearing")
                    Text(matter.text)
                        .font(.system(size: 22, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Captured \(formatRelative(matter.createdAt)) from \(matter.source)")
                        .font(.system(size: 12))
                        .foregroundStyle(DTColor.muted)
                    MatterActionBar(model: model, matter: matter, isProminent: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DTColor.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DTColor.cyan.opacity(0.24), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                EmptyStateLine(
                    systemImage: "checkmark.circle.fill",
                    title: "Nothing to clear",
                    detail: "Capture something first, or let the inbox stay quiet."
                )
            }

            MatterList(
                matters: Array(model.clearQueue.dropFirst()),
                emptyTitle: "No remaining queue",
                emptyDetail: "The next captured matter will appear here.",
                model: model
            )
        }
        .padding(20)
    }
}

private struct RootboxWorkspace: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceTitle(
                title: "Rootbox",
                detail: "A simple box for matters that survived Clear because they may keep growing.",
                systemImage: "tree.fill"
            )
            MatterList(
                matters: model.rootboxMatters,
                emptyTitle: "Rootbox is empty",
                emptyDetail: "Clear the inbox and keep only the few things worth returning to.",
                model: model
            )
        }
        .padding(20)
    }
}

private struct CalendarWorkspace: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WorkspaceTitle(
                    title: "Calendar",
                    detail: "Apple Calendar and local MCP service remain available as a secondary surface.",
                    systemImage: "calendar"
                )
                HStack(alignment: .top, spacing: 16) {
                    SourcesPanel(model: model)
                        .frame(width: 320)
                    VStack(spacing: 16) {
                        StatusPanel(model: model)
                        AgentsPanel(model: model)
                            .frame(minHeight: 220)
                    }
                    ActivityPanel(model: model)
                        .frame(width: 380)
                        .frame(minHeight: 420)
                }
            }
            .padding(20)
        }
    }
}

private struct ActivityWorkspace: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceTitle(
                title: "Activity",
                detail: "Recent capture, clear, rootbox, calendar, and MCP activity.",
                systemImage: "waveform.path.ecg"
            )
            HStack(alignment: .top, spacing: 16) {
                MatterLogPanel(model: model)
                ActivityPanel(model: model)
            }
        }
        .padding(20)
    }
}

private struct WorkspaceTitle: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DTColor.cyan)
                .frame(width: 34, height: 34)
                .background(DTColor.cyan.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(DTColor.muted)
            }
            Spacer()
        }
    }
}

private struct MatterList: View {
    let matters: [MatterSnapshot]
    let emptyTitle: String
    let emptyDetail: String
    @ObservedObject var model: DashboardModel

    var body: some View {
        Pane(title: "Matters", systemImage: "list.bullet") {
            if matters.isEmpty {
                EmptyStateLine(systemImage: "tray", title: emptyTitle, detail: emptyDetail)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(matters, id: \.id) { matter in
                            MatterRow(model: model, matter: matter)
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
    }
}

private struct MatterRow: View {
    @ObservedObject var model: DashboardModel
    let matter: MatterSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(for: matter.status))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint(for: matter.status))
                    .frame(width: 30, height: 30)
                    .background(tint(for: matter.status).opacity(0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 5) {
                    Text(matter.text)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        TinyTag(text: matter.status, tint: tint(for: matter.status))
                        Text(matter.source)
                            .font(.system(size: 11))
                            .foregroundStyle(DTColor.dimmed)
                        Text(formatRelative(matter.updatedAt))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DTColor.dimmed)
                    }
                }
                Spacer()
            }
            MatterActionBar(model: model, matter: matter, isProminent: false)
        }
        .padding(12)
        .background(model.selectedMatterID == matter.id ? DTColor.cyan.opacity(0.08) : DTColor.row)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(model.selectedMatterID == matter.id ? DTColor.cyan.opacity(0.3) : DTColor.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture {
            model.selectedMatterID = matter.id
        }
    }

    private func icon(for status: String) -> String {
        switch status {
        case "rootbox": return "tree.fill"
        case "today": return "sun.max.fill"
        case "later": return "clock.fill"
        case "done": return "checkmark.circle.fill"
        case "dropped": return "xmark.circle.fill"
        default: return "tray.fill"
        }
    }

    private func tint(for status: String) -> Color {
        switch status {
        case "rootbox": return DTColor.green
        case "today": return DTColor.amber
        case "later": return DTColor.cyan
        case "done": return DTColor.green
        case "dropped": return DTColor.dimmed
        default: return DTColor.cyan
        }
    }
}

private struct MatterActionBar: View {
    @ObservedObject var model: DashboardModel
    let matter: MatterSnapshot
    let isProminent: Bool

    var body: some View {
        HStack(spacing: 8) {
            action("Drop", "xmark", "dropped", tint: DTColor.dimmed)
            action("Today", "sun.max", "today", tint: DTColor.amber)
            action("Later", "clock", "later", tint: DTColor.cyan)
            action("Done", "checkmark", "done", tint: DTColor.green)
            action("Rootbox", "tree", "rootbox", tint: DTColor.green)
        }
        .buttonStyle(.bordered)
        .controlSize(isProminent ? .regular : .small)
    }

    private func action(_ title: String, _ image: String, _ status: String, tint: Color) -> some View {
        Button {
            model.moveMatter(matter, to: status)
        } label: {
            Label(title, systemImage: image)
        }
        .disabled(matter.status == status)
        .tint(tint)
    }
}

private struct MatterInspector: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceTitle(
                title: "Matter",
                detail: "The selected item is intentionally small. Clear decides what happens next.",
                systemImage: "scope"
            )

            if let matter = model.selectedMatter {
                VStack(alignment: .leading, spacing: 12) {
                    Text(matter.text)
                        .font(.system(size: 16, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    InfoGrid(rows: [
                        ("Status", matter.status),
                        ("Source", matter.source),
                        ("Created", formatLocalDateTime(matter.createdAt)),
                        ("Updated", formatLocalDateTime(matter.updatedAt))
                    ])
                    MatterActionBar(model: model, matter: matter, isProminent: false)
                }
                .padding(14)
                .background(DTColor.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DTColor.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                EmptyStateLine(
                    systemImage: "scope",
                    title: "No matter selected",
                    detail: "Capture or select a matter to inspect it."
                )
            }

            MatterLogPanel(model: model)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(DTColor.background)
    }
}

private struct MatterLogPanel: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        Pane(title: "Matter Activity", systemImage: "clock.arrow.circlepath") {
            if model.matterLogs.isEmpty {
                EmptyStateLine(
                    systemImage: "clock",
                    title: "No matter activity",
                    detail: "Capture and clear actions will appear here."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.matterLogs, id: \.id) { log in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: log.toStatus == "rootbox" ? "tree.fill" : "arrow.right.circle.fill")
                                    .foregroundStyle(log.toStatus == "rootbox" ? DTColor.green : DTColor.cyan)
                                    .frame(width: 28, height: 28)
                                    .background((log.toStatus == "rootbox" ? DTColor.green : DTColor.cyan).opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(log.summary ?? humanizeAction(log.action))
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(2)
                                    Text(formatRelative(log.createdAt))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(DTColor.dimmed)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(DTColor.row)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }
        }
    }
}

private struct QuickCapturePanel: View {
    @ObservedObject var model: DashboardModel
    let onClose: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(DTColor.cyan)
                Text("Quick Capture")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Control + Option + Space")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DTColor.dimmed)
            }
            HStack(spacing: 10) {
                TextField("One line. No labels. No decision yet.", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($focused)
                    .onSubmit(save)
                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "tray.and.arrow.down.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(DTColor.header)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focused = true
            }
        }
        .onExitCommand {
            onClose()
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onClose()
            return
        }
        model.capture(text: trimmed, source: "quick_capture")
        text = ""
        onClose()
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

private func fourCharCode(_ value: String) -> OSType {
    var result: OSType = 0
    for scalar in value.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
