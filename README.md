# Darktime

Darktime is a local-first macOS workspace for capturing attention, clearing open loops, and seeing which projects are actually receiving action.

Current MVP:

- Capture: in-app text capture and global Quick Capture.
- Inbox and Clear: lightweight triage from raw Matter into Issue, Done, or Dropped.
- Attention: local repo Projects, project Issues, and git commit Actions.
- Today: a daily focus view for selected Issues and today's Actions.
- Shortcut Capture: iCloud Drive folder import for iPhone, Mac, and Apple Watch Shortcuts.
- Apple Calendar and local MCP tools as secondary integrations.
- SQLite local storage. User data stays on the machine unless the user chooses iCloud Drive for Shortcut Capture.

## Build

```bash
npm install
npm run build:all
```

This builds:

- `.build/release/darktime`
- `.build/Darktime.app`
- `dist/mac/Darktime.app`
- `dist/mac/Darktime-mac.zip`
- `dist/mcp-server.js`

Build a local DMG:

```bash
npm run build:dmg
```

This creates:

- `dist/mac/Darktime-mac.dmg`

## Install Test Build

```bash
npm run build:all
cp -R "dist/mac/Darktime.app" /Applications/
open "/Applications/Darktime.app"
```

## Storage

Darktime stores local data in SQLite:

```text
~/Library/Application Support/Darktime/darktime.sqlite3
```

For development, override the path:

```bash
DARKTIME_DB=/tmp/darktime.sqlite3 npm run mcp
```

Shortcut Capture imports from the user's iCloud Drive. The primary location is the Shortcuts app container:

```text
~/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/Darktime/Inbox
```

Darktime also watches this compatibility location:

```text
~/Library/Mobile Documents/com~apple~CloudDocs/Darktime/Inbox
```

Files imported by the Mac app are moved to `Imported`; failed imports go to `Failed`.

## MCP Server

Run the local MCP server:

```bash
npm run build
npm run mcp
```

MCP clients can launch:

```bash
node /Users/lyshen/Desktop/project/darktime/dist/mcp-server.js
```

The MCP server looks for the signed app in this order:

- `DARKTIME_APP`
- `dist/mac/Darktime.app`
- `.build/Darktime.app`
- `~/Applications/Darktime.app`
- `/Applications/Darktime.app`

Available Matter tools:

- `matter_create`
- `matter_list`
- `matter_update_status`

Available Apple Calendar tools:

- `calendar_authorization_status`
- `calendar_request_access`
- `calendar_list_calendars`
- `calendar_list_events`
- `calendar_find_free_slots`
- `calendar_create_event`
- `calendar_update_event`
- `calendar_delete_event`

Calendar write tools require `confirm: true`.

## Direct Calendar Commands

Calendar permission is tied to the signed `.app` identity. Use the app bundle for permission and MCP access.

Check current permission:

```bash
rm -f /tmp/darktime-auth.json
open -W .build/Darktime.app --args authorization-status --output /tmp/darktime-auth.json
cat /tmp/darktime-auth.json
```

Request permission:

```bash
rm -f /tmp/darktime-request.json
open -W .build/Darktime.app --args request-access --output /tmp/darktime-request.json
cat /tmp/darktime-request.json
```

List events:

```bash
rm -f /tmp/darktime-events.json
open -W .build/Darktime.app --args list-events \
  --start 2026-06-28T09:00:00+08:00 \
  --end 2026-06-28T18:00:00+08:00 \
  --output /tmp/darktime-events.json
cat /tmp/darktime-events.json
```

Create an event:

```bash
rm -f /tmp/darktime-create.json
open -W .build/Darktime.app --args create-event \
  --title "Darktime focus block" \
  --start 2026-06-28T10:00:00+08:00 \
  --end 2026-06-28T11:00:00+08:00 \
  --availability busy \
  --output /tmp/darktime-create.json
cat /tmp/darktime-create.json
```

## GitHub Release Build

The repository includes `.github/workflows/build-mac.yml`.

- Push to `main`: build the macOS app and upload `.app`, `.zip`, and `.dmg` as workflow artifacts.
- Run manually from Actions: build the same downloadable artifacts.
- Push a version tag like `v0.1.0`: create/update the GitHub Release and attach the `.dmg` and `.zip`.

## Product Language

- [Chinese](/Users/lyshen/Desktop/project/darktime/doc/product-language-cn.md)
- [English](/Users/lyshen/Desktop/project/darktime/doc/product-language-en.md)
