import Foundation

struct MatterRepositorySnapshot {
    let sessions: [MCPSessionSnapshot]
    let matters: [MatterSnapshot]
    let roots: [RootSnapshot]
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
            roots: try LocalDatabase.recentRoots(limit: 80)
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
