import Foundation
import SQLite3

enum LocalDatabase {
    static let matterStatuses = ["inbox", "issue", "done", "dropped"]

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
              raw_payload_json TEXT,
              project_id TEXT,
              issue_kind TEXT,
              external_id TEXT,
              external_url TEXT,
              external_state TEXT
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
            CREATE TABLE IF NOT EXISTS projects (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              intention TEXT,
              kind TEXT NOT NULL,
              local_path TEXT UNIQUE,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS actions (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL,
              source TEXT NOT NULL,
              kind TEXT NOT NULL,
              external_id TEXT NOT NULL,
              happened_at TEXT NOT NULL,
              summary TEXT,
              metadata_json TEXT,
              created_at TEXT NOT NULL,
              UNIQUE(project_id, source, external_id)
            );
            CREATE INDEX IF NOT EXISTS idx_mcp_sessions_last_seen ON mcp_sessions(last_seen_at DESC);
            CREATE INDEX IF NOT EXISTS idx_action_logs_created_at ON action_logs(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_action_logs_session_id ON action_logs(session_id);
            CREATE INDEX IF NOT EXISTS idx_matters_status_updated ON matters(status, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_matters_created_at ON matters(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_matters_project_status ON matters(project_id, status, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_matters_external_issue ON matters(issue_kind, external_id);
            CREATE INDEX IF NOT EXISTS idx_matter_logs_created_at ON matter_logs(created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_matter_logs_matter_id ON matter_logs(matter_id);
            CREATE INDEX IF NOT EXISTS idx_projects_kind_updated ON projects(kind, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_actions_project_happened ON actions(project_id, happened_at DESC);
            CREATE INDEX IF NOT EXISTS idx_actions_source_kind ON actions(source, kind, happened_at DESC);
            """,
            db: db
        )
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
            rawPayloadJson: rawPayloadJson,
            projectId: nil,
            issueKind: nil,
            externalId: nil,
            externalUrl: nil,
            externalState: nil
        )
    }

    static func createProjectIssue(
        projectId: String,
        text: String,
        issueKind: String = "manual",
        source: String = "manual",
        externalId: String? = nil,
        externalUrl: String? = nil,
        externalState: String? = nil
    ) throws -> MatterSnapshot {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKind = normalizedIssueKind(issueKind)
        guard !trimmed.isEmpty else {
            throw StorageError.invalidInput("Issue text cannot be empty.")
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        guard try project(id: projectId, db: db) != nil else {
            throw StorageError.notFound("Project \(projectId) was not found.")
        }

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
                  raw_payload_json,
                  project_id,
                  issue_kind,
                  external_id,
                  external_url,
                  external_state
                ) VALUES (?, ?, 'issue', ?, ?, ?, NULL, ?, ?, ?, ?, ?);
                """,
                values: [
                    id,
                    trimmed,
                    source,
                    now,
                    now,
                    projectId,
                    normalizedKind,
                    normalizedOptional(externalId?.trimmingCharacters(in: .whitespacesAndNewlines)),
                    normalizedOptional(externalUrl?.trimmingCharacters(in: .whitespacesAndNewlines)),
                    normalizedOptional(externalState?.trimmingCharacters(in: .whitespacesAndNewlines)) ?? "open"
                ],
                db: db
            )
            try executePrepared(
                """
                INSERT INTO matter_logs (
                  matter_id,
                  created_at,
                  action,
                  to_status,
                  summary,
                  metadata_json
                ) VALUES (?, ?, 'created_project_issue', 'issue', ?, ?);
                """,
                values: [
                    id,
                    now,
                    "Created project issue",
                    "{\"projectId\":\"\(projectId)\"}"
                ],
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
            status: "issue",
            source: source,
            createdAt: now,
            updatedAt: now,
            rawPayloadJson: nil,
            projectId: projectId,
            issueKind: normalizedKind,
            externalId: normalizedOptional(externalId?.trimmingCharacters(in: .whitespacesAndNewlines)),
            externalUrl: normalizedOptional(externalUrl?.trimmingCharacters(in: .whitespacesAndNewlines)),
            externalState: normalizedOptional(externalState?.trimmingCharacters(in: .whitespacesAndNewlines)) ?? "open"
        )
    }

    static func upsertProjectIssue(
        projectId: String,
        text: String,
        issueKind: String,
        source: String,
        externalId: String,
        externalUrl: String?,
        externalState: String?
    ) throws -> MatterSnapshot {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKind = normalizedIssueKind(issueKind)
        let trimmedExternalId = externalId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedExternalUrl = normalizedOptional(externalUrl?.trimmingCharacters(in: .whitespacesAndNewlines))
        let normalizedExternalState = normalizedOptional(externalState?.trimmingCharacters(in: .whitespacesAndNewlines)) ?? "open"
        guard !trimmed.isEmpty else {
            throw StorageError.invalidInput("Issue text cannot be empty.")
        }
        guard !trimmedExternalId.isEmpty else {
            throw StorageError.invalidInput("External issue id cannot be empty.")
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        guard try project(id: projectId, db: db) != nil else {
            throw StorageError.notFound("Project \(projectId) was not found.")
        }

        if let existing = try matter(projectId: projectId, issueKind: normalizedKind, externalId: trimmedExternalId, db: db) {
            let now = isoNow()
            try executePrepared(
                """
                UPDATE matters
                SET text = ?,
                    source = ?,
                    status = 'issue',
                    external_url = ?,
                    external_state = ?,
                    updated_at = ?
                WHERE id = ?;
                """,
                values: [trimmed, source, normalizedExternalUrl, normalizedExternalState, now, existing.id],
                db: db
            )

            return MatterSnapshot(
                id: existing.id,
                text: trimmed,
                status: "issue",
                source: source,
                createdAt: existing.createdAt,
                updatedAt: now,
                rawPayloadJson: existing.rawPayloadJson,
                projectId: projectId,
                issueKind: normalizedKind,
                externalId: trimmedExternalId,
                externalUrl: normalizedExternalUrl,
                externalState: normalizedExternalState
            )
        }

        return try createProjectIssue(
            projectId: projectId,
            text: trimmed,
            issueKind: normalizedKind,
            source: source,
            externalId: trimmedExternalId,
            externalUrl: normalizedExternalUrl,
            externalState: normalizedExternalState
        )
    }

    static func closeMissingExternalIssues(projectId: String, issueKind: String, activeExternalIds: Set<String>) throws -> Int {
        let normalizedKind = normalizedIssueKind(issueKind)
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let current = try queryPrepared(
            """
            SELECT id, text, status, source, created_at, updated_at, raw_payload_json,
                   project_id, issue_kind, external_id, external_url, external_state
            FROM matters
            WHERE project_id = ? AND issue_kind = ? AND status = 'issue';
            """,
            values: [projectId, normalizedKind],
            db: db,
            row: matterSnapshot
        )

        let stale = current.filter { issue in
            guard let externalId = issue.externalId else {
                return false
            }
            return !activeExternalIds.contains(externalId)
        }
        guard !stale.isEmpty else {
            return 0
        }

        let now = isoNow()
        try exec("BEGIN TRANSACTION;", db: db)
        do {
            for issue in stale {
                try executePrepared(
                    """
                    UPDATE matters
                    SET status = 'done', external_state = 'closed', updated_at = ?
                    WHERE id = ?;
                    """,
                    values: [now, issue.id],
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
                    ) VALUES (?, ?, 'external_closed', 'issue', 'done', ?);
                    """,
                    values: [issue.id, now, "External issue is no longer open"],
                    db: db
                )
            }
            try exec("COMMIT;", db: db)
        } catch {
            try? exec("ROLLBACK;", db: db)
            throw error
        }

        return stale.count
    }

    static func createLocalRepoProject(title: String, localPath: String, intention: String? = nil) throws -> ProjectSnapshot {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIntention = intention?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw StorageError.invalidInput("Project title cannot be empty.")
        }
        guard !trimmedPath.isEmpty else {
            throw StorageError.invalidInput("Local repo path cannot be empty.")
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        if let existing = try project(localPath: trimmedPath, db: db) {
            if existing.intention == nil, let intention = normalizedOptional(trimmedIntention) {
                let now = isoNow()
                try executePrepared(
                    """
                    UPDATE projects
                    SET intention = ?, updated_at = ?
                    WHERE id = ?;
                    """,
                    values: [intention, now, existing.id],
                    db: db
                )
                return ProjectSnapshot(
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
            INSERT INTO projects (
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

        return ProjectSnapshot(
            id: id,
            title: trimmedTitle,
            intention: normalizedOptional(trimmedIntention),
            kind: "local_repo",
            localPath: trimmedPath,
            createdAt: now,
            updatedAt: now
        )
    }

    static func linkMatterToLocalRepoProject(matter: MatterSnapshot, title: String, localPath: String) throws -> ProjectSnapshot {
        let project = try createLocalRepoProject(
            title: title,
            localPath: localPath,
            intention: matter.text
        )
        _ = try updateMatterStatus(id: matter.id, status: "done")
        return project
    }

    static func updateProject(id: String, title: String, intention: String?) throws -> ProjectSnapshot {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIntention = intention?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw StorageError.invalidInput("Project title cannot be empty.")
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        guard let current = try project(id: id, db: db) else {
            throw StorageError.notFound("Project \(id) was not found.")
        }

        let now = isoNow()
        try executePrepared(
            """
            UPDATE projects
            SET title = ?, intention = ?, updated_at = ?
            WHERE id = ?;
            """,
            values: [trimmedTitle, normalizedOptional(trimmedIntention), now, id],
            db: db
        )

        return ProjectSnapshot(
            id: current.id,
            title: trimmedTitle,
            intention: normalizedOptional(trimmedIntention),
            kind: current.kind,
            localPath: current.localPath,
            createdAt: current.createdAt,
            updatedAt: now
        )
    }

    static func removeProject(id: String) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        guard try project(id: id, db: db) != nil else {
            throw StorageError.notFound("Project \(id) was not found.")
        }

        try exec("BEGIN TRANSACTION;", db: db)
        do {
            try executePrepared(
                """
                DELETE FROM actions
                WHERE project_id = ?;
                """,
                values: [id],
                db: db
            )
            try executePrepared(
                """
                UPDATE matters
                SET project_id = NULL, updated_at = ?
                WHERE project_id = ?;
                """,
                values: [isoNow(), id],
                db: db
            )
            try executePrepared(
                """
                DELETE FROM projects
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

    static func upsertActions(_ actions: [ActionUpsert]) throws -> Int {
        guard !actions.isEmpty else {
            return 0
        }

        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let now = isoNow()
        var changedCount = 0
        try exec("BEGIN TRANSACTION;", db: db)
        do {
            for action in actions {
                try executePrepared(
                    """
                    INSERT INTO actions (
                      id,
                      project_id,
                      source,
                      kind,
                      external_id,
                      happened_at,
                      summary,
                      metadata_json,
                      created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(project_id, source, external_id) DO UPDATE SET
                      kind = excluded.kind,
                      happened_at = excluded.happened_at,
                      summary = excluded.summary,
                      metadata_json = excluded.metadata_json;
                    """,
                    values: [
                        UUID().uuidString,
                        action.projectId,
                        action.source,
                        action.kind,
                        action.externalId,
                        action.happenedAt,
                        action.summary,
                        action.metadataJson,
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
            rawPayloadJson: current.rawPayloadJson,
            projectId: current.projectId,
            issueKind: current.issueKind,
            externalId: current.externalId,
            externalUrl: current.externalUrl,
            externalState: current.externalState
        )
    }

    static func updateMatterText(id: String, text: String) throws -> MatterSnapshot {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw StorageError.invalidInput("Matter text cannot be empty.")
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
                SET text = ?, updated_at = ?
                WHERE id = ?;
                """,
                values: [trimmed, now, id],
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
                ) VALUES (?, ?, 'text_changed', ?, ?, ?);
                """,
                values: [id, now, current.status, current.status, "Updated matter text"],
                db: db
            )
            try exec("COMMIT;", db: db)
        } catch {
            try? exec("ROLLBACK;", db: db)
            throw error
        }

        return MatterSnapshot(
            id: current.id,
            text: trimmed,
            status: current.status,
            source: current.source,
            createdAt: current.createdAt,
            updatedAt: now,
            rawPayloadJson: current.rawPayloadJson,
            projectId: current.projectId,
            issueKind: current.issueKind,
            externalId: current.externalId,
            externalUrl: current.externalUrl,
            externalState: current.externalState
        )
    }

    static func updateIssueProject(id: String, projectId: String?, issueKind: String? = nil) throws -> MatterSnapshot {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        guard let current = try matter(id: id, db: db) else {
            throw StorageError.notFound("Matter \(id) was not found.")
        }
        guard current.status == "issue" else {
            throw StorageError.invalidInput("Only issues can be attached to projects.")
        }
        if let projectId, try project(id: projectId, db: db) == nil {
            throw StorageError.notFound("Project \(projectId) was not found.")
        }

        let normalizedKind = normalizedIssueKind(issueKind ?? current.issueKind ?? "manual")
        let now = isoNow()
        try exec("BEGIN TRANSACTION;", db: db)
        do {
            try executePrepared(
                """
                UPDATE matters
                SET project_id = ?, issue_kind = ?, updated_at = ?
                WHERE id = ?;
                """,
                values: [projectId, normalizedKind, now, id],
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
                  summary,
                  metadata_json
                ) VALUES (?, ?, 'project_changed', 'issue', 'issue', ?, ?);
                """,
                values: [
                    id,
                    now,
                    projectId == nil ? "Detached issue from project" : "Attached issue to project",
                    projectId.map { "{\"projectId\":\"\($0)\"}" }
                ],
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
            status: current.status,
            source: current.source,
            createdAt: current.createdAt,
            updatedAt: now,
            rawPayloadJson: current.rawPayloadJson,
            projectId: projectId,
            issueKind: normalizedKind,
            externalId: current.externalId,
            externalUrl: current.externalUrl,
            externalState: current.externalState
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
                SELECT id, text, status, source, created_at, updated_at, raw_payload_json,
                       project_id, issue_kind, external_id, external_url, external_state
                FROM matters
                WHERE status = ?
                ORDER BY updated_at DESC
                LIMIT \(max(1, limit));
                """
            values = [status]
        } else {
            sql = """
                SELECT id, text, status, source, created_at, updated_at, raw_payload_json,
                       project_id, issue_kind, external_id, external_url, external_state
                FROM matters
                ORDER BY updated_at DESC
                LIMIT \(max(1, limit));
                """
            values = []
        }

        return try queryPrepared(sql, values: values, db: db, row: matterSnapshot)
    }

    static func recentProjects(limit: Int = 80) throws -> [ProjectSnapshot] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
            SELECT id, title, intention, kind, local_path, created_at, updated_at
            FROM projects
            ORDER BY updated_at DESC
            LIMIT \(max(1, limit));
            """

        return try query(sql, db: db, row: projectSnapshot)
    }

    static func recentActions(limit: Int = 5_000) throws -> [ActionSnapshot] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
            SELECT
              id,
              project_id,
              source,
              kind,
              external_id,
              happened_at,
              summary,
              metadata_json,
              created_at
            FROM actions
            ORDER BY happened_at DESC
            LIMIT \(max(1, limit));
            """

        return try query(sql, db: db, row: actionSnapshot)
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
            SELECT id, text, status, source, created_at, updated_at, raw_payload_json,
                   project_id, issue_kind, external_id, external_url, external_state
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

    private static func matter(projectId: String, issueKind: String, externalId: String, db: OpaquePointer) throws -> MatterSnapshot? {
        let rows = try queryPrepared(
            """
            SELECT id, text, status, source, created_at, updated_at, raw_payload_json,
                   project_id, issue_kind, external_id, external_url, external_state
            FROM matters
            WHERE project_id = ? AND issue_kind = ? AND external_id = ?
            LIMIT 1;
            """,
            values: [projectId, issueKind, externalId],
            db: db,
            row: matterSnapshot
        )
        return rows.first
    }

    private static func project(localPath: String, db: OpaquePointer) throws -> ProjectSnapshot? {
        let rows = try queryPrepared(
            """
            SELECT id, title, intention, kind, local_path, created_at, updated_at
            FROM projects
            WHERE local_path = ?
            LIMIT 1;
            """,
            values: [localPath],
            db: db,
            row: projectSnapshot
        )
        return rows.first
    }

    private static func project(id: String, db: OpaquePointer) throws -> ProjectSnapshot? {
        let rows = try queryPrepared(
            """
            SELECT id, title, intention, kind, local_path, created_at, updated_at
            FROM projects
            WHERE id = ?
            LIMIT 1;
            """,
            values: [id],
            db: db,
            row: projectSnapshot
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
            rawPayloadJson: columnText(statement, 6),
            projectId: columnText(statement, 7),
            issueKind: columnText(statement, 8),
            externalId: columnText(statement, 9),
            externalUrl: columnText(statement, 10),
            externalState: columnText(statement, 11)
        )
    }

    private static func projectSnapshot(_ statement: OpaquePointer) -> ProjectSnapshot {
        ProjectSnapshot(
            id: columnText(statement, 0) ?? "",
            title: columnText(statement, 1) ?? "",
            intention: columnText(statement, 2),
            kind: columnText(statement, 3) ?? "local_repo",
            localPath: columnText(statement, 4),
            createdAt: columnText(statement, 5) ?? "",
            updatedAt: columnText(statement, 6) ?? ""
        )
    }

    private static func actionSnapshot(_ statement: OpaquePointer) -> ActionSnapshot {
        ActionSnapshot(
            id: columnText(statement, 0) ?? "",
            projectId: columnText(statement, 1) ?? "",
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

    private static func normalizedIssueKind(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return "manual"
        }
        return normalized
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
