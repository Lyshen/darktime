import Foundation
import SQLite3

extension LocalDatabase {
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
}
