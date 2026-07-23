import AppKit
import Combine
import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    private static let quickCaptureDraftKey = "darktime.quickCaptureDraft"
    private static let dailyFocusPrefix = "darktime.dailyFocusIssueIDs."
    private static let dailyReflectionPrefix = "darktime.dailyReflection."

    @Published var selectedSection: WorkspaceSection = .capture
    @Published var authorizationStatus = "checking"
    @Published var canReadWrite = false
    @Published var calendars: [CalendarSnapshot] = []
    @Published var sessions: [MCPSessionSnapshot] = []
    @Published var matters: [MatterSnapshot] = []
    @Published var projects: [ProjectSnapshot] = []
    @Published var localRepoSnapshots: [LocalRepoSnapshot] = []
    @Published var actions: [ActionSnapshot] = []
    @Published var storageReady = false
    @Published var storageError: String?
    @Published var shortcutPendingCount = 0
    @Published var shortcutFailedCount = 0
    @Published var isRequestingAccess = false
    @Published var isSyncingActions = false
    @Published var actionSyncError: String?
    @Published var actionSyncLastFinishedAt: String?
    @Published var actionSyncLastChangeCount = 0
    @Published var copiedCommand = false
    @Published var dailyFocusIssueIDs = Set<String>()
    @Published var dailyReflection: String {
        didSet {
            UserDefaults.standard.set(dailyReflection, forKey: Self.dailyReflectionPrefix + dailyDateKey)
        }
    }
    @Published var quickCaptureDraft: String {
        didSet {
            UserDefaults.standard.set(quickCaptureDraft, forKey: Self.quickCaptureDraftKey)
        }
    }

    private let calendarService = AppleCalendarService()
    private var lastLocalRepoActionSyncAt: Date?
    private var lastLocalRepoActionSyncProjectIDs = Set<String>()
    private var localRepoActionSyncTask: Task<Void, Never>?
    private var dailyDateKey: String

    init() {
        dailyDateKey = Self.currentDailyDateKey()
        quickCaptureDraft = UserDefaults.standard.string(forKey: Self.quickCaptureDraftKey) ?? ""
        dailyFocusIssueIDs = Set(UserDefaults.standard.stringArray(forKey: Self.dailyFocusPrefix + dailyDateKey) ?? [])
        dailyReflection = UserDefaults.standard.string(forKey: Self.dailyReflectionPrefix + dailyDateKey) ?? ""
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

    var projectIssueMatters: [MatterSnapshot] {
        issueMatters.filter { $0.projectId != nil && $0.externalState?.lowercased() != "closed" }
    }

    var attentionItemCount: Int {
        localRepoSnapshots.count + issueMatters.count
    }

    var droppedMatters: [MatterSnapshot] {
        matters.filter { $0.status == "dropped" }
    }

    var todayFocusIssues: [MatterSnapshot] {
        issueMatters.filter { dailyFocusIssueIDs.contains($0.id) }
    }

    var todayActions: [ActionSnapshot] {
        actions.filter { action in
            guard let date = parseISODate(action.happenedAt) else {
                return false
            }
            return Calendar.current.isDateInToday(date)
        }
    }

    func refresh() {
        refreshDailyStateIfNeeded()
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
                } else if status == "dropped" || status == "done" || status == "inbox" {
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
            scheduleLocalRepoActionSync(force: true)
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
            scheduleLocalRepoActionSync(force: true)
        } catch {
            storageError = error.localizedDescription
        }
    }

    @discardableResult
    func createProjectIssue(_ project: ProjectSnapshot, text: String) -> Bool {
        do {
            _ = try MatterRepository.createProjectIssue(project: project, text: text)
            selectedSection = .attention
            refresh()
            return true
        } catch {
            storageReady = false
            storageError = String(describing: error)
            return false
        }
    }

    @discardableResult
    func attachIssue(_ issue: MatterSnapshot, to project: ProjectSnapshot) -> Bool {
        do {
            _ = try MatterRepository.attachIssue(issue, to: project)
            refresh()
            return true
        } catch {
            storageReady = false
            storageError = String(describing: error)
            return false
        }
    }

    @discardableResult
    func detachIssue(_ issue: MatterSnapshot) -> Bool {
        do {
            _ = try MatterRepository.detachIssue(issue)
            refresh()
            return true
        } catch {
            storageReady = false
            storageError = String(describing: error)
            return false
        }
    }

    @discardableResult
    func updateIssue(_ issue: MatterSnapshot, text: String) -> Bool {
        do {
            _ = try MatterRepository.updateMatterText(issue, text: text)
            refresh()
            return true
        } catch {
            storageReady = false
            storageError = String(describing: error)
            return false
        }
    }

    func refreshRepoProjects() {
        scheduleLocalRepoActionSync(force: true)
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
            scheduleLocalRepoActionSync(force: true)
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

    func projectTitle(for issue: MatterSnapshot) -> String? {
        guard let projectId = issue.projectId else {
            return nil
        }
        return projectTitle(projectId: projectId)
    }

    func projectTitle(projectId: String) -> String? {
        return projects.first { $0.id == projectId }?.title
    }

    func isDailyFocus(_ issue: MatterSnapshot) -> Bool {
        dailyFocusIssueIDs.contains(issue.id)
    }

    func toggleDailyFocus(_ issue: MatterSnapshot) {
        if dailyFocusIssueIDs.contains(issue.id) {
            dailyFocusIssueIDs.remove(issue.id)
        } else {
            dailyFocusIssueIDs.insert(issue.id)
        }
        saveDailyFocus()
    }

    func clearDailyFocus() {
        dailyFocusIssueIDs.removeAll()
        saveDailyFocus()
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
            actions = snapshot.actions
            refreshLocalRepoSnapshots(from: snapshot.actions)
            scheduleLocalRepoActionSyncIfNeeded()
            refreshShortcutCounts()
            storageReady = true
            storageError = nil
        } catch {
            sessions = []
            matters = []
            projects = []
            localRepoSnapshots = []
            actions = []
            storageReady = false
            storageError = String(describing: error)
        }
    }

    private static func currentDailyDateKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func refreshDailyStateIfNeeded() {
        let currentKey = Self.currentDailyDateKey()
        guard currentKey != dailyDateKey else {
            return
        }
        dailyDateKey = currentKey
        dailyFocusIssueIDs = Set(UserDefaults.standard.stringArray(forKey: Self.dailyFocusPrefix + dailyDateKey) ?? [])
        dailyReflection = UserDefaults.standard.string(forKey: Self.dailyReflectionPrefix + dailyDateKey) ?? ""
    }

    private func saveDailyFocus() {
        UserDefaults.standard.set(Array(dailyFocusIssueIDs), forKey: Self.dailyFocusPrefix + dailyDateKey)
    }

    private func refreshLocalRepoSnapshots(from actions: [ActionSnapshot]) {
        localRepoSnapshots = ProjectActionSyncService.snapshots(
            projects: projects,
            issueMatters: projectIssueMatters,
            actions: actions,
            isSyncing: isSyncingActions
        )
    }

    private func scheduleLocalRepoActionSyncIfNeeded() {
        let currentIDs = ProjectActionSyncService.projectIDs(from: projects)
        let projectsChanged = lastLocalRepoActionSyncProjectIDs != currentIDs

        if projectsChanged || lastLocalRepoActionSyncAt == nil {
            scheduleLocalRepoActionSync(force: true)
            return
        }

        guard let lastLocalRepoActionSyncAt else {
            scheduleLocalRepoActionSync(force: true)
            return
        }

        if Date().timeIntervalSince(lastLocalRepoActionSyncAt) > ProjectActionSyncService.syncInterval {
            scheduleLocalRepoActionSync(force: false)
        }
    }

    private func scheduleLocalRepoActionSync(force: Bool) {
        let repoProjects = ProjectActionSyncService.localRepoProjects(from: projects)
        guard !repoProjects.isEmpty else {
            localRepoActionSyncTask?.cancel()
            localRepoActionSyncTask = nil
            isSyncingActions = false
            return
        }

        if isSyncingActions {
            return
        }

        if !force,
           let lastLocalRepoActionSyncAt,
           Date().timeIntervalSince(lastLocalRepoActionSyncAt) < ProjectActionSyncService.syncInterval {
            return
        }

        isSyncingActions = true
        actionSyncError = nil
        let projectsToSync = repoProjects
        let projectIDsToSync = Set(repoProjects.map(\.id))
        localRepoActionSyncTask = Task { [weak self, projectsToSync] in
            let result = await Task.detached(priority: .utility) {
                Result {
                    try ProjectActionSyncService.sync(projects: projectsToSync)
                }
            }.value

            await MainActor.run {
                guard let self else {
                    return
                }
                self.isSyncingActions = false
                self.lastLocalRepoActionSyncAt = Date()
                switch result {
                case .success(let changedCount):
                    self.actionSyncError = nil
                    self.actionSyncLastFinishedAt = ISO8601DateFormatter().string(from: Date())
                    self.actionSyncLastChangeCount = changedCount
                    self.lastLocalRepoActionSyncProjectIDs = projectIDsToSync
                    self.refreshStorage()
                case .failure(let error):
                    self.actionSyncError = error.localizedDescription
                    self.actionSyncLastFinishedAt = ISO8601DateFormatter().string(from: Date())
                }
            }
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
