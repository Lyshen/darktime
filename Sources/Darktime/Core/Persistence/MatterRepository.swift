import Foundation

struct MatterRepositorySnapshot {
    let sessions: [MCPSessionSnapshot]
    let matters: [MatterSnapshot]
}

enum MatterRepository {
    static var databasePath: String {
        LocalDatabase.databasePath()
    }

    static func refreshSnapshot() throws -> MatterRepositorySnapshot {
        try LocalDatabase.ensureDatabase()
        _ = try LocalDatabase.importShortcutInbox()

        return MatterRepositorySnapshot(
            sessions: try LocalDatabase.recentSessions(limit: 12),
            matters: try LocalDatabase.recentMatters(limit: 180)
        )
    }

    static func capture(text: String, source: String) throws -> MatterSnapshot {
        try LocalDatabase.createMatter(text: text, source: source)
    }

    static func moveMatter(_ matter: MatterSnapshot, to status: String) throws -> MatterSnapshot {
        try LocalDatabase.updateMatterStatus(id: matter.id, status: status)
    }
}
