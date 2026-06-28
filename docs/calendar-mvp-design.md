# Darktime Calendar MVP Design

## Goal

Build a local calendar gateway that lets local coding agents, including Codex and Claude Code, read and write the user's calendar through a single controlled interface.

The first MVP focuses on Apple Calendar on this Mac:

- Read calendars and events through Apple EventKit.
- Create, update, and delete Apple Calendar events.
- Expose the capability through a local MCP server.
- Keep calendar provider credentials and write permissions out of agent prompts.

## Why This Shape

Skills are good for repeatable agent workflows: when to check the calendar, how to summarize a day, how to propose focus blocks, and how to ask for confirmation.

MCP is the better boundary for live private data and actions. It lets Codex, Claude Code, and other local agents call a local tool without each agent owning calendar credentials or direct provider SDKs.

For MVP, Apple Calendar is the fastest integration path because it can already aggregate iCloud, Google, Exchange, and other calendars configured in macOS Calendar.app. Later provider-specific APIs can fill gaps where Apple Calendar sync is incomplete.

## Architecture

```text
Apple Calendar.app / macOS calendar accounts
                  |
                  v
Swift CalendarBridge executable
  - EventKit authorization
  - Calendar/event read operations
  - Event create/update/delete operations
  - Normalized JSON output
                  |
                  v
TypeScript MCP server over stdio
  - Tool schemas
  - Safety confirmation for writes
  - Stable local agent interface
                  |
                  v
Codex / Claude Code / other MCP clients
```

## MVP Tool Surface

The Swift bridge exposes command-line operations that return JSON:

- `authorization-status`
- `request-access`
- `list-calendars`
- `list-events`
- `create-event`
- `update-event`
- `delete-event`
- `find-free-slots`

The MCP server exposes matching tools:

- `calendar_authorization_status`
- `calendar_request_access`
- `calendar_list_calendars`
- `calendar_list_events`
- `calendar_create_event`
- `calendar_update_event`
- `calendar_delete_event`
- `calendar_find_free_slots`

Write tools require `confirm: true` at the MCP layer. This keeps accidental writes from happening when an agent is merely drafting a plan.

## Local Permission Model

Apple Calendar access is controlled by macOS privacy/TCC:

- The bridge embeds calendar usage strings in its executable Info.plist.
- The release build is wrapped in `DarktimeCalendarBridge.app` because macOS Calendar/TCC permission is bound to the signed app identity.
- On macOS 14+, the bridge requests full calendar access with EventKit's full-access API.
- The user grants or denies access through the system permission prompt.
- If access is denied or not yet granted, read/write operations fail with an actionable error.

The MCP server does not store Apple Calendar credentials. It only launches the local bridge.

## Normalized Event Model

MVP event JSON uses a provider-neutral shape so future Google, Outlook, Feishu, and WeCom integrations can fit behind the same MCP tools:

```json
{
  "provider": "apple",
  "eventId": "...",
  "calendarId": "...",
  "calendarTitle": "Work",
  "title": "Customer call",
  "start": "2026-06-28T09:00:00.000+08:00",
  "end": "2026-06-28T09:30:00.000+08:00",
  "allDay": false,
  "availability": "busy",
  "location": "Zoom",
  "notes": "...",
  "url": "https://..."
}
```

## Future Provider Expansion

After Apple Calendar works, add direct provider connectors behind the same normalized model:

- Google Calendar API for Google-native fields, attendees, Meet links, and domain behavior.
- Microsoft Graph for Outlook and Exchange calendars.
- Feishu Calendar API for Feishu-native tenant calendars.
- WeCom calendar APIs where enterprise app authorization is available.

Provider-specific connectors should live behind a local app/service authorization layer. Agents should continue to call the same MCP tools.

## First-Version Limitations

- The first bridge is a local helper executable, not a polished menu bar app.
- Recurring events are listed as expanded EventKit occurrences, but update/delete defaults to `.thisEvent`.
- Attendee management and meeting-room fields are not part of MVP.
- Provider-specific meeting links and enterprise policy behavior may require direct provider APIs later.
- The MCP server is stdio-based and intended to be launched by an MCP client.

## Development Checks

Required local tools:

- Xcode command-line tools or Xcode.
- Swift toolchain.
- Node.js and npm.
- `codesign` for local ad-hoc signing if needed by macOS privacy behavior.

## Run Flow

Build the bridge:

```bash
npm run build:app
```

Install Node dependencies and build the MCP server:

```bash
npm install
npm run build
```

Check authorization:

```bash
open -W .build/DarktimeCalendarBridge.app --args authorization-status --output /tmp/darktime-auth.json
cat /tmp/darktime-auth.json
```

Request calendar access:

```bash
open -W .build/DarktimeCalendarBridge.app --args request-access --output /tmp/darktime-request.json
cat /tmp/darktime-request.json
```

Run the MCP server:

```bash
npm run mcp
```

MCP clients can point to:

```bash
node /absolute/path/to/darktime/dist/mcp-server.js
```
