import Foundation

struct MatterRepositorySnapshot {
    let sessions: [MCPSessionSnapshot]
    let matters: [MatterSnapshot]
    let projects: [ProjectSnapshot]
    let actions: [ActionSnapshot]
}

enum MatterRepository {
    static let droppedRetentionDays = 3

    static var databasePath: String {
        LocalDatabase.databasePath()
    }

    static var shortcutInboxPath: String {
        LocalDatabase.shortcutsInboxPath()
    }

    static var shortcutImportedPath: String {
        LocalDatabase.shortcutsImportedPath()
    }

    static var shortcutFailedPath: String {
        LocalDatabase.shortcutsFailedPath()
    }

    static func refreshSnapshot() throws -> MatterRepositorySnapshot {
        try LocalDatabase.ensureDatabase()
        _ = try LocalDatabase.importShortcutInbox()
        try LocalDatabase.deleteExpiredDroppedMatters(olderThanDays: droppedRetentionDays)

        return MatterRepositorySnapshot(
            sessions: try LocalDatabase.recentSessions(limit: 12),
            matters: try LocalDatabase.recentMatters(limit: 180),
            projects: try LocalDatabase.recentProjects(limit: 80),
            actions: try LocalDatabase.recentActions(limit: 5_000)
        )
    }

    static func capture(text: String, source: String) throws -> MatterSnapshot {
        try LocalDatabase.createMatter(text: text, source: source)
    }

    static func moveMatter(_ matter: MatterSnapshot, to status: String) throws -> MatterSnapshot {
        try LocalDatabase.updateMatterStatus(id: matter.id, status: status)
    }

    static func updateMatterText(_ matter: MatterSnapshot, text: String) throws -> MatterSnapshot {
        try LocalDatabase.updateMatterText(id: matter.id, text: text)
    }

    static func createProjectIssue(project: ProjectSnapshot, text: String) throws -> MatterSnapshot {
        try LocalDatabase.createProjectIssue(projectId: project.id, text: text)
    }

    static func attachIssue(_ issue: MatterSnapshot, to project: ProjectSnapshot) throws -> MatterSnapshot {
        try LocalDatabase.updateIssueProject(id: issue.id, projectId: project.id)
    }

    static func detachIssue(_ issue: MatterSnapshot) throws -> MatterSnapshot {
        try LocalDatabase.updateIssueProject(id: issue.id, projectId: nil)
    }

    static func createLocalRepoProject(title: String, localPath: String, intention: String? = nil) throws -> ProjectSnapshot {
        try LocalDatabase.createLocalRepoProject(title: title, localPath: localPath, intention: intention)
    }

    static func linkIssueToLocalRepoProject(issue: MatterSnapshot, title: String, localPath: String) throws -> ProjectSnapshot {
        try LocalDatabase.linkMatterToLocalRepoProject(matter: issue, title: title, localPath: localPath)
    }

    static func updateProject(id: String, title: String, intention: String?) throws -> ProjectSnapshot {
        try LocalDatabase.updateProject(id: id, title: title, intention: intention)
    }

    static func removeProject(id: String) throws {
        try LocalDatabase.removeProject(id: id)
    }

    @discardableResult
    static func syncLocalGitActions(projects: [ProjectSnapshot]) throws -> Int {
        var failedProjects: [String] = []
        let actions = projects.flatMap { project -> [ActionUpsert] in
            guard let localPath = project.localPath else {
                return []
            }

            do {
                let repository = try LocalGitRepositoryService.resolveRepository(at: localPath)
                return try LocalGitRepositoryService.commitActions(at: repository.rootPath)
                    .map { commit in
                        ActionUpsert(
                            projectId: project.id,
                            source: "local_git",
                            kind: "commit",
                            externalId: commit.hash,
                            happenedAt: commit.date,
                            summary: commit.summary,
                            metadataJson: nil
                        )
                    }
            } catch {
                failedProjects.append(project.title)
                return []
            }
        }

        if actions.isEmpty, !failedProjects.isEmpty {
            throw StorageError.invalidInput("Unable to sync local git actions for \(failedProjects.joined(separator: ", ")).")
        }

        return try LocalDatabase.upsertActions(actions)
    }

    @discardableResult
    static func syncLocalGitPullRequestIssues(projects: [ProjectSnapshot]) throws -> Int {
        var changedCount = 0

        for project in projects {
            guard let localPath = project.localPath else {
                continue
            }
            guard let repoSlug = LocalGitRepositoryService.githubRepositorySlug(at: localPath) else {
                continue
            }

            do {
                let pullRequests = try LocalGitRepositoryService.openPullRequestIssues(repoSlug: repoSlug)
                for pullRequest in pullRequests {
                    _ = try LocalDatabase.upsertProjectIssue(
                        projectId: project.id,
                        text: pullRequest.title,
                        issueKind: "github_pr",
                        source: "github",
                        externalId: pullRequest.externalId,
                        externalUrl: pullRequest.url,
                        externalState: pullRequest.state.isEmpty ? "open" : pullRequest.state
                    )
                    changedCount += 1
                }
                changedCount += try LocalDatabase.closeMissingExternalIssues(
                    projectId: project.id,
                    issueKind: "github_pr",
                    activeExternalIds: Set(pullRequests.map(\.externalId))
                )
            } catch {
                continue
            }
        }

        return changedCount
    }

    static func ensureShortcutFolders() throws {
        try LocalDatabase.ensureShortcutFolders()
    }

    static func shortcutPendingFileCount() throws -> Int {
        try LocalDatabase.shortcutPendingFileCount()
    }

    static func shortcutFailedFileCount() throws -> Int {
        try LocalDatabase.shortcutFailedFileCount()
    }

    static func createShortcutTestCapture(text: String) throws {
        try LocalDatabase.createShortcutTestCapture(text: text)
    }
}
