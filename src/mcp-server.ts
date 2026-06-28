#!/usr/bin/env node

import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
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

const moduleDir = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(moduleDir, "..");

const server = new McpServer({
  name: "darktime-calendar",
  version: "0.1.0"
});

server.registerTool(
  "calendar_authorization_status",
  {
    title: "Calendar Authorization Status",
    description: "Check whether the local Darktime bridge has full Apple Calendar read/write access.",
    inputSchema: {}
  },
  async () => textResult(await runBridge("authorization-status"))
);

server.registerTool(
  "calendar_request_access",
  {
    title: "Request Calendar Access",
    description: "Ask macOS to grant full Apple Calendar access to the local Darktime bridge. This may show a system permission prompt.",
    inputSchema: {}
  },
  async () => textResult(await runBridge("request-access"))
);

server.registerTool(
  "calendar_list_calendars",
  {
    title: "List Calendars",
    description: "List Apple calendars visible to this Mac through EventKit.",
    inputSchema: {}
  },
  async () => textResult(await runBridge("list-calendars"))
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
    textResult(await runBridge("list-events", [
      ["start", start],
      ["end", end],
      ["calendar-id", calendarId]
    ]))
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
    textResult(await runBridge("find-free-slots", [
      ["start", start],
      ["end", end],
      ["duration-minutes", durationMinutes],
      ["calendar-id", calendarId]
    ]))
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
    const confirmation = requireConfirmedWrite(confirm, "create a calendar event");
    if (confirmation) return confirmation;

    return textResult(await runBridge("create-event", [
      ["title", title],
      ["start", start],
      ["end", end],
      ["calendar-id", calendarId],
      ["notes", notes],
      ["location", location],
      ["url", url],
      ["availability", availability]
    ]));
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
    const confirmation = requireConfirmedWrite(confirm, "update a calendar event");
    if (confirmation) return confirmation;

    return textResult(await runBridge("update-event", [
      ["event-id", eventId],
      ["title", title],
      ["start", start],
      ["end", end],
      ["calendar-id", calendarId],
      ["notes", notes],
      ["location", location],
      ["url", url],
      ["availability", availability]
    ]));
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
    const confirmation = requireConfirmedWrite(confirm, "delete a calendar event");
    if (confirmation) return confirmation;

    return textResult(await runBridge("delete-event", [
      ["event-id", eventId]
    ]));
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);

function requireConfirmedWrite(confirm: boolean, action: string) {
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

function textResult(data: unknown) {
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(data, null, 2)
      }
    ]
  };
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
    throw new Error(`calendar-bridge exited with code ${code}: ${stderr || stdout}`);
  }

  return response.data;
}

function resolveBridgeLauncher(): BridgeLauncher {
  const explicitAppPath = process.env.DARKTIME_CALENDAR_APP;
  const explicitPath = process.env.DARKTIME_CALENDAR_BRIDGE;
  const appCandidates = [
    explicitAppPath,
    path.join(projectRoot, ".build", "DarktimeCalendarBridge.app")
  ].filter(Boolean) as string[];

  const appPath = appCandidates.find((candidate) => existsSync(candidate));
  if (appPath) {
    return { kind: "app", appPath };
  }

  const candidates = [
    explicitPath,
    path.join(projectRoot, ".build", "release", "calendar-bridge"),
    path.join(projectRoot, ".build", "debug", "calendar-bridge")
  ].filter(Boolean) as string[];

  const bridgePath = candidates.find((candidate) => existsSync(candidate));
  if (!bridgePath) {
    throw new Error(
      `Could not find calendar bridge. Run "npm run build:app", set DARKTIME_CALENDAR_APP, or set DARKTIME_CALENDAR_BRIDGE. Checked apps: ${appCandidates.join(", ")}. Checked binaries: ${candidates.join(", ")}`
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

function spawnAndCollect(command: string, args: string[]): Promise<{ stdout: string; stderr: string; code: number | null }> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd: projectRoot,
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");

    child.stdout.on("data", (chunk: string) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk: string) => {
      stderr += chunk;
    });
    child.on("error", reject);
    child.on("close", (code: number | null) => {
      resolve({ stdout, stderr, code });
    });
  });
}

async function runAppBundle(appPath: string, args: string[]): Promise<{ stdout: string; stderr: string; code: number | null }> {
  const outputPath = path.join(tmpdir(), `darktime-calendar-${process.pid}-${randomUUID()}.json`);
  const openArgs = ["-W", appPath, "--args", ...args, "--output", outputPath];
  const result = await spawnAndCollect("open", openArgs);

  let stdout = "";
  try {
    await waitForFile(outputPath, 30_000);
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

  throw new Error(`Timed out waiting for calendar bridge output at ${filePath}`);
}

function parseBridgeResponse(stdout: string, stderr: string): BridgeResponse {
  try {
    return JSON.parse(stdout) as BridgeResponse;
  } catch (error) {
    throw new Error(`calendar-bridge returned non-JSON output. stdout=${stdout} stderr=${stderr}`);
  }
}
