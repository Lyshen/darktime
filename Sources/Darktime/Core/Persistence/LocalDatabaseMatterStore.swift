import Foundation
import SQLite3

extension LocalDatabase {
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
}
