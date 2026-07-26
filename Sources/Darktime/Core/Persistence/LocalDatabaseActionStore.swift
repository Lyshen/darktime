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

                guard let actionId = try actionId(
                    projectId: action.projectId,
                    source: action.source,
                    externalId: action.externalId,
                    db: db
                ) else {
                    continue
                }

                try replaceActionRefs(
                    action.refs,
                    actionId: actionId,
                    projectId: action.projectId,
                    now: now,
                    db: db
                )
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

    static func recentActionRefs(limit: Int = 20_000) throws -> [ActionRefSnapshot] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
            SELECT
              action_id,
              project_id,
              ref_kind,
              ref_key,
              ref_title,
              ref_url,
              created_at
            FROM action_refs
            ORDER BY created_at DESC
            LIMIT \(max(1, limit));
            """

        return try query(sql, db: db, row: actionRefSnapshot)
    }

    private static func actionId(
        projectId: String,
        source: String,
        externalId: String,
        db: OpaquePointer
    ) throws -> String? {
        let rows = try queryPrepared(
            """
            SELECT id
            FROM actions
            WHERE project_id = ? AND source = ? AND external_id = ?
            LIMIT 1;
            """,
            values: [projectId, source, externalId],
            db: db
        ) { statement in
            columnText(statement, 0)
        }

        return rows.first ?? nil
    }

    private static func replaceActionRefs(
        _ refs: [ActionRefUpsert],
        actionId: String,
        projectId: String,
        now: String,
        db: OpaquePointer
    ) throws {
        try executePrepared(
            "DELETE FROM action_refs WHERE action_id = ?;",
            values: [actionId],
            db: db
        )

        let uniqueRefs = Array(Set(refs)).sorted { left, right in
            if left.kind != right.kind {
                return left.kind < right.kind
            }
            return left.key < right.key
        }

        for ref in uniqueRefs {
            let normalizedKind = ref.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedKey = ref.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKind.isEmpty, !normalizedKey.isEmpty else {
                continue
            }

            try executePrepared(
                """
                INSERT INTO action_refs (
                  action_id,
                  project_id,
                  ref_kind,
                  ref_key,
                  ref_title,
                  ref_url,
                  created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(action_id, ref_kind, ref_key) DO UPDATE SET
                  ref_title = excluded.ref_title,
                  ref_url = excluded.ref_url;
                """,
                values: [
                    actionId,
                    projectId,
                    normalizedKind,
                    normalizedKey,
                    normalizedOptional(ref.title?.trimmingCharacters(in: .whitespacesAndNewlines)),
                    normalizedOptional(ref.url?.trimmingCharacters(in: .whitespacesAndNewlines)),
                    now
                ],
                db: db
            )
        }
    }
}
