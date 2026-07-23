import Foundation
import SQLite3

extension LocalDatabase {
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
}
