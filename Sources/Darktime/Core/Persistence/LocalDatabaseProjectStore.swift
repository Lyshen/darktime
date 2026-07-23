import Foundation
import SQLite3

extension LocalDatabase {
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
}
