import Foundation
import SQLite3

enum LocalDatabase {
    static let matterStatuses = ["inbox", "today", "later", "done", "dropped", "rootbox"]

    private struct ShortcutImportLocation {
        let rootURL: URL

        var inboxURL: URL {
            rootURL.appendingPathComponent("Inbox", isDirectory: true)
        }

        var importedURL: URL {
            rootURL.appendingPathComponent("Imported", isDirectory: true)
        }

        var failedURL: URL {
            rootURL.appendingPathComponent("Failed", isDirectory: true)
        }
    }

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
        primaryShortcutImportLocation().inboxURL.path
    }

    static func shortcutsImportedPath() -> String {
        primaryShortcutImportLocation().importedURL.path
    }

    static func shortcutsFailedPath() -> String {
        primaryShortcutImportLocation().failedURL.path
    }

    static func ensureShortcutFolders() throws {
        for location in shortcutImportLocations() {
            try FileManager.default.createDirectory(
                at: location.inboxURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: location.importedURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: location.failedURL,
                withIntermediateDirectories: true
            )
        }
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
            CREATE TABLE IF NOT EXISTS roots (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              intention TEXT,
              kind TEXT NOT NULL,
              local_path TEXT UNIQUE,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS output_traces (
              id TEXT PRIMARY KEY,
              root_id TEXT NOT NULL,
              source TEXT NOT NULL,
              kind TEXT NOT NULL,
              external_id TEXT NOT NULL,
              happened_at TEXT NOT NULL,
              summary TEXT,
              metadata_json TEXT,
              created_at TEXT NOT NULL,
              UNIQUE(root_id, source, external_id)
            );
            CREATE INDEX IF NOT EXISTS idx_mcp_sessions_last_seen ON mcp_sessions(last_seen_at DESC);
            CREATE INDEX IF NOT EXISTS idx_action_logs_created_at ON action_logs(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_action_logs_session_id ON action_logs(session_id);
            CREATE INDEX IF NOT EXISTS idx_matters_status_updated ON matters(status, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_matters_created_at ON matters(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_matter_logs_created_at ON matter_logs(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_matter_logs_matter_id ON matter_logs(matter_id);
            CREATE INDEX IF NOT EXISTS idx_roots_kind_updated ON roots(kind, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_output_traces_root_happened ON output_traces(root_id, happened_at DESC);
            CREATE INDEX IF NOT EXISTS idx_output_traces_source_kind ON output_traces(source, kind, happened_at DESC);
            """,
            db: db
        )
        try migrateRoots(db: db)
    }

    static func importShortcutInbox() throws -> Int {
        try ensureShortcutFolders()

        var importedCount = 0
        for location in shortcutImportLocations() {
            importedCount += try importShortcutInbox(from: location)
        }

        return importedCount
    }

    static func shortcutPendingFileCount() throws -> Int {
        try ensureShortcutFolders()
        return try shortcutImportLocations().reduce(0) { count, location in
            count + (try shortcutImportFileCount(in: location.inboxURL))
        }
    }

    static func shortcutFailedFileCount() throws -> Int {
        try ensureShortcutFolders()
        return try shortcutImportLocations().reduce(0) { count, location in
            count + (try shortcutImportFileCount(in: location.failedURL))
        }
    }

    static func createShortcutTestCapture(text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StorageError.invalidInput("Shortcut test capture cannot be empty.")
        }

        try ensureShortcutFolders()
        let fileURL = primaryShortcutImportLocation().inboxURL
            .appendingPathComponent("darktime-test-\(UUID().uuidString).txt")
        try trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
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

    static func createLocalRepoRoot(title: String, localPath: String, intention: String? = nil) throws -> RootSnapshot {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIntention = intention?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw StorageError.invalidInput("Root title cannot be empty.")
        }
        guard !trimmedPath.isEmpty else {
            throw StorageError.invalidInput("Local repo path cannot be empty.")
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        if let existing = try root(localPath: trimmedPath, db: db) {
            if existing.intention == nil, let intention = normalizedOptional(trimmedIntention) {
                let now = isoNow()
                try executePrepared(
                    """
                    UPDATE roots
                    SET intention = ?, updated_at = ?
                    WHERE id = ?;
                    """,
                    values: [intention, now, existing.id],
                    db: db
                )
                return RootSnapshot(
                    id: existing.id,
                    title: existing.title,
                    intention: intention,
                    kind: existing.kind,
                    localPath: existing.localPath,
                    createdAt: existing.createdAt,
                    updatedAt: now
                )
            }
            return existing
        }

        let id = UUID().uuidString
        let now = isoNow()
        try executePrepared(
            """
            INSERT INTO roots (
              id,
              title,
              intention,
              kind,
              local_path,
              created_at,
              updated_at
            ) VALUES (?, ?, ?, 'local_repo', ?, ?, ?);
            """,
            values: [id, trimmedTitle, normalizedOptional(trimmedIntention), trimmedPath, now, now],
            db: db
        )

        return RootSnapshot(
            id: id,
            title: trimmedTitle,
            intention: normalizedOptional(trimmedIntention),
            kind: "local_repo",
            localPath: trimmedPath,
            createdAt: now,
            updatedAt: now
        )
    }

    static func linkMatterToLocalRepoRoot(matter: MatterSnapshot, title: String, localPath: String) throws -> RootSnapshot {
        let root = try createLocalRepoRoot(
            title: title,
            localPath: localPath,
            intention: matter.text
        )
        _ = try updateMatterStatus(id: matter.id, status: "done")
        return root
    }

    static func updateRoot(id: String, title: String, intention: String?) throws -> RootSnapshot {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIntention = intention?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw StorageError.invalidInput("Root title cannot be empty.")
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        guard let current = try root(id: id, db: db) else {
            throw StorageError.notFound("Root \(id) was not found.")
        }

        let now = isoNow()
        try executePrepared(
            """
            UPDATE roots
            SET title = ?, intention = ?, updated_at = ?
            WHERE id = ?;
            """,
            values: [trimmedTitle, normalizedOptional(trimmedIntention), now, id],
            db: db
        )

        return RootSnapshot(
            id: current.id,
            title: trimmedTitle,
            intention: normalizedOptional(trimmedIntention),
            kind: current.kind,
            localPath: current.localPath,
            createdAt: current.createdAt,
            updatedAt: now
        )
    }

    static func removeRoot(id: String) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        guard try root(id: id, db: db) != nil else {
            throw StorageError.notFound("Root \(id) was not found.")
        }

        try exec("BEGIN TRANSACTION;", db: db)
        do {
            try executePrepared(
                """
                DELETE FROM output_traces
                WHERE root_id = ?;
                """,
                values: [id],
                db: db
            )
            try executePrepared(
                """
                DELETE FROM roots
                WHERE id = ?;
                """,
                values: [id],
                db: db
            )
            try exec("COMMIT;", db: db)
        } catch {
            try? exec("ROLLBACK;", db: db)
            throw error
        }
    }

    static func upsertOutputTraces(_ traces: [OutputTraceUpsert]) throws -> Int {
        guard !traces.isEmpty else {
            return 0
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let now = isoNow()
        var changedCount = 0
        try exec("BEGIN TRANSACTION;", db: db)
        do {
            for trace in traces {
                try executePrepared(
                    """
                    INSERT INTO output_traces (
                      id,
                      root_id,
                      source,
                      kind,
                      external_id,
                      happened_at,
                      summary,
                      metadata_json,
                      created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(root_id, source, external_id) DO UPDATE SET
                      kind = excluded.kind,
                      happened_at = excluded.happened_at,
                      summary = excluded.summary,
                      metadata_json = excluded.metadata_json
                    WHERE
                      output_traces.kind IS NOT excluded.kind OR
                      output_traces.happened_at IS NOT excluded.happened_at OR
                      output_traces.summary IS NOT excluded.summary OR
                      output_traces.metadata_json IS NOT excluded.metadata_json;
                    """,
                    values: [
                        UUID().uuidString,
                        trace.rootId,
                        trace.source,
                        trace.kind,
                        trace.externalId,
                        trace.happenedAt,
                        trace.summary,
                        trace.metadataJson,
                        now
                    ],
                    db: db
                )
                changedCount += sqlite3_changes(db) > 0 ? 1 : 0
            }
            try exec("COMMIT;", db: db)
        } catch {
            try? exec("ROLLBACK;", db: db)
            throw error
        }

        return changedCount
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

    static func recentRoots(limit: Int = 80) throws -> [RootSnapshot] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
            SELECT id, title, intention, kind, local_path, created_at, updated_at
            FROM roots
            ORDER BY updated_at DESC
            LIMIT \(max(1, limit));
            """

        return try query(sql, db: db, row: rootSnapshot)
    }

    static func recentOutputTraces(limit: Int = 5_000) throws -> [OutputTraceSnapshot] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
            SELECT
              id,
              root_id,
              source,
              kind,
              external_id,
              happened_at,
              summary,
              metadata_json,
              created_at
            FROM output_traces
            ORDER BY happened_at DESC
            LIMIT \(max(1, limit));
            """

        return try query(sql, db: db, row: outputTraceSnapshot)
    }

    static func latestOutputTrace(rootId: String, source: String, kind: String) throws -> OutputTraceSnapshot? {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
            SELECT
              id,
              root_id,
              source,
              kind,
              external_id,
              happened_at,
              summary,
              metadata_json,
              created_at
            FROM output_traces
            WHERE root_id = ? AND source = ? AND kind = ?
            ORDER BY happened_at DESC
            LIMIT 1;
            """

        return try queryPrepared(
            sql,
            values: [rootId, source, kind],
            db: db,
            row: outputTraceSnapshot
        ).first
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

    private static func root(localPath: String, db: OpaquePointer) throws -> RootSnapshot? {
        let rows = try queryPrepared(
            """
            SELECT id, title, intention, kind, local_path, created_at, updated_at
            FROM roots
            WHERE local_path = ?
            LIMIT 1;
            """,
            values: [localPath],
            db: db,
            row: rootSnapshot
        )
        return rows.first
    }

    private static func root(id: String, db: OpaquePointer) throws -> RootSnapshot? {
        let rows = try queryPrepared(
            """
            SELECT id, title, intention, kind, local_path, created_at, updated_at
            FROM roots
            WHERE id = ?
            LIMIT 1;
            """,
            values: [id],
            db: db,
            row: rootSnapshot
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

    private static func importShortcutInbox(from location: ShortcutImportLocation) throws -> Int {
        let files = try FileManager.default.contentsOfDirectory(
            at: location.inboxURL,
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
                try moveImportedFile(fileURL, to: location.importedURL)
                importedCount += 1
            } catch {
                try? moveImportedFile(fileURL, to: location.failedURL)
            }
        }

        return importedCount
    }

    private static func primaryShortcutImportLocation() -> ShortcutImportLocation {
        ShortcutImportLocation(rootURL: shortcutsAppRootURL())
    }

    private static func shortcutImportLocations() -> [ShortcutImportLocation] {
        [
            ShortcutImportLocation(rootURL: shortcutsAppRootURL()),
            ShortcutImportLocation(rootURL: cloudDocsRootURL())
        ]
    }

    private static func shortcutsAppRootURL() -> URL {
        mobileDocumentsURL()
            .appendingPathComponent("iCloud~is~workflow~my~workflows", isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Darktime", isDirectory: true)
    }

    private static func cloudDocsRootURL() -> URL {
        mobileDocumentsURL()
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent("Darktime", isDirectory: true)
    }

    private static func mobileDocumentsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
    }

    private static func shortcutImportFileCount(in url: URL) throws -> Int {
        return try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { fileURL in
            let ext = fileURL.pathExtension.lowercased()
            return ext == "txt" || ext == "json"
        }
        .count
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

    private static func migrateRoots(db: OpaquePointer) throws {
        do {
            try exec("ALTER TABLE roots ADD COLUMN intention TEXT;", db: db)
        } catch StorageError.sqlite(let message) where message.localizedCaseInsensitiveContains("duplicate column") {
            return
        } catch {
            throw error
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

    private static func rootSnapshot(_ statement: OpaquePointer) -> RootSnapshot {
        RootSnapshot(
            id: columnText(statement, 0) ?? "",
            title: columnText(statement, 1) ?? "",
            intention: columnText(statement, 2),
            kind: columnText(statement, 3) ?? "seed",
            localPath: columnText(statement, 4),
            createdAt: columnText(statement, 5) ?? "",
            updatedAt: columnText(statement, 6) ?? ""
        )
    }

    private static func outputTraceSnapshot(_ statement: OpaquePointer) -> OutputTraceSnapshot {
        OutputTraceSnapshot(
            id: columnText(statement, 0) ?? "",
            rootId: columnText(statement, 1) ?? "",
            source: columnText(statement, 2) ?? "",
            kind: columnText(statement, 3) ?? "",
            externalId: columnText(statement, 4),
            happenedAt: columnText(statement, 5) ?? "",
            summary: columnText(statement, 6),
            metadataJson: columnText(statement, 7),
            createdAt: columnText(statement, 8) ?? ""
        )
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
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

enum StorageError: LocalizedError {
    case sqlite(String)
    case invalidInput(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .sqlite(let message), .invalidInput(let message), .notFound(let message):
            return message
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
