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
    appMenu.addItem(
        withTitle: "Calendar",
        action: #selector(CalendarAppDelegate.showCalendarFromMenu(_:)),
        keyEquivalent: "k"
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

    @objc func showCalendarFromMenu(_ sender: Any?) {
        model?.selectedSection = .calendar
        showMainWindow()
    }

    private func buildWindow(model: DashboardModel) {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 840)
        let contentRect = visibleFrame.insetBy(dx: max(24, visibleFrame.width * 0.035), dy: max(24, visibleFrame.height * 0.05))
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Darktime"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .white
        window.minSize = NSSize(width: 1060, height: 680)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: DarktimeDashboard(model: model))

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    private func showMainWindow() {
        if window == nil, let model {
            buildWindow(model: model)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        panel.appearance = NSAppearance(named: .aqua)
        return panel
    }
}

private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case capture
    case inbox
    case rootbox
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: return "Capture"
        case .inbox: return "Inbox"
        case .rootbox: return "Rootbox"
        case .calendar: return "Calendar"
        }
    }

    var systemImage: String {
        switch self {
        case .capture: return "square.and.pencil"
        case .inbox: return "tray.fill"
        case .rootbox: return "tree.fill"
        case .calendar: return "calendar"
        }
    }
}

@MainActor
private final class DashboardModel: ObservableObject {
    @Published var selectedSection: WorkspaceSection = .capture
    @Published var authorizationStatus = "checking"
    @Published var canReadWrite = false
    @Published var calendars: [CalendarSnapshot] = []
    @Published var sessions: [MCPSessionSnapshot] = []
    @Published var matters: [MatterSnapshot] = []
    @Published var storageReady = false
    @Published var storageError: String?
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

    var inboxMatters: [MatterSnapshot] {
        matters.filter { $0.status == "inbox" }
    }

    var rootboxMatters: [MatterSnapshot] {
        matters.filter { $0.status == "rootbox" }
    }

    func refresh() {
        refreshStorage()
        refreshCalendar()
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

    func capture(text: String, source: String = "manual", revealInbox: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        do {
            _ = try DarktimeStorage.createMatter(text: trimmed, source: source)
            if revealInbox {
                selectedSection = .inbox
            }
            refresh()
        } catch {
            storageReady = false
            storageError = String(describing: error)
        }
    }

    func moveMatter(_ matter: MatterSnapshot, to status: String) {
        do {
            _ = try DarktimeStorage.updateMatterStatus(id: matter.id, status: status)
            if status == "rootbox" {
                selectedSection = .rootbox
            } else if status == "dropped" || status == "done" || status == "later" {
                selectedSection = .inbox
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
            _ = try DarktimeStorage.importShortcutInbox()
            sessions = try DarktimeStorage.recentSessions(limit: 12)
            matters = try DarktimeStorage.recentMatters(limit: 180)
            storageReady = true
            storageError = nil
        } catch {
            sessions = []
            matters = []
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
    @AppStorage("darktime.sidebarWidth") private var sidebarWidth = 230.0
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let minSidebarWidth = 190.0
    private let maxSidebarWidth = 340.0

    var body: some View {
        ZStack {
            DTColor.workspace.ignoresSafeArea()
            HStack(spacing: 0) {
                WorkspaceRail(model: model)
                    .frame(width: CGFloat(sidebarWidth))
                    .frame(maxHeight: .infinity)

                SidebarResizeHandle(width: $sidebarWidth, minWidth: minSidebarWidth, maxWidth: maxSidebarWidth)

                workspace
                    .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(DTColor.workspace)
            }
        }
        .font(.system(size: 13, weight: .regular, design: .default))
        .foregroundStyle(DTColor.text)
        .onReceive(refreshTimer) { _ in
            model.refresh()
        }
    }

    @ViewBuilder
    private var workspace: some View {
        switch model.selectedSection {
        case .capture:
            CaptureWorkspace(model: model)
        case .inbox:
            InboxWorkspace(model: model)
        case .rootbox:
            RootboxWorkspace(model: model)
        case .calendar:
            CalendarWorkspace(model: model)
        }
    }
}

private struct SidebarResizeHandle: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double
    @State private var dragStartWidth: Double?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isHovering ? DTColor.line.opacity(1.35) : DTColor.line)
                .frame(width: 1)

            Rectangle()
                .fill(Color.clear)
                .frame(width: 10)
                .contentShape(Rectangle())
        }
        .frame(width: 10)
        .frame(maxHeight: .infinity)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = width
                    }
                    let proposed = (dragStartWidth ?? width) + Double(value.translation.width)
                    width = min(max(proposed, minWidth), maxWidth)
                }
                .onEnded { _ in
                    dragStartWidth = nil
                }
        )
    }
}

private struct WorkspaceRail: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            railButton(for: .capture)

            VStack(alignment: .leading, spacing: 6) {
                railButton(for: .inbox)
                railButton(for: .rootbox)
            }
            .padding(.top, 26)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 54)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(DTColor.sidebar)
    }

    private func railButton(for section: WorkspaceSection) -> some View {
        RailItemButton(
            section: section,
            isSelected: model.selectedSection == section,
            count: count(for: section)
        ) {
            model.selectedSection = section
        }
    }

    private func count(for section: WorkspaceSection) -> Int? {
        switch section {
        case .capture: return nil
        case .inbox: return model.inboxMatters.count
        case .rootbox: return model.rootboxMatters.count
        case .calendar: return nil
        }
    }
}

private struct RailItemButton: View {
    let section: WorkspaceSection
    let isSelected: Bool
    let count: Int?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(isSelected ? DTColor.text : DTColor.dimmed)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(DTColor.workspace.opacity(0.78))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? DTColor.text : DTColor.muted)
            .background(isSelected || isHovering ? DTColor.sidebarSelection : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private struct CaptureWorkspace: View {
    @ObservedObject var model: DashboardModel
    @State private var draft = ""
    @State private var savedMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            DTColor.workspace

            VStack(spacing: 38) {
                Text("What matters right now?")
                    .font(.system(size: 30, weight: .regular, design: .default))
                    .foregroundStyle(DTColor.text)

                VStack(spacing: 0) {
                    TextField("Capture it.", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .foregroundStyle(DTColor.text)
                        .lineLimit(1...4)
                        .focused($focused)
                        .onSubmit(save)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                        .frame(minHeight: 52, alignment: .topLeading)

                    HStack(alignment: .center, spacing: 10) {
                        if let savedMessage {
                            Label(savedMessage, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundStyle(DTColor.green)
                                .transition(.opacity)
                        } else {
                            Label("Inbox", systemImage: "tray")
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundStyle(DTColor.dimmed)
                        }

                        Spacer()

                        Button {
                            save()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 32, height: 32)
                                .background(canSave ? DTColor.text : DTColor.dimmed.opacity(0.45))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(!canSave)
                        .help("Capture")
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                .frame(maxWidth: 760, minHeight: 104)
                .background(DTColor.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(DTColor.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Color.black.opacity(0.08), radius: 22, x: 0, y: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 56)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focused = true
            }
        }
    }

    private var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        model.capture(text: trimmed, source: "manual", revealInbox: false)
        draft = ""

        withAnimation(.easeOut(duration: 0.18)) {
            savedMessage = "Captured to Inbox"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.18)) {
                savedMessage = nil
            }
        }
    }
}

private struct InboxWorkspace: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        MatterWorkspace(
            systemImage: "tray.fill",
            title: "Inbox",
            detail: "Everything captured lands here first. Clear each matter by deciding what leaves and what stays.",
            matters: model.inboxMatters,
            emptyTitle: "Inbox is clear",
            emptyDetail: "Use quick capture to unload the next open loop.",
            model: model
        )
    }
}

private struct RootboxWorkspace: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        MatterWorkspace(
            systemImage: "tree.fill",
            title: "Rootbox",
            detail: "A simple box for matters that survived Clear because they may keep growing.",
            matters: model.rootboxMatters,
            emptyTitle: "Rootbox is empty",
            emptyDetail: "Clear the inbox and keep only the few things worth returning to.",
            model: model
        )
    }
}

private struct MatterWorkspace: View {
    let systemImage: String
    let title: String
    let detail: String
    let matters: [MatterSnapshot]
    let emptyTitle: String
    let emptyDetail: String
    @ObservedObject var model: DashboardModel

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTopBar(systemImage: systemImage, title: title, detail: detail)
            Divider().overlay(DTColor.line.opacity(0.7))

            MatterList(
                matters: matters,
                emptyTitle: emptyTitle,
                emptyDetail: emptyDetail,
                model: model
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DTColor.workspace)
    }
}

private struct WorkspaceTopBar: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DTColor.muted)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(DTColor.text)
            Text(detail)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(DTColor.muted)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 46)
        .background(DTColor.workspace)
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
                }
            }
            .padding(20)
        }
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
        ScrollView {
            VStack(spacing: 0) {
                if matters.isEmpty {
                    EmptyStateLine(systemImage: "tray", title: emptyTitle, detail: emptyDetail)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(matters, id: \.id) { matter in
                            MatterRow(model: model, matter: matter)
                        }
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 26)
            .padding(.bottom, 30)
        }
        .background(DTColor.workspace)
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
            if matter.status == "rootbox" {
                RootboxActionBar(model: model, matter: matter)
            } else {
                InboxClearActionBar(model: model, matter: matter)
            }
        }
        .padding(12)
        .background(DTColor.row)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(DTColor.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
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

private struct InboxClearActionBar: View {
    @ObservedObject var model: DashboardModel
    let matter: MatterSnapshot

    var body: some View {
        HStack(spacing: 8) {
            action("Drop", "xmark", "dropped", tint: DTColor.dimmed)
            action("Later", "clock", "later", tint: DTColor.cyan)
            action("Done", "checkmark", "done", tint: DTColor.green)
            action("Rootbox", "tree", "rootbox", tint: DTColor.green)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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

private struct RootboxActionBar: View {
    @ObservedObject var model: DashboardModel
    let matter: MatterSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.moveMatter(matter, to: "inbox")
            } label: {
                Label("Move to Inbox", systemImage: "tray")
            }
            .tint(DTColor.cyan)

            Button {
                model.moveMatter(matter, to: "dropped")
            } label: {
                Label("Drop", systemImage: "xmark")
            }
            .tint(DTColor.dimmed)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
                .tint(DTColor.accent)
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
    static let workspace = Color.white
    static let sidebar = Color(red: 0.93, green: 0.935, blue: 0.94).opacity(0.86)
    static let sidebarSelection = Color.black.opacity(0.065)
    static let header = Color(red: 0.985, green: 0.985, blue: 0.975)
    static let panel = Color.white
    static let row = Color(red: 0.955, green: 0.955, blue: 0.955)
    static let codeBackground = Color(red: 0.94, green: 0.94, blue: 0.94)
    static let line = Color.black.opacity(0.075)
    static let text = Color.black.opacity(0.86)
    static let muted = Color.black.opacity(0.58)
    static let dimmed = Color.black.opacity(0.36)
    static let accent = Color.black.opacity(0.82)
    static let green = Color(red: 0.18, green: 0.48, blue: 0.28)
    static let cyan = Color(red: 0.19, green: 0.36, blue: 0.56)
    static let amber = Color(red: 0.68, green: 0.42, blue: 0.12)
    static let red = Color(red: 0.68, green: 0.18, blue: 0.18)
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
