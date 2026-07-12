# Background Trace Sync V0

## Why

Darktime should not block the UI while reading external systems.

Rootbox and Timeline should read local cached state. External connectors should sync traces into SQLite in the background.

The first painful example is local git:

```text
SwiftUI view opens
DashboardModel refreshes on MainActor
LocalGitRepositoryService runs git commands synchronously
UI can stay loading or feel frozen
```

Timeline makes this more obvious because it needs up to one year of commit traces.

## Principle

```text
UI reads cache.
Workers sync external traces.
Connectors never drive the visible UI directly.
```

This is enough for the early product. It avoids a full daemon/server architecture while still keeping heavy work away from SwiftUI.

## Initial Shape

```text
SwiftUI Views
  render state and send user intents

DashboardModel
  owns UI state
  starts background refreshes
  never runs slow connectors on the main actor

Use Cases
  capture matter
  move matter
  add root
  refresh traces
  build root snapshots

SQLite
  matters
  roots
  output_traces

Connectors
  local git -> output_traces
  shortcut inbox -> matters
  apple calendar -> calendar events

Background Workers
  run connector sync
  write SQLite
  publish fresh snapshots back to UI
```

## Output Trace

The shared trace shape should be local-first and source-neutral:

```text
id
root_id
source        local_git / github / manual / shortcut / calendar
kind          commit / file_change / note / event / log
external_id   commit hash or provider id
happened_at
summary
metadata_json
created_at
```

For local git, `external_id` should be the commit hash so imports are idempotent.

## V0 Scope

- Add `output_traces` table.
- Move local git commit scanning into a background task.
- Import local git commits into `output_traces`.
- Keep UI responsive while sync runs.
- Build Rootbox state and Timeline from cached traces where possible.
- Keep the existing local repo root UI behavior.

## Out Of Scope

- Separate daemon process.
- GitHub OAuth.
- File watcher.
- Manual output logs.
- Real-time sync indicators beyond a simple syncing/error state.

## Why Not A Separate Service Yet

A separate local service may be useful later, especially for MCP, background sync, and menu bar operation.

For V0, an in-process background worker is enough:

```text
less packaging complexity
less IPC complexity
easier debugging
still fixes the main UI blocking problem
```

The important boundary is not process separation yet. The important boundary is:

```text
main actor UI != slow connector work
```
