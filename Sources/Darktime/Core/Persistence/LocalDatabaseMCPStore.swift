import Foundation
import SQLite3

extension LocalDatabase {
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
}
