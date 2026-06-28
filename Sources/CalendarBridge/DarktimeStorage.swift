import Foundation
import SQLite3

struct MCPSessionSnapshot {
    let id: String
    let clientName: String
    let clientVersion: String?
    let transport: String
    let startedAt: String
    let lastSeenAt: String
    let lastToolName: String?
    let lastToolStatus: String?
    let toolCallCount: Int
}

struct ActionLogSnapshot {
    let id: Int64
    let createdAt: String
    let sessionId: String?
    let clientName: String?
    let source: String
    let action: String
    let status: String
    let isWrite: Bool
    let summary: String?
    let errorCode: String?
    let errorMessage: String?
}

enum DarktimeStorage {
    static func databasePath() -> String {
        if let override = ProcessInfo.processInfo.environment["DARKTIME_DB"], !override.isEmpty {
            return override
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Darktime", isDirectory: true)
            .appendingPathComponent("darktime.sqlite3")
            .path
    }

    static func ensureDatabase() throws {
        let dbPath = databasePath()
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: dbPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        try exec(
            """
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS mcp_sessions (
              id TEXT PRIMARY KEY,
              client_name TEXT NOT NULL,
              client_version TEXT,
              transport TEXT NOT NULL,
              started_at TEXT NOT NULL,
              last_seen_at TEXT NOT NULL,
              last_tool_name TEXT,
              last_tool_status TEXT,
              tool_call_count INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS action_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              created_at TEXT NOT NULL,
              session_id TEXT,
              client_name TEXT,
              source TEXT NOT NULL,
              action TEXT NOT NULL,
              status TEXT NOT NULL,
              is_write INTEGER NOT NULL DEFAULT 0,
              summary TEXT,
              error_code TEXT,
              error_message TEXT,
              request_json TEXT,
              response_json TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_mcp_sessions_last_seen ON mcp_sessions(last_seen_at DESC);
            CREATE INDEX IF NOT EXISTS idx_action_logs_created_at ON action_logs(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_action_logs_session_id ON action_logs(session_id);
            """,
            db: db
        )
    }

    static func recentSessions(limit: Int = 8) throws -> [MCPSessionSnapshot] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
            SELECT
              id,
              client_name,
              client_version,
              transport,
              started_at,
              last_seen_at,
              last_tool_name,
              last_tool_status,
              tool_call_count
            FROM mcp_sessions
            ORDER BY last_seen_at DESC
            LIMIT \(max(1, limit));
            """

        return try query(sql, db: db) { statement in
            MCPSessionSnapshot(
                id: columnText(statement, 0) ?? "",
                clientName: columnText(statement, 1) ?? "MCP stdio client",
                clientVersion: columnText(statement, 2),
                transport: columnText(statement, 3) ?? "stdio",
                startedAt: columnText(statement, 4) ?? "",
                lastSeenAt: columnText(statement, 5) ?? "",
                lastToolName: columnText(statement, 6),
                lastToolStatus: columnText(statement, 7),
                toolCallCount: Int(sqlite3_column_int(statement, 8))
            )
        }
    }

    static func recentActions(limit: Int = 18) throws -> [ActionLogSnapshot] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
            SELECT
              id,
              created_at,
              session_id,
              client_name,
              source,
              action,
              status,
              is_write,
              summary,
              error_code,
              error_message
            FROM action_logs
            ORDER BY created_at DESC
            LIMIT \(max(1, limit));
            """

        return try query(sql, db: db) { statement in
            ActionLogSnapshot(
                id: sqlite3_column_int64(statement, 0),
                createdAt: columnText(statement, 1) ?? "",
                sessionId: columnText(statement, 2),
                clientName: columnText(statement, 3),
                source: columnText(statement, 4) ?? "",
                action: columnText(statement, 5) ?? "",
                status: columnText(statement, 6) ?? "",
                isWrite: sqlite3_column_int(statement, 7) == 1,
                summary: columnText(statement, 8),
                errorCode: columnText(statement, 9),
                errorMessage: columnText(statement, 10)
            )
        }
    }

    private static func openDatabase() throws -> OpaquePointer {
        var db: OpaquePointer?
        let result = sqlite3_open(databasePath(), &db)
        guard result == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database."
            if let db {
                sqlite3_close(db)
            }
            throw StorageError.sqlite(message)
        }
        return db
    }

    private static func exec(_ sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite exec failed."
            sqlite3_free(errorMessage)
            throw StorageError.sqlite(message)
        }
    }

    private static func query<T>(_ sql: String, db: OpaquePointer, row: (OpaquePointer) -> T) throws -> [T] {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw StorageError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(row(statement))
        }
        return rows
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }
}

enum StorageError: Error {
    case sqlite(String)
}
