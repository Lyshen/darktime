import Foundation

struct MatterStoreSnapshot {
    let sessions: [MCPSessionSnapshot]
    let matters: [MatterSnapshot]
}

enum MatterStore {
    static var databasePath: String {
        DarktimeStorage.databasePath()
    }

    static func refreshSnapshot() throws -> MatterStoreSnapshot {
        try DarktimeStorage.ensureDatabase()
        _ = try DarktimeStorage.importShortcutInbox()

        return MatterStoreSnapshot(
            sessions: try DarktimeStorage.recentSessions(limit: 12),
            matters: try DarktimeStorage.recentMatters(limit: 180)
        )
    }

    static func capture(text: String, source: String) throws -> MatterSnapshot {
        try DarktimeStorage.createMatter(text: text, source: source)
    }

    static func moveMatter(_ matter: MatterSnapshot, to status: String) throws -> MatterSnapshot {
        try DarktimeStorage.updateMatterStatus(id: matter.id, status: status)
    }
}

