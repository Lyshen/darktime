# Darktime Open Loops MVP v0

本文件描述当前 MVP 的实现边界。正式产品语言见 [domain-language-v0.md](domain-language-v0.md)。

## Goal

Darktime MVP v0 should become a local-first attention workspace.

The main product loop is:

```text
Capture -> Inbox -> Clear -> Issue / Done / Dropped
Issue -> Project
Project -> Output Trace
Attention View -> Issues + Projects + Timeline
```

Apple Calendar remains available as a secondary utility surface. It is not the core product loop.

## Product Position

Darktime is for people whose real context is scattered across thoughts, conversations, projects, local files, calendars, and devices.

This MVP should help the user:

- Capture mental clutter quickly.
- Let raw Matter sit in Inbox without immediate classification.
- Clear Inbox intentionally.
- Keep only selected Matter as Issue.
- Turn a meaningful Issue into a Project when it needs sustained output.
- See whether Projects are actually receiving output.

The product should feel like a calm local control surface, not a generic chatbot, task manager, calendar clone, or notes app.

## MVP Loop

### 1. Capture

Capture creates a Matter.

Each capture stores:

- Text.
- Source: `manual`, `shortcut`, `mcp`, or future source ids.
- Created time.
- Status: starts as `inbox`.
- Optional raw payload.

### 2. Inbox

Inbox is the buffer for raw Matter.

The user should not need to classify everything at capture time.

### 3. Clear

Clear is the decision action.

For each Matter, the user can choose:

- `done`: already handled.
- `dropped`: consciously ignored or no longer relevant.
- `issue`: worth attention, but not necessarily a long-running project yet.

This phase is manual in v0. AI can be added later as an optional observer.

### 4. Issue

Issue is the first committed unit of attention.

It means the Matter deserves handling, action, or continued observation.

### 5. Project

Project is a sustained attention container.

The first supported Project source is a local git repository. An Issue can also become a Project by linking a local repo.

### 6. Output Trace

Output Trace is evidence that something actually happened.

The first supported trace source is:

```text
local_git / commit
```

### 7. Attention View

Attention View is a UI aggregation, not a separate entity.

It shows:

```text
active Issues
Projects
Project output timeline
```

## Mac App Surface

```text
Left rail
- Capture
- Inbox
- Attention

Attention
- Items: Projects + Issues
- Timeline: project output distribution
```

Calendar, Shortcut Capture, Dropped, and MCP setup can remain available through secondary surfaces or menus.

## Sources

### Shortcut Capture

Shortcut capture is the preferred mobile/watch input path for MVP:

```text
iPhone / Apple Watch / Siri
-> Shortcut dictation
-> Save text file to iCloud Drive/Darktime/Inbox
-> Mac Darktime imports the file into SQLite
```

Do not store the SQLite database itself in iCloud Drive. Use iCloud Drive as an append-only inbox for capture files.

### MCP

MCP remains useful for local agents.

MCP tools should allow agents to:

- Create Matter in Inbox.
- List Matter by status.
- Move Matter between statuses.

Agents should not silently drop or move user Matter without explicit tool calls.

## SQLite Storage

Use:

```text
~/Library/Application Support/Darktime/darktime.sqlite3
```

Main tables:

- `matters`: raw captures, inbox items, issues, done, dropped.
- `matter_logs`: status history.
- `roots`: legacy storage table backing current Project records.
- `output_traces`: output evidence linked to a Project.

Current Matter statuses:

```text
inbox
issue
done
dropped
today
later
```

`today` and `later` are legacy statuses kept for compatibility. They are not part of the current primary Clear flow.

## Out Of Scope

- Native iPhone or Apple Watch app.
- Hosted sync service.
- User accounts.
- Direct Google/Outlook/Feishu/DingTalk/WeCom OAuth.
- Generic chatbot experience.
- Today planning.
- Project detail.
- Issue decomposition.
- Manual output logs.
- AI observer.
- Automatic scheduling.
