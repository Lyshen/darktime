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
    @Published var projects: [ProjectSnapshot] = []
    @Published var localRepoSnapshots: [LocalRepoSnapshot] = []
    @Published var outputTraces: [OutputTraceSnapshot] = []
    @Published var storageReady = false
    @Published var storageError: String?
    @Published var shortcutPendingCount = 0
    @Published var shortcutFailedCount = 0
    @Published var isRequestingAccess = false
    @Published var isSyncingTraces = false
    @Published var traceSyncError: String?
    @Published var traceSyncLastFinishedAt: String?
    @Published var traceSyncLastChangeCount = 0
    @Published var copiedCommand = false
    @Published var quickCaptureDraft: String {
        didSet {
            UserDefaults.standard.set(quickCaptureDraft, forKey: Self.quickCaptureDraftKey)
        }
    }

    private let calendarService = AppleCalendarService()
    private var lastLocalRepoTraceSyncAt: Date?
    private var lastLocalRepoTraceSyncProjectIDs = Set<String>()
    private var localRepoTraceSyncTask: Task<Void, Never>?

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

    var issueMatters: [MatterSnapshot] {
        matters.filter { $0.status == "issue" }
    }

    var attentionItemCount: Int {
        localRepoSnapshots.count + issueMatters.count
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
                if status == "issue" {
                    selectedSection = .attention
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

    func addLocalRepoProject() {
        guard let path = chooseLocalRepoPath(message: "Choose a local git repository to show its activity in Attention.") else {
            return
        }

        addLocalRepoProject(path: path)
    }

    func addLocalRepoProject(path: String) {
        do {
            let repository = try LocalGitRepositoryService.resolveRepository(at: path)
            _ = try MatterRepository.createLocalRepoProject(
                title: repository.title,
                localPath: repository.rootPath
            )
            selectedSection = .attention
            refresh()
            scheduleLocalRepoTraceSync(force: true)
        } catch {
            storageError = error.localizedDescription
        }
    }

    func linkIssueToLocalRepoProject(_ issue: MatterSnapshot) {
        guard let path = chooseLocalRepoPath(message: "Choose a local git repository for this issue.") else {
            return
        }

        do {
            let repository = try LocalGitRepositoryService.resolveRepository(at: path)
            _ = try MatterRepository.linkIssueToLocalRepoProject(
                issue: issue,
                title: repository.title,
                localPath: repository.rootPath
            )
            selectedSection = .attention
            refresh()
            scheduleLocalRepoTraceSync(force: true)
        } catch {
            storageError = error.localizedDescription
        }
    }

    func refreshRepoProjects() {
        scheduleLocalRepoTraceSync(force: true)
    }

    @discardableResult
    func updateProject(_ project: ProjectSnapshot, title: String, intention: String?) -> Bool {
        do {
            _ = try MatterRepository.updateProject(
                id: project.id,
                title: title,
                intention: intention
            )
            refresh()
            scheduleLocalRepoTraceSync(force: true)
            return true
        } catch {
            storageError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func removeProject(_ project: ProjectSnapshot) -> Bool {
        do {
            try MatterRepository.removeProject(id: project.id)
            refresh()
            return true
        } catch {
            storageError = error.localizedDescription
            return false
        }
    }

    func openLocalRepo(_ repo: LocalRepoSnapshot) {
        NSWorkspace.shared.open(URL(fileURLWithPath: repo.rootPath, isDirectory: true))
    }

    private func chooseLocalRepoPath(message: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = "Add Local Repo"
        panel.prompt = "Add Repo"
        panel.message = message
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return url.path
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
            projects = snapshot.projects
            outputTraces = snapshot.outputTraces
            refreshLocalRepoSnapshots(from: snapshot.outputTraces)
            scheduleLocalRepoTraceSyncIfNeeded()
            refreshShortcutCounts()
            storageReady = true
            storageError = nil
        } catch {
            sessions = []
            matters = []
            projects = []
            localRepoSnapshots = []
            outputTraces = []
            storageReady = false
            storageError = String(describing: error)
        }
    }

    private func refreshLocalRepoSnapshots(from traces: [OutputTraceSnapshot]) {
        let repoProjects = projects.filter { $0.kind == "local_repo" }
        let tracesByProject = Dictionary(grouping: traces.filter { $0.source == "local_git" && $0.kind == "commit" }, by: \.projectId)
        localRepoSnapshots = repoProjects.compactMap { project in
            cachedLocalRepoSnapshot(project: project, traces: tracesByProject[project.id] ?? [])
        }
            .sorted { left, right in
                localRepoSortKey(left) < localRepoSortKey(right)
            }
    }

    private func cachedLocalRepoSnapshot(project: ProjectSnapshot, traces: [OutputTraceSnapshot]) -> LocalRepoSnapshot? {
        guard let localPath = project.localPath else {
            return nil
        }

        let sortedTraces = traces.sorted { $0.happenedAt > $1.happenedAt }
        let latestTrace = sortedTraces.first

        return LocalRepoSnapshot(
            project: project,
            repoName: URL(fileURLWithPath: localPath, isDirectory: true).lastPathComponent,
            rootPath: localPath,
            branch: "cached",
            lastCommitAt: latestTrace?.happenedAt,
            latestCommitSummary: latestTrace?.summary ?? (isSyncingTraces ? "Syncing local git..." : "No cached commits yet"),
            commitsLast2Days: traceCount(in: sortedTraces, days: 2),
            commitsLast7Days: traceCount(in: sortedTraces, days: 7),
            commitsLast30Days: traceCount(in: sortedTraces, days: 30),
            hasUncommittedChanges: false,
            state: localRepoState(lastOutputAt: latestTrace?.happenedAt)
        )
    }

    private func traceCount(in traces: [OutputTraceSnapshot], days: Int) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return traces.filter { trace in
            guard let date = parseISODate(trace.happenedAt) else {
                return false
            }
            return date >= cutoff
        }.count
    }

    private func localRepoState(lastOutputAt: String?) -> String {
        guard
            let lastOutputAt,
            let date = parseISODate(lastOutputAt)
        else {
            return "empty"
        }

        let days = Date().timeIntervalSince(date) / 86_400
        if days <= 2 {
            return "alive"
        }
        if days <= 7 {
            return "quiet"
        }
        if days <= 30 {
            return "fading"
        }
        return "inactive"
    }

    private func scheduleLocalRepoTraceSyncIfNeeded() {
        let currentIDs = Set(projects.filter { $0.kind == "local_repo" }.map(\.id))
        let projectsChanged = lastLocalRepoTraceSyncProjectIDs != currentIDs

        if projectsChanged || lastLocalRepoTraceSyncAt == nil {
            scheduleLocalRepoTraceSync(force: true)
            return
        }

        guard let lastLocalRepoTraceSyncAt else {
            scheduleLocalRepoTraceSync(force: true)
            return
        }

        if Date().timeIntervalSince(lastLocalRepoTraceSyncAt) > 120 {
            scheduleLocalRepoTraceSync(force: false)
        }
    }

    private func scheduleLocalRepoTraceSync(force: Bool) {
        let repoProjects = projects.filter { $0.kind == "local_repo" }
        guard !repoProjects.isEmpty else {
            localRepoTraceSyncTask?.cancel()
            localRepoTraceSyncTask = nil
            isSyncingTraces = false
            return
        }

        if isSyncingTraces {
            return
        }

        if !force, let lastLocalRepoTraceSyncAt, Date().timeIntervalSince(lastLocalRepoTraceSyncAt) < 120 {
            return
        }

        isSyncingTraces = true
        traceSyncError = nil
        let projectsToSync = repoProjects
        let projectIDsToSync = Set(repoProjects.map(\.id))
        localRepoTraceSyncTask = Task { [weak self, projectsToSync] in
            let result = await Task.detached(priority: .utility) {
                Result {
                    try MatterRepository.syncLocalGitTraces(projects: projectsToSync)
                }
            }.value

            await MainActor.run {
                guard let self else {
                    return
                }
                self.isSyncingTraces = false
                self.lastLocalRepoTraceSyncAt = Date()
                switch result {
                case .success(let changedCount):
                    self.traceSyncError = nil
                    self.traceSyncLastFinishedAt = ISO8601DateFormatter().string(from: Date())
                    self.traceSyncLastChangeCount = changedCount
                    self.lastLocalRepoTraceSyncProjectIDs = projectIDsToSync
                    self.refreshStorage()
                case .failure(let error):
                    self.traceSyncError = error.localizedDescription
                    self.traceSyncLastFinishedAt = ISO8601DateFormatter().string(from: Date())
                }
            }
        }
    }

    private func localRepoSortKey(_ repo: LocalRepoSnapshot) -> String {
        "\(localRepoStateRank(repo.state))-\(repo.project.title.lowercased())"
    }

    private func localRepoStateRank(_ state: String) -> String {
        switch state {
        case "alive": return "0"
        case "quiet": return "1"
        case "fading": return "2"
        case "inactive": return "3"
        case "empty": return "4"
        default: return "4"
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
