#!/usr/bin/env node

import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

type BridgeSuccess = {
  ok: true;
  data: unknown;
};

type BridgeFailure = {
  ok: false;
  error: {
    code: string;
    message: string;
  };
};

type BridgeResponse = BridgeSuccess | BridgeFailure;

type CliPair = [name: string, value: string | number | boolean | null | undefined];

type BridgeLauncher =
  | { kind: "app"; appPath: string }
  | { kind: "binary"; binaryPath: string };

type ToolResult = {
  isError?: boolean;
  content: Array<{
    type: "text";
    text: string;
  }>;
};

type ActionStatus = "started" | "success" | "error" | "blocked";
type MatterStatus = "inbox" | "today" | "later" | "done" | "dropped" | "rootbox";

const moduleDir = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(moduleDir, "..");
const sessionId = randomUUID();
const clientName = process.env.DARKTIME_MCP_CLIENT_NAME || "MCP stdio client";
const clientVersion = process.env.DARKTIME_MCP_CLIENT_VERSION || null;
const matterStatuses = ["inbox", "today", "later", "done", "dropped", "rootbox"] as const;

const server = new McpServer({
  name: "darktime",
  version: "0.1.0"
});

server.registerTool(
  "calendar_authorization_status",
  {
    title: "Calendar Authorization Status",
    description: "Check whether Darktime has full Apple Calendar read/write access.",
    inputSchema: {}
  },
  async () => withToolLogging("calendar_authorization_status", false, {}, async () =>
    textResult(await runBridge("authorization-status"))
  )
);

server.registerTool(
  "calendar_request_access",
  {
    title: "Request Calendar Access",
    description: "Ask macOS to grant full Apple Calendar access to Darktime. This may show a system permission prompt.",
    inputSchema: {}
  },
  async () => withToolLogging("calendar_request_access", false, {}, async () =>
    textResult(await runBridge("request-access"))
  )
);

server.registerTool(
  "calendar_list_calendars",
  {
    title: "List Calendars",
    description: "List Apple calendars visible to this Mac through EventKit.",
    inputSchema: {}
  },
  async () => withToolLogging("calendar_list_calendars", false, {}, async () =>
    textResult(await runBridge("list-calendars"))
  )
);

server.registerTool(
  "matter_create",
  {
    title: "Create Matter",
    description: "Capture a Matter into Darktime Inbox. Use this for lightweight open loops, not confirmed calendar events.",
    inputSchema: {
      text: z.string().min(1).describe("One captured thought, open loop, or attention item."),
      source: z.string().optional().describe("Optional source label. Defaults to mcp.")
    }
  },
  async ({ text, source }) =>
    withToolLogging("matter_create", true, { text, source }, async () =>
      textResult(await createMatter(text, source || "mcp"))
    )
);

server.registerTool(
  "matter_list",
  {
    title: "List Matters",
    description: "List Darktime Matters, optionally filtered by status.",
    inputSchema: {
      status: z.enum(matterStatuses).optional(),
      limit: z.number().int().positive().max(200).optional()
    }
  },
  async ({ status, limit }) =>
    withToolLogging("matter_list", false, { status, limit }, async () =>
      textResult(await listMatters(status, limit ?? 60))
    )
);

server.registerTool(
  "matter_update_status",
  {
    title: "Update Matter Status",
    description: "Move a Darktime Matter between Inbox, Clear outcomes, and Rootbox.",
    inputSchema: {
      id: z.string().min(1),
      status: z.enum(matterStatuses)
    }
  },
  async ({ id, status }) =>
    withToolLogging("matter_update_status", true, { id, status }, async () =>
      textResult(await updateMatterStatus(id, status))
    )
);

server.registerTool(
  "calendar_list_events",
  {
    title: "List Calendar Events",
    description: "List Apple Calendar events in an ISO-8601 time range.",
    inputSchema: {
      start: z.string().describe("Inclusive ISO-8601 start time, for example 2026-06-28T09:00:00+08:00."),
      end: z.string().describe("Exclusive ISO-8601 end time, for example 2026-06-28T18:00:00+08:00."),
      calendarId: z.string().optional().describe("Optional Apple calendar identifier to filter by.")
    }
  },
  async ({ start, end, calendarId }) =>
    withToolLogging("calendar_list_events", false, { start, end, calendarId }, async () =>
      textResult(await runBridge("list-events", [
        ["start", start],
        ["end", end],
        ["calendar-id", calendarId]
      ]))
    )
);

server.registerTool(
  "calendar_find_free_slots",
  {
    title: "Find Free Calendar Slots",
    description: "Find free slots in an ISO-8601 time range. Events marked free do not block time.",
    inputSchema: {
      start: z.string().describe("Inclusive ISO-8601 start time."),
      end: z.string().describe("Exclusive ISO-8601 end time."),
      durationMinutes: z.number().int().positive().describe("Minimum slot duration in minutes."),
      calendarId: z.string().optional().describe("Optional Apple calendar identifier to filter by.")
    }
  },
  async ({ start, end, durationMinutes, calendarId }) =>
    withToolLogging("calendar_find_free_slots", false, { start, end, durationMinutes, calendarId }, async () =>
      textResult(await runBridge("find-free-slots", [
        ["start", start],
        ["end", end],
        ["duration-minutes", durationMinutes],
        ["calendar-id", calendarId]
      ]))
    )
);

server.registerTool(
  "calendar_create_event",
  {
    title: "Create Calendar Event",
    description: "Create an Apple Calendar event. Requires confirm: true because this writes to the user's calendar.",
    inputSchema: {
      title: z.string().min(1),
      start: z.string().describe("ISO-8601 start time."),
      end: z.string().describe("ISO-8601 end time."),
      calendarId: z.string().optional().describe("Optional writable Apple calendar identifier. Defaults to the system default calendar."),
      notes: z.string().optional(),
      location: z.string().optional(),
      url: z.string().optional(),
      availability: z.enum(["busy", "free", "tentative", "unavailable"]).optional(),
      confirm: z.boolean().describe("Must be true to create an event.")
    }
  },
  async ({ title, start, end, calendarId, notes, location, url, availability, confirm }) => {
    const request = { title, start, end, calendarId, notes, location, url, availability, confirm };
    const confirmation = requireConfirmedWrite(confirm, "create a calendar event");
    if (confirmation) return logBlockedTool("calendar_create_event", true, request, confirmation);

    return withToolLogging("calendar_create_event", true, request, async () =>
      textResult(await runBridge("create-event", [
        ["title", title],
        ["start", start],
        ["end", end],
        ["calendar-id", calendarId],
        ["notes", notes],
        ["location", location],
        ["url", url],
        ["availability", availability]
      ]))
    );
  }
);

server.registerTool(
  "calendar_update_event",
  {
    title: "Update Calendar Event",
    description: "Update an Apple Calendar event by EventKit event id. Requires confirm: true because this writes to the user's calendar.",
    inputSchema: {
      eventId: z.string().min(1),
      title: z.string().optional(),
      start: z.string().optional().describe("Optional ISO-8601 start time."),
      end: z.string().optional().describe("Optional ISO-8601 end time."),
      calendarId: z.string().optional().describe("Optional writable Apple calendar identifier to move the event."),
      notes: z.string().optional(),
      location: z.string().optional(),
      url: z.string().optional(),
      availability: z.enum(["busy", "free", "tentative", "unavailable"]).optional(),
      confirm: z.boolean().describe("Must be true to update an event.")
    }
  },
  async ({ eventId, title, start, end, calendarId, notes, location, url, availability, confirm }) => {
    const request = { eventId, title, start, end, calendarId, notes, location, url, availability, confirm };
    const confirmation = requireConfirmedWrite(confirm, "update a calendar event");
    if (confirmation) return logBlockedTool("calendar_update_event", true, request, confirmation);

    return withToolLogging("calendar_update_event", true, request, async () =>
      textResult(await runBridge("update-event", [
        ["event-id", eventId],
        ["title", title],
        ["start", start],
        ["end", end],
        ["calendar-id", calendarId],
        ["notes", notes],
        ["location", location],
        ["url", url],
        ["availability", availability]
      ]))
    );
  }
);

server.registerTool(
  "calendar_delete_event",
  {
    title: "Delete Calendar Event",
    description: "Delete an Apple Calendar event by EventKit event id. Requires confirm: true because this writes to the user's calendar.",
    inputSchema: {
      eventId: z.string().min(1),
      confirm: z.boolean().describe("Must be true to delete an event.")
    }
  },
  async ({ eventId, confirm }) => {
    const request = { eventId, confirm };
    const confirmation = requireConfirmedWrite(confirm, "delete a calendar event");
    if (confirmation) return logBlockedTool("calendar_delete_event", true, request, confirmation);

    return withToolLogging("calendar_delete_event", true, request, async () =>
      textResult(await runBridge("delete-event", [
        ["event-id", eventId]
      ]))
    );
  }
);

const transport = new StdioServerTransport();
await initializeStorage();
await recordSessionStarted();
await server.connect(transport);

function requireConfirmedWrite(confirm: boolean, action: string): ToolResult | null {
  if (confirm === true) {
    return null;
  }

  return {
    isError: true,
    content: [
      {
        type: "text" as const,
        text: `Refusing to ${action} without confirm: true. Ask the user to explicitly confirm the calendar write.`
      }
    ]
  };
}

function textResult(data: unknown): ToolResult {
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(data, null, 2)
      }
    ]
  };
}

async function withToolLogging(
  action: string,
  isWrite: boolean,
  request: unknown,
  operation: () => Promise<ToolResult>
): Promise<ToolResult> {
  try {
    const result = await operation();
    await recordAction({
      action,
      status: result.isError ? "error" : "success",
      isWrite,
      request,
      response: result,
      summary: summarizeToolResult(action, result)
    });
    return result;
  } catch (error) {
    await recordAction({
      action,
      status: "error",
      isWrite,
      request,
      errorMessage: error instanceof Error ? error.message : String(error),
      summary: `${action} failed`
    });
    throw error;
  }
}

async function logBlockedTool(
  action: string,
  isWrite: boolean,
  request: unknown,
  result: ToolResult
): Promise<ToolResult> {
  await recordAction({
    action,
    status: "blocked",
    isWrite,
    request,
    response: result,
    errorCode: "missing_confirm",
    errorMessage: result.content[0]?.text,
    summary: `${action} blocked by missing confirm`
  });
  return result;
}

async function initializeStorage(): Promise<void> {
  await safeStorage(async () => {
    const dbPath = darktimeDbPath();
    mkdirSync(path.dirname(dbPath), { recursive: true });
    await sqliteExec(`
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
    `);
  });
}

async function createMatter(text: string, source: string): Promise<Record<string, unknown>> {
  const trimmed = text.trim();
  if (!trimmed) {
    throw new Error("Matter text cannot be empty.");
  }

  const id = randomUUID();
  const now = isoNow();
  await sqliteExec(`
    BEGIN TRANSACTION;
    INSERT INTO matters (
      id,
      text,
      status,
      source,
      created_at,
      updated_at,
      raw_payload_json
    ) VALUES (
      ${sqlValue(id)},
      ${sqlValue(trimmed)},
      'inbox',
      ${sqlValue(source || "mcp")},
      ${sqlValue(now)},
      ${sqlValue(now)},
      NULL
    );
    INSERT INTO matter_logs (
      matter_id,
      created_at,
      action,
      to_status,
      summary
    ) VALUES (
      ${sqlValue(id)},
      ${sqlValue(now)},
      'created',
      'inbox',
      'Captured to Inbox'
    );
    COMMIT;
  `);

  return {
    id,
    text: trimmed,
    status: "inbox",
    source: source || "mcp",
    createdAt: now,
    updatedAt: now
  };
}

async function listMatters(status: MatterStatus | undefined, limit: number): Promise<unknown[]> {
  const safeLimit = Math.max(1, Math.min(200, Math.floor(limit)));
  const where = status ? `WHERE status = ${sqlValue(status)}` : "";
  return sqliteQueryJson(`
    SELECT
      id,
      text,
      status,
      source,
      created_at AS createdAt,
      updated_at AS updatedAt,
      raw_payload_json AS rawPayloadJson
    FROM matters
    ${where}
    ORDER BY updated_at DESC
    LIMIT ${safeLimit};
  `);
}

async function updateMatterStatus(id: string, status: MatterStatus): Promise<Record<string, unknown>> {
  const rows = await sqliteQueryJson(`
    SELECT
      id,
      text,
      status,
      source,
      created_at AS createdAt,
      updated_at AS updatedAt,
      raw_payload_json AS rawPayloadJson
    FROM matters
    WHERE id = ${sqlValue(id)}
    LIMIT 1;
  `) as Array<Record<string, unknown>>;

  const current = rows[0];
  if (!current) {
    throw new Error(`Matter ${id} was not found.`);
  }

  const now = isoNow();
  await sqliteExec(`
    BEGIN TRANSACTION;
    UPDATE matters
    SET status = ${sqlValue(status)},
        updated_at = ${sqlValue(now)}
    WHERE id = ${sqlValue(id)};
    INSERT INTO matter_logs (
      matter_id,
      created_at,
      action,
      from_status,
      to_status,
      summary
    ) VALUES (
      ${sqlValue(id)},
      ${sqlValue(now)},
      'status_changed',
      ${sqlValue(String(current.status || ""))},
      ${sqlValue(status)},
      ${sqlValue(`Moved from ${String(current.status || "unknown")} to ${status}`)}
    );
    COMMIT;
  `);

  return {
    ...current,
    status,
    updatedAt: now
  };
}

async function recordSessionStarted(): Promise<void> {
  const now = isoNow();
  await safeStorage(async () => {
    await sqliteExec(`
      INSERT INTO mcp_sessions (
        id,
        client_name,
        client_version,
        transport,
        started_at,
        last_seen_at,
        last_tool_name,
        last_tool_status,
        tool_call_count
      ) VALUES (
        ${sqlValue(sessionId)},
        ${sqlValue(clientName)},
        ${sqlValue(clientVersion)},
        'stdio',
        ${sqlValue(now)},
        ${sqlValue(now)},
        'server_started',
        'started',
        0
      )
      ON CONFLICT(id) DO UPDATE SET
        last_seen_at = excluded.last_seen_at,
        last_tool_name = excluded.last_tool_name,
        last_tool_status = excluded.last_tool_status;

      INSERT INTO action_logs (
        created_at,
        session_id,
        client_name,
        source,
        action,
        status,
        is_write,
        summary
      ) VALUES (
        ${sqlValue(now)},
        ${sqlValue(sessionId)},
        ${sqlValue(clientName)},
        'mcp',
        'server_started',
        'started',
        0,
        'MCP stdio session started'
      );
    `);
  });
}

async function recordAction(input: {
  action: string;
  status: ActionStatus;
  isWrite: boolean;
  request?: unknown;
  response?: unknown;
  summary?: string;
  errorCode?: string;
  errorMessage?: string;
}): Promise<void> {
  const now = isoNow();
  await safeStorage(async () => {
    await sqliteExec(`
      INSERT INTO action_logs (
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
      ) VALUES (
        ${sqlValue(now)},
        ${sqlValue(sessionId)},
        ${sqlValue(clientName)},
        ${sqlValue(input.action.startsWith("matter_") ? "matter" : "apple_calendar")},
        ${sqlValue(input.action)},
        ${sqlValue(input.status)},
        ${input.isWrite ? 1 : 0},
        ${sqlValue(input.summary)},
        ${sqlValue(input.errorCode)},
        ${sqlValue(input.errorMessage)},
        ${sqlValue(toJson(input.request))},
        ${sqlValue(toJson(input.response))}
      );

      UPDATE mcp_sessions
      SET
        last_seen_at = ${sqlValue(now)},
        last_tool_name = ${sqlValue(input.action)},
        last_tool_status = ${sqlValue(input.status)},
        tool_call_count = tool_call_count + 1
      WHERE id = ${sqlValue(sessionId)};
    `);
  });
}

async function safeStorage(operation: () => Promise<void>): Promise<void> {
  try {
    await operation();
  } catch {
    // Observability must not break calendar operations.
  }
}

async function sqliteExec(sql: string): Promise<void> {
  const dbPath = darktimeDbPath();
  const { stdout, stderr, code } = await spawnAndCollect("sqlite3", [dbPath], sql);
  if (code !== 0) {
    throw new Error(`sqlite3 failed with code ${code}: ${stderr || stdout}`);
  }
}

async function sqliteQueryJson(sql: string): Promise<unknown[]> {
  const dbPath = darktimeDbPath();
  const { stdout, stderr, code } = await spawnAndCollect("sqlite3", ["-json", dbPath, sql]);
  if (code !== 0) {
    throw new Error(`sqlite3 query failed with code ${code}: ${stderr || stdout}`);
  }

  if (!stdout.trim()) {
    return [];
  }

  try {
    const parsed = JSON.parse(stdout);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    throw new Error(`sqlite3 returned invalid JSON: ${stdout}`);
  }
}

function darktimeDbPath(): string {
  if (process.env.DARKTIME_DB) {
    return process.env.DARKTIME_DB;
  }

  return path.join(homedir(), "Library", "Application Support", "Darktime", "darktime.sqlite3");
}

function sqlValue(value: unknown): string {
  if (value === undefined || value === null) {
    return "NULL";
  }

  return `'${String(value).replace(/'/g, "''")}'`;
}

function toJson(value: unknown): string | null {
  if (value === undefined) {
    return null;
  }

  try {
    return JSON.stringify(value);
  } catch {
    return null;
  }
}

function summarizeToolResult(action: string, result: ToolResult): string {
  const text = result.content[0]?.text ?? "";
  if (!text) {
    return `${action} completed`;
  }

  const payload = parseToolPayload(text);
  if (action === "calendar_authorization_status") {
    const record = asRecord(payload);
    const status = stringField(record, "status") ?? "unknown";
    const canReadWrite = booleanField(record, "canReadWrite") === true ? "read/write ready" : "not ready";
    return `Apple Calendar permission is ${status} (${canReadWrite})`;
  }

  if (action === "calendar_list_calendars" && Array.isArray(payload)) {
    return `Listed ${payload.length} Apple calendars`;
  }

  if (action === "calendar_list_events" && Array.isArray(payload)) {
    const nextEvent = asRecord(payload[0]);
    const nextTitle = stringField(nextEvent, "title");
    const nextStart = stringField(nextEvent, "start");
    const suffix = nextTitle && nextStart ? `; first: "${nextTitle}" at ${formatInstant(nextStart)}` : "";
    return `Listed ${payload.length} calendar events${suffix}`;
  }

  if (action === "calendar_find_free_slots" && Array.isArray(payload)) {
    return `Found ${payload.length} free calendar slots`;
  }

  if (["calendar_create_event", "calendar_update_event", "calendar_delete_event"].includes(action)) {
    const record = asRecord(payload);
    const verb = action === "calendar_create_event"
      ? "Created"
      : action === "calendar_update_event"
        ? "Updated"
        : "Deleted";
    const title = stringField(record, "title") ?? "Untitled event";
    const calendarTitle = stringField(record, "calendarTitle") ?? "Calendar";
    const start = stringField(record, "start");
    const end = stringField(record, "end");
    const range = start && end ? `, ${formatRange(start, end)}` : "";
    return `${verb} "${title}" in ${calendarTitle}${range}`;
  }

  if (action === "matter_create") {
    const record = asRecord(payload);
    const text = stringField(record, "text") ?? "Matter";
    return `Captured "${text.slice(0, 80)}" to Inbox`;
  }

  if (action === "matter_list" && Array.isArray(payload)) {
    return `Listed ${payload.length} matters`;
  }

  if (action === "matter_update_status") {
    const record = asRecord(payload);
    const text = stringField(record, "text") ?? "Matter";
    const status = stringField(record, "status") ?? "updated";
    return `Moved "${text.slice(0, 80)}" to ${status}`;
  }

  return `${action}: ${text.replace(/\s+/g, " ").slice(0, 180)}`;
}

function isoNow(): string {
  return new Date().toISOString();
}

function parseToolPayload(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }

  return value as Record<string, unknown>;
}

function stringField(record: Record<string, unknown> | null, key: string): string | null {
  const value = record?.[key];
  return typeof value === "string" && value.length > 0 ? value : null;
}

function booleanField(record: Record<string, unknown> | null, key: string): boolean | null {
  const value = record?.[key];
  return typeof value === "boolean" ? value : null;
}

function formatRange(start: string, end: string): string {
  return `${formatInstant(start)}-${formatInstant(end, { timeOnly: true })}`;
}

function formatInstant(value: string, options: { timeOnly?: boolean } = {}): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat(undefined, {
    month: options.timeOnly ? undefined : "short",
    day: options.timeOnly ? undefined : "numeric",
    hour: "2-digit",
    minute: "2-digit"
  }).format(date);
}

async function runBridge(command: string, pairs: CliPair[] = []): Promise<unknown> {
  const launcher = resolveBridgeLauncher();
  const args = [command, ...toCliArgs(pairs)];

  const { stdout, stderr, code } = launcher.kind === "app"
    ? await runAppBundle(launcher.appPath, args)
    : await spawnAndCollect(launcher.binaryPath, args);
  const response = parseBridgeResponse(stdout, stderr);

  if (!response.ok) {
    throw new Error(`[${response.error.code}] ${response.error.message}`);
  }

  if (code !== 0) {
    throw new Error(`Darktime exited with code ${code}: ${stderr || stdout}`);
  }

  return response.data;
}

function resolveBridgeLauncher(): BridgeLauncher {
  const explicitAppPath = process.env.DARKTIME_CALENDAR_APP;
  const explicitPath = process.env.DARKTIME_CALENDAR_BRIDGE;
  const appCandidates = [
    explicitAppPath,
    path.join(projectRoot, "dist", "mac", "Darktime.app"),
    path.join(projectRoot, ".build", "Darktime.app")
  ].filter(Boolean) as string[];

  const home = process.env.HOME;
  if (home) {
    appCandidates.push(path.join(home, "Applications", "Darktime.app"));
  }
  appCandidates.push(path.join("/Applications", "Darktime.app"));

  const appPath = appCandidates.find((candidate) => existsSync(candidate));
  if (appPath) {
    return { kind: "app", appPath };
  }

  const candidates = [
    explicitPath,
    path.join(projectRoot, ".build", "release", "darktime"),
    path.join(projectRoot, ".build", "debug", "darktime")
  ].filter(Boolean) as string[];

  const bridgePath = candidates.find((candidate) => existsSync(candidate));
  if (!bridgePath) {
    throw new Error(
      `Could not find Darktime. Run "npm run build:app", set DARKTIME_CALENDAR_APP, or set DARKTIME_CALENDAR_BRIDGE. Checked apps: ${appCandidates.join(", ")}. Checked binaries: ${candidates.join(", ")}`
    );
  }

  return { kind: "binary", binaryPath: bridgePath };
}

function toCliArgs(pairs: CliPair[]): string[] {
  const args: string[] = [];

  for (const [name, value] of pairs) {
    if (value === undefined || value === null) {
      continue;
    }

    args.push(`--${name}`, String(value));
  }

  return args;
}

function spawnAndCollect(command: string, args: string[], stdin?: string): Promise<{ stdout: string; stderr: string; code: number | null }> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: projectRoot,
      stdio: [stdin === undefined ? "ignore" : "pipe", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";

    child.stdout?.setEncoding("utf8");
    child.stderr?.setEncoding("utf8");

    child.stdout?.on("data", (chunk: string) => {
      stdout += chunk;
    });
    child.stderr?.on("data", (chunk: string) => {
      stderr += chunk;
    });
    child.on("error", reject);
    child.on("close", (code: number | null) => {
      resolve({ stdout, stderr, code });
    });

    if (stdin !== undefined && child.stdin) {
      child.stdin.end(stdin);
    }
  });
}

async function runAppBundle(appPath: string, args: string[]): Promise<{ stdout: string; stderr: string; code: number | null }> {
  const outputPath = path.join(tmpdir(), `darktime-calendar-${process.pid}-${randomUUID()}.json`);
  const openArgs = ["-n", appPath, "--args", ...args, "--output", outputPath];
  const result = await spawnAndCollect("open", openArgs);

  let stdout = "";
  try {
    const timeoutMs = args[0] === "request-access" ? 180_000 : 30_000;
    await waitForFile(outputPath, timeoutMs);
    stdout = readFileSync(outputPath, "utf8");
  } finally {
    rmSync(outputPath, { force: true });
  }

  return {
    stdout,
    stderr: result.stderr,
    code: result.code
  };
}

async function waitForFile(filePath: string, timeoutMs: number): Promise<void> {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    if (existsSync(filePath)) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  throw new Error(`Timed out waiting for Darktime output at ${filePath}`);
}

function parseBridgeResponse(stdout: string, stderr: string): BridgeResponse {
  try {
    return JSON.parse(stdout) as BridgeResponse;
  } catch (error) {
    throw new Error(`Darktime returned non-JSON output. stdout=${stdout} stderr=${stderr}`);
  }
}
