import Foundation

enum ProjectActionSyncService {
    static let syncInterval: TimeInterval = 120

    static func localRepoProjects(from projects: [ProjectSnapshot]) -> [ProjectSnapshot] {
        projects.filter { $0.kind == "local_repo" }
    }

    static func projectIDs(from projects: [ProjectSnapshot]) -> Set<String> {
        Set(localRepoProjects(from: projects).map(\.id))
    }

    static func snapshots(
        projects: [ProjectSnapshot],
        issueMatters: [MatterSnapshot],
        actions: [ActionSnapshot],
        isSyncing: Bool
    ) -> [LocalRepoSnapshot] {
        let repoProjects = localRepoProjects(from: projects)
        let actionsByProject = Dictionary(
            grouping: actions.filter { $0.source == "local_git" && $0.kind == "commit" },
            by: \.projectId
        )
        let issuesByProject = Dictionary(grouping: issueMatters) { $0.projectId ?? "" }

        return repoProjects.compactMap { project in
            snapshot(
                project: project,
                actions: actionsByProject[project.id] ?? [],
                openIssueCount: issuesByProject[project.id]?.count ?? 0,
                isSyncing: isSyncing
            )
        }
        .sorted { left, right in
            sortKey(left) < sortKey(right)
        }
    }

    static func sync(projects: [ProjectSnapshot]) throws -> Int {
        let actionCount = try MatterRepository.syncLocalGitActions(projects: projects)
        let issueCount = try MatterRepository.syncLocalGitPullRequestIssues(projects: projects)
        return actionCount + issueCount
    }

    private static func snapshot(
        project: ProjectSnapshot,
        actions: [ActionSnapshot],
        openIssueCount: Int,
        isSyncing: Bool
    ) -> LocalRepoSnapshot? {
        guard let localPath = project.localPath else {
            return nil
        }

        let sortedActions = actions.sorted { $0.happenedAt > $1.happenedAt }
        let latestAction = sortedActions.first

        return LocalRepoSnapshot(
            project: project,
            repoName: URL(fileURLWithPath: localPath, isDirectory: true).lastPathComponent,
            rootPath: localPath,
            branch: "cached",
            lastCommitAt: latestAction?.happenedAt,
            latestCommitSummary: latestAction?.summary ?? (isSyncing ? "Syncing local git..." : "No actions yet"),
            commitsLast2Days: actionCount(in: sortedActions, days: 2),
            commitsLast7Days: actionCount(in: sortedActions, days: 7),
            commitsLast30Days: actionCount(in: sortedActions, days: 30),
            hasUncommittedChanges: false,
            state: state(lastOutputAt: latestAction?.happenedAt),
            openIssueCount: openIssueCount
        )
    }

    private static func actionCount(in actions: [ActionSnapshot], days: Int) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return actions.filter { action in
            guard let date = parseISODate(action.happenedAt) else {
                return false
            }
            return date >= cutoff
        }.count
    }

    private static func state(lastOutputAt: String?) -> String {
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

    private static func sortKey(_ repo: LocalRepoSnapshot) -> String {
        "\(stateRank(repo.state))-\(repo.project.title.lowercased())"
    }

    private static func stateRank(_ state: String) -> String {
        switch state {
        case "alive": return "0"
        case "quiet": return "1"
        case "fading": return "2"
        case "inactive": return "3"
        case "empty": return "4"
        default: return "4"
        }
    }
}
