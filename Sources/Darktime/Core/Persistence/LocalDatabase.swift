import Foundation
import SQLite3

enum LocalDatabase {
    static let matterStatuses = ["inbox", "today", "later", "done", "dropped", "rootbox"]

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

    static func shortcutsInboxPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent("Darktime", isDirectory: true)
            .appendingPathComponent("Inbox", isDirectory: true)
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
            CREATE TABLE IF NOT EXISTS matters (
              id TEXT PRIMARY KEY,
              text TEXT NOT NULL,
              status TEXT NOT NULL,
              source TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              raw_payload_json TEXT
            );
            CREATE TABLE IF NOT EXISTS matter_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              matter_id TEXT NOT NULL,
              created_at TEXT NOT NULL,
              action TEXT NOT NULL,
              from_status TEXT,
              to_status TEXT,
              summary TEXT,
              metadata_json TEXT,
              FOREIGN KEY (matter_id) REFERENCES matters(id)
            );
            CREATE INDEX IF NOT EXISTS idx_mcp_sessions_last_seen ON mcp_sessions(last_seen_at DESC);
            CREATE INDEX IF NOT EXISTS idx_action_logs_created_at ON action_logs(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_action_logs_session_id ON action_logs(session_id);
            CREATE INDEX IF NOT EXISTS idx_matters_status_updated ON matters(status, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_matters_created_at ON matters(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_matter_logs_created_at ON matter_logs(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_matter_logs_matter_id ON matter_logs(matter_id);
            """,
            db: db
        )
    }

    static func importShortcutInbox() throws -> Int {
        let inboxURL = URL(fileURLWithPath: shortcutsInboxPath(), isDirectory: true)
        let importedURL = inboxURL.deletingLastPathComponent().appendingPathComponent("Imported", isDirectory: true)
        let failedURL = inboxURL.deletingLastPathComponent().appendingPathComponent("Failed", isDirectory: true)

        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: importedURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: failedURL, withIntermediateDirectories: true)

        let files = try FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "txt" || ext == "json"
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var importedCount = 0
        for fileURL in files {
            do {
                let payload = try shortcutPayload(from: fileURL)
                guard !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw StorageError.invalidInput("Shortcut file is empty.")
                }

                _ = try createMatter(
                    text: payload.text,
                    source: payload.source,
                    rawPayloadJson: payload.rawPayloadJson
                )
                try moveImportedFile(fileURL, to: importedURL)
                importedCount += 1
            } catch {
                try? moveImportedFile(fileURL, to: failedURL)
            }
        }

        return importedCount
    }

    static func createMatter(text: String, source: String = "manual", rawPayloadJson: String? = nil) throws -> MatterSnapshot {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StorageError.invalidInput("Matter text cannot be empty.")
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let id = UUID().uuidString
        let now = isoNow()
        try exec("BEGIN TRANSACTION;", db: db)
        do {
            try executePrepared(
                """
                INSERT INTO matters (
                  id,
                  text,
                  status,
                  source,
                  created_at,
                  updated_at,
                  raw_payload_json
                ) VALUES (?, ?, 'inbox', ?, ?, ?, ?);
                """,
                values: [id, trimmed, source, now, now, rawPayloadJson],
                db: db
            )
            try executePrepared(
                """
                INSERT INTO matter_logs (
                  matter_id,
                  created_at,
                  action,
                  to_status,
                  summary
                ) VALUES (?, ?, 'created', 'inbox', ?);
                """,
                values: [id, now, "Captured to Inbox"],
                db: db
            )
            try exec("COMMIT;", db: db)
        } catch {
            try? exec("ROLLBACK;", db: db)
            throw error
        }

        return MatterSnapshot(
            id: id,
            text: trimmed,
            status: "inbox",
            source: source,
            createdAt: now,
            updatedAt: now,
            rawPayloadJson: rawPayloadJson
        )
    }

    static func updateMatterStatus(id: String, status: String) throws -> MatterSnapshot {
        guard matterStatuses.contains(status) else {
            throw StorageError.invalidInput("Unknown matter status '\(status)'.")
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        guard let current = try matter(id: id, db: db) else {
            throw StorageError.notFound("Matter \(id) was not found.")
        }

        let now = isoNow()
        try exec("BEGIN TRANSACTION;", db: db)
        do {
            try executePrepared(
                """
                UPDATE matters
                SET status = ?, updated_at = ?
                WHERE id = ?;
                """,
                values: [status, now, id],
                db: db
            )
            try executePrepared(
                """
                INSERT INTO matter_logs (
                  matter_id,
                  created_at,
                  action,
                  from_status,
                  to_status,
                  summary
                ) VALUES (?, ?, 'status_changed', ?, ?, ?);
                """,
                values: [id, now, current.status, status, "Moved from \(current.status) to \(status)"],
                db: db
            )
            try exec("COMMIT;", db: db)
        } catch {
            try? exec("ROLLBACK;", db: db)
            throw error
        }

        return MatterSnapshot(
            id: current.id,
            text: current.text,
            status: status,
            source: current.source,
            createdAt: current.createdAt,
            updatedAt: now,
            rawPayloadJson: current.rawPayloadJson
        )
    }

    static func deleteExpiredDroppedMatters(olderThanDays days: Int) throws {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -max(1, days),
            to: Date()
        ) ?? Date()
        let cutoff = ISO8601DateFormatter().string(from: cutoffDate)

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        try exec("BEGIN TRANSACTION;", db: db)
        do {
            try executePrepared(
                """
                DELETE FROM matter_logs
                WHERE matter_id IN (
                  SELECT id FROM matters
                  WHERE status = 'dropped' AND updated_at <= ?
                );
                """,
                values: [cutoff],
                db: db
            )
            try executePrepared(
                """
                DELETE FROM matters
                WHERE status = 'dropped' AND updated_at <= ?;
                """,
                values: [cutoff],
                db: db
            )
            try exec("COMMIT;", db: db)
        } catch {
            try? exec("ROLLBACK;", db: db)
            throw error
        }
    }

    static func recentMatters(status: String? = nil, limit: Int = 60) throws -> [MatterSnapshot] {
        if let status, !matterStatuses.contains(status) {
            throw StorageError.invalidInput("Unknown matter status '\(status)'.")
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql: String
        let values: [String?]
        if let status {
            sql = """
                SELECT id, text, status, source, created_at, updated_at, raw_payload_json
                FROM matters
                WHERE status = ?
                ORDER BY updated_at DESC
                LIMIT \(max(1, limit));
                """
            values = [status]
        } else {
            sql = """
                SELECT id, text, status, source, created_at, updated_at, raw_payload_json
                FROM matters
                ORDER BY updated_at DESC
                LIMIT \(max(1, limit));
                """
            values = []
        }

        return try queryPrepared(sql, values: values, db: db, row: matterSnapshot)
    }

    static func recentMatterLogs(limit: Int = 30) throws -> [MatterLogSnapshot] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
            SELECT
              id,
              matter_id,
              created_at,
              action,
              from_status,
              to_status,
              summary,
              metadata_json
            FROM matter_logs
            ORDER BY created_at DESC
            LIMIT \(max(1, limit));
            """

        return try query(sql, db: db) { statement in
            MatterLogSnapshot(
                id: sqlite3_column_int64(statement, 0),
                matterId: columnText(statement, 1) ?? "",
                createdAt: columnText(statement, 2) ?? "",
                action: columnText(statement, 3) ?? "",
                fromStatus: columnText(statement, 4),
                toStatus: columnText(statement, 5),
                summary: columnText(statement, 6),
                metadataJson: columnText(statement, 7)
            )
        }
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
              error_message,
              request_json,
              response_json
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
                errorMessage: columnText(statement, 10),
                requestJson: columnText(statement, 11),
                responseJson: columnText(statement, 12)
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

    private static func matter(id: String, db: OpaquePointer) throws -> MatterSnapshot? {
        let rows = try queryPrepared(
            """
            SELECT id, text, status, source, created_at, updated_at, raw_payload_json
            FROM matters
            WHERE id = ?
            LIMIT 1;
            """,
            values: [id],
            db: db,
            row: matterSnapshot
        )
        return rows.first
    }

    private static func shortcutPayload(from fileURL: URL) throws -> (text: String, source: String, rawPayloadJson: String?) {
        let data = try Data(contentsOf: fileURL)
        if fileURL.pathExtension.lowercased() == "json" {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any] else {
                throw StorageError.invalidInput("Shortcut JSON must be an object.")
            }
            guard let text = dictionary["text"] as? String else {
                throw StorageError.invalidInput("Shortcut JSON is missing text.")
            }
            let source = dictionary["source"] as? String ?? "shortcut"
            return (text, source, String(data: data, encoding: .utf8))
        }

        return (String(decoding: data, as: UTF8.self), "shortcut", nil)
    }

    private static func moveImportedFile(_ fileURL: URL, to directoryURL: URL) throws {
        let destination = directoryURL.appendingPathComponent("\(UUID().uuidString)-\(fileURL.lastPathComponent)")
        try FileManager.default.moveItem(at: fileURL, to: destination)
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

    private static func executePrepared(_ sql: String, values: [String?], db: OpaquePointer) throws {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw StorageError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        try bind(values, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StorageError.sqlite(String(cString: sqlite3_errmsg(db)))
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

    private static func queryPrepared<T>(_ sql: String, values: [String?], db: OpaquePointer, row: (OpaquePointer) -> T) throws -> [T] {
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            throw StorageError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        try bind(values, to: statement)

        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(row(statement))
        }
        return rows
    }

    private static func bind(_ values: [String?], to statement: OpaquePointer) throws {
        for (index, value) in values.enumerated() {
            let parameterIndex = Int32(index + 1)
            let result: Int32
            if let value {
                result = sqlite3_bind_text(statement, parameterIndex, value, -1, sqliteTransient)
            } else {
                result = sqlite3_bind_null(statement, parameterIndex)
            }
            guard result == SQLITE_OK else {
                throw StorageError.sqlite("Unable to bind SQLite value at index \(parameterIndex).")
            }
        }
    }

    private static func matterSnapshot(_ statement: OpaquePointer) -> MatterSnapshot {
        MatterSnapshot(
            id: columnText(statement, 0) ?? "",
            text: columnText(statement, 1) ?? "",
            status: columnText(statement, 2) ?? "inbox",
            source: columnText(statement, 3) ?? "manual",
            createdAt: columnText(statement, 4) ?? "",
            updatedAt: columnText(statement, 5) ?? "",
            rawPayloadJson: columnText(statement, 6)
        )
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

enum StorageError: Error {
    case sqlite(String)
    case invalidInput(String)
    case notFound(String)
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
