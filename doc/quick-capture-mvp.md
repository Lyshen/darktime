# Quick Capture MVP

## Goal

Make capture effortless.

Quick Capture should let the user put one open loop into Darktime Inbox from any context, without turning the moment into note-taking, task planning, or organizing.

## Core Flow

```text
Control + Option + Space
-> Quick Capture appears
-> Type one messy thought
-> Enter saves to Inbox
-> Panel closes
```

## Interaction Rules

- `Control + Option + Space` opens Quick Capture.
- If Quick Capture is already open, the same shortcut focuses it.
- `Enter` saves the current draft to Inbox.
- `Shift + Enter` inserts a newline.
- `Esc` closes the panel and preserves the draft.
- Clicking outside the panel closes it and preserves the draft.
- Empty drafts cannot be saved.
- Successful save clears the draft.

## Draft

Draft persistence is part of the trust model.

If the user types something and closes the panel accidentally, Darktime should restore the draft the next time Quick Capture opens.

```text
Close without saving -> keep draft
Save successfully -> clear draft
Clear explicitly -> clear draft
```

## Out Of Scope

- Voice capture.
- Selected text capture through Accessibility permissions.
- Clipboard capture.
- AI cleanup.
- Tags, projects, dates, priorities, or Root selection.
- Full settings UI for custom shortcuts.

## Success Criteria

- Opening the panel feels instant.
- The panel does not steal more attention than needed.
- Drafts are not lost on accidental close.
- The user can create several real Inbox matters per day without thinking about structure.
