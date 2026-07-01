# Darktime Open Loops MVP v0

## Goal

Darktime MVP v0 should become a local-first attention inbox.

The product is not a multi-calendar connector in this phase. Apple Calendar remains the trusted output layer, while Darktime owns the earlier mental loop:

```text
Capture -> Hold -> Clear -> Commit -> Review
```

The core promise:

> Darktime helps high-context people unload open loops and turn only the important ones into trusted time commitments.

## Product Position

Darktime is for people whose real context is scattered across conversations, thoughts, habits, plans, and calendar events.

This MVP should help the user:

- Capture a thought without deciding what it means immediately.
- Keep unresolved items in a quiet inbox.
- Review and clear those items intentionally.
- Commit only selected items to Apple Calendar.
- Leave low-value items parked, deferred, or dropped.

The product should feel like a calm local control surface, not a generic chatbot, task manager, or calendar clone.

## MVP Loop

### 1. Capture

The user can quickly create an open loop from the Mac app.

Each capture should store:

- Text.
- Source: `manual`, `shortcut`, `mcp`, or future source ids.
- Created time.
- Status: starts as `inbox`.
- Optional note or raw payload.

### 2. Hold

Inbox items are stored locally in SQLite.

The user does not need to classify everything at capture time. The important behavior is reducing cognitive pressure first.

### 3. Clear

The Mac app should provide a focused clearing surface.

For each item, the user can choose:

- `today`: worth attention soon.
- `later`: real, but not today.
- `done`: already handled.
- `dropped`: consciously ignored or no longer relevant.

This phase should be manual in v0. AI can be added later as an optional observer.

### 4. Commit

Selected items can be written to Apple Calendar as actual events.

Calendar events are not the inbox. They are the final commitment surface.

The user should confirm before an inbox item becomes a calendar event.

### 5. Review

The dashboard should show enough history to build trust:

- Recent captured items.
- Recent cleared items.
- Recent calendar commits.
- Recent MCP or Shortcut imports.

## Mac App Surface

The first version should be a full-screen dashboard with clear working areas:

```text
Darktime

Left rail
- Inbox
- Today
- Later
- Done
- Dropped
- Sources
- Activity

Main area
- Quick capture input
- Current list based on selected section
- Item actions: Today, Later, Done, Drop, Commit

Right inspector
- Selected item details
- Source
- Created time
- Calendar commit state
- Related activity logs
```

The app should prioritize dense, readable information over decorative cards.

## Sources

### Apple Calendar

Apple Calendar is implemented and remains the primary calendar write target.

The app should show:

- Permission state.
- Writable calendars.
- Default write target.
- Whether the selected calendar appears local-only or likely syncs through iCloud.

### Shortcuts Inbox

Shortcuts is the preferred mobile/watch capture path for MVP.

Suggested flow:

```text
iPhone / Apple Watch / Siri
-> Shortcut dictation
-> Save text or JSON file to iCloud Drive/Darktime/Inbox
-> Mac Darktime imports the file into SQLite
```

The app should support importing simple text files first.

Future JSON shape:

```json
{
  "text": "Call Alice after work about insurance",
  "source": "shortcut",
  "captured_at": "2026-07-01T18:30:00+08:00"
}
```

Do not store the SQLite database itself in iCloud Drive. Use iCloud Drive as an append-only dropbox for capture files.

### MCP

MCP remains useful for local agents.

MCP tools should allow agents to:

- Create inbox items.
- List inbox items.
- Move items between statuses.
- Commit selected items to Apple Calendar with explicit confirmation.
- Read recent activity logs.

MCP should not silently schedule or drop user commitments.

### Other Calendar Providers

Direct Google, Outlook, Feishu, DingTalk, and WeCom integrations are out of scope for this MVP.

Provider-specific OAuth and enterprise authorization should not block the core product loop.

## SQLite Storage

Use the existing shared database path:

```text
~/Library/Application Support/Darktime/darktime.sqlite3
```

Development override:

```text
DARKTIME_DB=/path/to/darktime.sqlite3
```

### New Table: `open_loops`

- `id`: UUID.
- `text`: captured text.
- `status`: `inbox`, `today`, `later`, `done`, or `dropped`.
- `source`: `manual`, `shortcut`, `mcp`, or future source id.
- `created_at`: ISO timestamp.
- `updated_at`: ISO timestamp.
- `raw_payload_json`: optional original payload.
- `scheduled_event_id`: optional Apple Calendar event id.
- `scheduled_calendar_id`: optional Apple Calendar id.
- `scheduled_start_at`: optional ISO timestamp.
- `scheduled_end_at`: optional ISO timestamp.

### New Table: `open_loop_logs`

- `id`: autoincrement integer.
- `open_loop_id`: related item id.
- `created_at`: ISO timestamp.
- `action`: `created`, `status_changed`, `committed`, `imported`, or `error`.
- `from_status`: optional previous status.
- `to_status`: optional next status.
- `summary`: human-readable summary.
- `metadata_json`: optional details.

Existing `action_logs` should continue to record MCP and calendar operations.

## Import Rules

For Shortcuts/iCloud import:

- Default folder: `~/Library/Mobile Documents/com~apple~CloudDocs/Darktime/Inbox`.
- Import `.txt` files as one inbox item per file.
- Import `.json` files when they match the supported shape.
- Move successfully imported files to `Imported`.
- Move failed files to `Failed` with an error log.
- Avoid duplicate import by file path and content hash.

## AI Boundary

AI is not required for v0.

When added later, AI should behave as a quiet observer:

- Summarize patterns only when the user asks.
- Suggest what to commit, defer, or drop.
- Ask at most one clarifying question.
- Never auto-write to calendar without confirmation.
- Use the user's own API key or local model.

## Out Of Scope

- Native iPhone or Apple Watch app.
- Hosted sync service.
- User accounts.
- Google/Outlook/Feishu/DingTalk/WeCom direct OAuth.
- Generic chatbot experience.
- Habit analytics and streak systems.
- Automatic scheduling without user confirmation.
- Team collaboration.

## Acceptance Criteria

- Google spike code is not part of this branch.
- Existing Apple Calendar read/write continues to work.
- Existing MCP server continues to run.
- App can create an inbox item manually.
- App can list and filter items by status.
- App can change item status.
- App can commit a selected item to Apple Calendar after confirmation.
- App can import at least plain text files from the Shortcuts/iCloud inbox folder.
- SQLite persists items and logs across app restarts.
- Dashboard shows recent open loop activity.
- `npm run build:all` passes.
- `npm run build:dmg` passes.

## Product Validation

The MVP is successful only if it becomes personally useful.

Seven-day dogfood target:

- Capture at least 5 real open loops per day.
- Clear the inbox at least 4 days in a week.
- Commit at least 5 important items to Apple Calendar.
- Drop at least 10 low-value items consciously.
- Feel less pressure to keep small commitments in working memory.
