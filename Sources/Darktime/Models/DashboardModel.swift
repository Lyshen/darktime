import AppKit
import Carbon.HIToolbox
import Combine
import EventKit
import Foundation
import SwiftUI

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
    @Published var isRequestingAccess = false
    @Published var copiedCommand = false
    @Published var quickCaptureDraft: String {
        didSet {
            UserDefaults.standard.set(quickCaptureDraft, forKey: Self.quickCaptureDraftKey)
        }
    }

    private let eventStore = EKEventStore()

    init() {
        quickCaptureDraft = UserDefaults.standard.string(forKey: Self.quickCaptureDraftKey) ?? ""
    }

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

    @discardableResult
    func capture(text: String, source: String = "manual", revealInbox: Bool = false) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        do {
            _ = try DarktimeStorage.createMatter(text: trimmed, source: source)
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

