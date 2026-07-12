import Foundation

struct MatterRepositorySnapshot {
    let sessions: [MCPSessionSnapshot]
    let matters: [MatterSnapshot]
    let roots: [RootSnapshot]
    let outputTraces: [OutputTraceSnapshot]
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
            roots: try LocalDatabase.recentRoots(limit: 80),
            outputTraces: try LocalDatabase.recentOutputTraces(limit: 5_000)
        )
    }

    static func capture(text: String, source: String) throws -> MatterSnapshot {
        try LocalDatabase.createMatter(text: text, source: source)
    }

    static func moveMatter(_ matter: MatterSnapshot, to status: String) throws -> MatterSnapshot {
        try LocalDatabase.updateMatterStatus(id: matter.id, status: status)
    }

    static func createLocalRepoRoot(title: String, localPath: String, intention: String? = nil) throws -> RootSnapshot {
        try LocalDatabase.createLocalRepoRoot(title: title, localPath: localPath, intention: intention)
    }

    static func linkMatterToLocalRepoRoot(matter: MatterSnapshot, title: String, localPath: String) throws -> RootSnapshot {
        try LocalDatabase.linkMatterToLocalRepoRoot(matter: matter, title: title, localPath: localPath)
    }

    static func updateRoot(id: String, title: String, intention: String?) throws -> RootSnapshot {
        try LocalDatabase.updateRoot(id: id, title: title, intention: intention)
    }

    static func removeRoot(id: String) throws {
        try LocalDatabase.removeRoot(id: id)
    }

    @discardableResult
    static func syncLocalGitTraces(roots: [RootSnapshot]) throws -> Int {
        var failedRoots: [String] = []
        let traces = roots.flatMap { root -> [OutputTraceUpsert] in
            guard let localPath = root.localPath else {
                return []
            }

            do {
                let repository = try LocalGitRepositoryService.resolveRepository(at: localPath)
                let scanWindow = try localGitScanWindow(for: root)
                return try LocalGitRepositoryService.commitTraces(
                    at: repository.rootPath,
                    since: scanWindow.since,
                    includeLatestFallback: scanWindow.includeLatestFallback
                )
                    .map { commit in
                        OutputTraceUpsert(
                            rootId: root.id,
                            source: "local_git",
                            kind: "commit",
                            externalId: commit.hash,
                            happenedAt: commit.date,
                            summary: commit.summary,
                            metadataJson: nil
                        )
                    }
            } catch {
                failedRoots.append(root.title)
                return []
            }
        }

        if traces.isEmpty, !failedRoots.isEmpty {
            throw StorageError.invalidInput("Unable to sync local git traces for \(failedRoots.joined(separator: ", ")).")
        }

        return try LocalDatabase.upsertOutputTraces(traces)
    }

    private static func localGitScanWindow(for root: RootSnapshot) throws -> (since: String, includeLatestFallback: Bool) {
        guard
            let latestTrace = try LocalDatabase.latestOutputTrace(
                rootId: root.id,
                source: "local_git",
                kind: "commit"
            ),
            let latestDate = parseISODate(latestTrace.happenedAt)
        else {
            return ("1 year ago", true)
        }

        let overlapDate = latestDate.addingTimeInterval(-86_400)
        return (ISO8601DateFormatter().string(from: overlapDate), false)
    }

    private static func parseISODate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
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
