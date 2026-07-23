import Foundation
import SQLite3

extension LocalDatabase {
    static func openDatabase() throws -> OpaquePointer {
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

    static func matter(id: String, db: OpaquePointer) throws -> MatterSnapshot? {
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

    static func matter(projectId: String, issueKind: String, externalId: String, db: OpaquePointer) throws -> MatterSnapshot? {
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

    static func project(localPath: String, db: OpaquePointer) throws -> ProjectSnapshot? {
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

    static func project(id: String, db: OpaquePointer) throws -> ProjectSnapshot? {
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

    static func exec(_ sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite exec failed."
            sqlite3_free(errorMessage)
            throw StorageError.sqlite(message)
        }
    }

    static func executePrepared(_ sql: String, values: [String?], db: OpaquePointer) throws {
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

    static func query<T>(_ sql: String, db: OpaquePointer, row: (OpaquePointer) -> T) throws -> [T] {
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

    static func queryPrepared<T>(_ sql: String, values: [String?], db: OpaquePointer, row: (OpaquePointer) -> T) throws -> [T] {
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

    static func bind(_ values: [String?], to statement: OpaquePointer) throws {
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

    static func matterSnapshot(_ statement: OpaquePointer) -> MatterSnapshot {
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

    static func projectSnapshot(_ statement: OpaquePointer) -> ProjectSnapshot {
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

    static func actionSnapshot(_ statement: OpaquePointer) -> ActionSnapshot {
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

    static func normalizedOptional(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    static func normalizedIssueKind(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return "manual"
        }
        return normalized
    }

    static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
