# Local Git Incremental Sync V0

## Why

Rootbox should stay responsive while local repo activity is refreshed.

The previous background worker moved git work off the main actor, but it still asked each repo for up to one year of commits every sync.

## V0 Behavior

The first sync for a local repo scans up to one year of git history.

After that, Darktime reads the newest cached `local_git / commit` trace for each root and asks git only for commits since that timestamp minus one day.

```text
no cached trace -> git log --since="1 year ago"
cached trace    -> git log --since="<latest trace time - 1 day>"
```

The one-day overlap is intentional. It makes the sync tolerant of time boundaries, while the unique `(root_id, source, external_id)` key keeps commit imports idempotent.

## Out Of Scope

- File watching.
- GitHub sync.
- Per-root diagnostics UI.
- A separate sync daemon.
