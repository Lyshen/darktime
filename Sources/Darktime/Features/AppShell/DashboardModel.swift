import AppKit
import Combine
import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    private static let quickCaptureDraftKey = "darktime.quickCaptureDraft"

    @Published var selectedSection: WorkspaceSection = .capture
    @Published var authorizationStatus = "checking"
    @Published var canReadWrite = false
    @Published var calendars: [CalendarSnapshot] = []
    @Published var sessions: [MCPSessionSnapshot] = []
    @Published var matters: [MatterSnapshot] = []
    @Published var storageReady = false
    @Published var storageError: String?
    @Published var shortcutPendingCount = 0
    @Published var shortcutFailedCount = 0
    @Published var isRequestingAccess = false
    @Published var copiedCommand = false
    @Published var quickCaptureDraft: String {
        didSet {
            UserDefaults.standard.set(quickCaptureDraft, forKey: Self.quickCaptureDraftKey)
        }
    }

    private let calendarService = AppleCalendarService()

    init() {
        quickCaptureDraft = UserDefaults.standard.string(forKey: Self.quickCaptureDraftKey) ?? ""
    }

    var dbPath: String {
        MatterRepository.databasePath
    }

    var shortcutInboxPath: String {
        MatterRepository.shortcutInboxPath
    }

    var shortcutImportedPath: String {
        MatterRepository.shortcutImportedPath
    }

    var shortcutFailedPath: String {
        MatterRepository.shortcutFailedPath
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

    var droppedMatters: [MatterSnapshot] {
        matters.filter { $0.status == "dropped" }
    }

    func refresh() {
        refreshStorage()
        refreshCalendar()
    }

    func requestAccess() async {
        isRequestingAccess = true
        defer { isRequestingAccess = false }

        do {
            try await calendarService.requestAccess()
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

    @discardableResult
    func capture(text: String, source: String = "manual", revealInbox: Bool = false) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        do {
            _ = try MatterRepository.capture(text: trimmed, source: source)
            if revealInbox {
                selectedSection = .inbox
            }
            refresh()
            return true
        } catch {
            storageReady = false
            storageError = String(describing: error)
            return false
        }
    }

    func clearQuickCaptureDraft() {
        quickCaptureDraft = ""
    }

    @discardableResult
    func moveMatter(_ matter: MatterSnapshot, to status: String, navigate: Bool = true) -> Bool {
        do {
            _ = try MatterRepository.moveMatter(matter, to: status)
            if navigate {
                if status == "rootbox" {
                    selectedSection = .rootbox
                } else if status == "dropped" || status == "done" || status == "later" || status == "inbox" {
                    selectedSection = .inbox
                }
            }
            refresh()
            return true
        } catch {
            storageReady = false
            storageError = String(describing: error)
            return false
        }
    }

    func restoreDroppedMatter(_ matter: MatterSnapshot) {
        do {
            _ = try MatterRepository.moveMatter(matter, to: "inbox")
            refresh()
        } catch {
            storageReady = false
            storageError = String(describing: error)
        }
    }

    func prepareShortcutCaptureFolders() {
        do {
            try MatterRepository.ensureShortcutFolders()
            refreshShortcutCounts()
        } catch {
            storageError = String(describing: error)
        }
    }

    @discardableResult
    func createShortcutTestCapture() -> Bool {
        do {
            try MatterRepository.createShortcutTestCapture(
                text: "Darktime Shortcut test capture"
            )
            refresh()
            return true
        } catch {
            storageReady = false
            storageError = String(describing: error)
            return false
        }
    }

    func openShortcutInboxFolder() {
        prepareShortcutCaptureFolders()
        NSWorkspace.shared.open(URL(fileURLWithPath: shortcutInboxPath, isDirectory: true))
    }

    func openShortcutFailedFolder() {
        prepareShortcutCaptureFolders()
        NSWorkspace.shared.open(URL(fileURLWithPath: shortcutFailedPath, isDirectory: true))
    }

    func mcpCommand() -> String {
        MCPCommandProvider.command()
    }

    private func refreshStorage() {
        do {
            let snapshot = try MatterRepository.refreshSnapshot()
            sessions = snapshot.sessions
            matters = snapshot.matters
            refreshShortcutCounts()
            storageReady = true
            storageError = nil
        } catch {
            sessions = []
            matters = []
            storageReady = false
            storageError = String(describing: error)
        }
    }

    private func refreshShortcutCounts() {
        do {
            shortcutPendingCount = try MatterRepository.shortcutPendingFileCount()
            shortcutFailedCount = try MatterRepository.shortcutFailedFileCount()
        } catch {
            shortcutPendingCount = 0
            shortcutFailedCount = 0
        }
    }

    private func refreshCalendar() {
        let authorization = calendarService.authorizationStatus()
        authorizationStatus = authorization.status
        canReadWrite = authorization.canReadWrite
        calendars = calendarService.calendarsIfAuthorized()
    }
}
