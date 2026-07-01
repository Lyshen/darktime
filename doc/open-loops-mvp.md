# Darktime Capture Inbox Clear Rootbox MVP v0

## Goal

Darktime MVP v0 should become a local-first attention filtering workspace.

The product is not a multi-calendar connector in this phase. The existing Apple Calendar dashboard should remain available as a secondary section, while the main app surface focuses on the earliest Darktime loop:

```text
Matter -> Capture -> Inbox -> Clear -> Rootbox
```

The core promise:

> Darktime helps high-context people capture mental clutter quickly, clear it later, and keep only what deserves to keep growing.

## Product Position

Darktime is for people whose real context is scattered across conversations, thoughts, habits, plans, and calendar events.

This MVP should help the user:

- Capture a thought without deciding what it means immediately.
- Keep unresolved Matter in a quiet inbox.
- Clear the inbox intentionally.
- Drop or defer low-value Matter.
- Move a small number of Matter into Rootbox.

The product should feel like a calm local control surface, not a generic chatbot, task manager, calendar clone, or notes app.

## MVP Loop

### 1. Capture

The user can quickly create an open loop from the Mac app.

Each capture should store:

- Text.
- Source: `manual`, `shortcut`, `mcp`, or future source ids.
- Created time.
- Status: starts as `inbox`.
- Optional note or raw payload.

### 2. Inbox

Inbox items are stored locally in SQLite.

The user does not need to classify everything at capture time. The important behavior is reducing cognitive pressure first.

### 3. Clear

The Mac app should provide a focused clearing surface.

For each Matter, the user can choose:

- `today`: worth attention soon.
- `later`: real, but not today.
- `done`: already handled.
- `dropped`: consciously ignored or no longer relevant.
- `rootbox`: worth keeping because it may grow into something valuable.

This phase should be manual in v0. AI can be added later as an optional observer.

### 4. Rootbox

Rootbox is just a box in v0.

It stores the Matter that survived Clear because the user thinks it may be worth returning to.

Rootbox v0 does not need to discover Roots, generate routines, or analyze patterns.

### 5. Review

The dashboard should show enough history to build trust:

- Recent captured items.
- Recent cleared items.
- Recent Rootbox additions.
- Recent MCP or Shortcut imports.

## Mac App Surface

The first version should be a full-screen dashboard with clear working areas:

```text
Darktime

Left rail
- Inbox
- Clear
- Rootbox
- Calendar
- Activity

Main area
- Quick capture input
- Current list or clear queue based on selected section
- Item actions: Today, Later, Done, Drop, Rootbox

Right inspector
- Selected item details
- Source
- Created time
- Related activity logs
```

The app should prioritize dense, readable information over decorative cards.

## Capture Surface

Capture should not require switching into a heavy notes interface.

MVP v0 should provide:

- A small quick capture input inside the main app.
- A global shortcut that opens a small capture panel.
- Text-only capture first.

The global panel should behave like:

```text
Shortcut -> small panel -> type one line -> Enter -> saved to Inbox -> panel disappears
```

Voice capture, image capture, Share Extension, OCR, and webpage extraction are useful but out of scope for this first cut.

## Sources

### Apple Calendar

Apple Calendar is already implemented and becomes a secondary section in the app.

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

- Create Matter in Inbox.
- List Matter by status.
- Move Matter between statuses.
- Read recent activity logs.

MCP should not silently drop or move user Matter without explicit tool calls.

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

### New Table: `matters`

- `id`: UUID.
- `text`: captured text.
- `status`: `inbox`, `today`, `later`, `done`, `dropped`, or `rootbox`.
- `source`: `manual`, `shortcut`, `mcp`, or future source id.
- `created_at`: ISO timestamp.
- `updated_at`: ISO timestamp.
- `raw_payload_json`: optional original payload.

### New Table: `matter_logs`

- `id`: autoincrement integer.
- `matter_id`: related Matter id.
- `created_at`: ISO timestamp.
- `action`: `created`, `status_changed`, `imported`, or `error`.
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
- Voice transcription.
- Image attachment processing.
- Share Extension.
- Root discovery or routine generation.

## Acceptance Criteria

- Google spike code is not part of this branch.
- Existing Apple Calendar read/write continues to work.
- Existing MCP server continues to run.
- App opens on the Capture/Inbox/Clear/Rootbox workflow, not the calendar dashboard.
- Calendar dashboard remains available as a secondary section.
- App can create a Matter manually.
- App can list and filter Matter by status.
- App can change Matter status.
- App can move selected Matter to Rootbox.
- Global quick capture can create a Matter without using the main window.
- App can import at least plain text files from the Shortcuts/iCloud inbox folder.
- SQLite persists items and logs across app restarts.
- Dashboard shows recent Matter activity.
- `npm run build:all` passes.
- `npm run build:dmg` passes.

## Product Validation

The MVP is successful only if it becomes personally useful.

Seven-day dogfood target:

- Capture at least 5 real open loops per day.
- Clear the inbox at least 4 days in a week.
- Move at least 5 genuinely valuable items into Rootbox.
- Drop at least 10 low-value items consciously.
- Feel less pressure to keep small commitments in working memory.
