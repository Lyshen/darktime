# Darktime Product Language

Darktime is a local-first attention workspace. It is not primarily a calendar, todo app, notes app, or chatbot. Its job is to show what is taking attention, what deserves handling, what has become sustained work, and where the user actually took action.

## Core Concepts

| Concept | Definition | Boundary |
| --- | --- | --- |
| Matter | One raw piece of captured attention. | Not yet a task, plan, project, habit, or calendar event. |
| Capture | The act of putting Matter into Darktime. | Does not classify, judge, or plan; it lowers cognitive load. |
| Inbox | The temporary buffer for Matter. | Lets the user defer decisions without encouraging endless collecting. |
| Clear | The act of processing Inbox. | Reduces attention load; does not create a todo list. |
| Issue | Something worth handling. | Not a todo; can stand alone or move into a Project. |
| Project | A container for work that has entered sustained investment. | Not just an upgraded Issue; Projects create Issues and Actions. |
| Action | One real movement that already happened on an Issue or Project. | Not a plan, reminder, or todo; it must have happened. |
| Attention View | A UI aggregation of Issues, Projects, and Actions. | Not a separate business entity. |

## Flow

```text
Capture
  -> Matter
  -> Inbox
  -> Clear
      -> Dropped
      -> Done
      -> Issue
          -> Action
          -> Make Project / Link Repo
              -> Project
                  -> Issue
                  -> Action
```

The current MVP supports manual Project Issues and can import open PRs from local repos as `Issue(kind: github_pr)` through `gh` CLI. Future GitHub Issue sync will use the same Issue model.

## Key Meanings

- `Drop`: no longer worth attention, recoverable for a short period.
- `Done`: already handled, no tracking needed.
- `Issue`: worth handling, but not necessarily sustained work yet.
- `Project`: work that has truly entered sustained investment, such as a local git repo.
- `Action`: one real movement that already happened; the first MVP Action is `local_git / commit`.
- `source`: an implementation field on Action, such as `manual`, `local_git`, or `calendar`; not a top-level product concept.

## State Language

Issue:

```text
open  -> recently created or updated
stale -> not touched for a while
```

Project:

```text
alive    -> Action in the last 2 days
quiet    -> Action in the last 7 days
fading   -> Action in the last 30 days
inactive -> no Action for more than 30 days
empty    -> no Action yet
```

These states are not judgments. They only make actual attention investment visible.

## Current MVP

In:

- Capture / Inbox / Clear.
- Issue list, edit, drop, and make Project.
- Manual Project Issues.
- Local git repo Projects.
- Open PRs from local repos imported as `github_pr` Issues.
- Commits imported as Actions.
- Attention Items and Timeline.

Out:

- Project detail.
- Manual Action.
- Today planning.
- AI observer / coach.
- Automatic calendar scheduling.

## Implementation Boundary

Swift should use current product language where possible: `MatterSnapshot`, `ProjectSnapshot`, `ActionSnapshot`, `AttentionWorkspace`.

SQLite still keeps some historical table names, such as `roots` and `output_traces`, for local data compatibility. They do not define the current product language.
