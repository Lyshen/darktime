# darktime

Darktime is a local calendar gateway MVP for giving local coding agents controlled access to the user's calendar.

Current MVP:

- Apple Calendar read/write through a Swift EventKit bridge.
- Local MCP server for Codex, Claude Code, and other MCP clients.
- Write operations require explicit `confirm: true` at the MCP layer.

## Local Tooling Check

This machine is ready for the MVP:

- Xcode: `16.1`
- Swift: `6.0.2`
- Node.js: `22.14.0`
- npm: `10.9.2`
- Local tools available: `swift`, `xcodebuild`, `node`, `npm`, `codesign`, `plutil`, `osascript`

## Build

```bash
npm install
npm run build:all
```

This builds:

- `.build/release/calendar-bridge`
- `.build/DarktimeCalendarBridge.app`
- `dist/mac/Darktime Calendar Bridge.app`
- `dist/mac/Darktime-Calendar-Bridge-mac.zip`
- `dist/mcp-server.js`

## Install Test Build

Build the app artifact:

```bash
npm run build:all
```

Install it for local testing:

```bash
cp -R "dist/mac/Darktime Calendar Bridge.app" /Applications/
open "/Applications/Darktime Calendar Bridge.app"
```

Opening the app with no arguments requests Calendar permission. The app is currently a helper app, so it has no visible UI after the permission flow.

## Apple Calendar Permission

Calendar permission is tied to the signed `.app` identity, not just the raw command-line binary. Use the app bundle for permission and MCP access.

Check current permission:

```bash
rm -f /tmp/darktime-auth.json
open -W .build/DarktimeCalendarBridge.app --args authorization-status --output /tmp/darktime-auth.json
cat /tmp/darktime-auth.json
```

Request permission:

```bash
rm -f /tmp/darktime-request.json
open -W .build/DarktimeCalendarBridge.app --args request-access --output /tmp/darktime-request.json
cat /tmp/darktime-request.json
```

macOS should show a Calendar permission prompt. Grant full calendar access.

## Direct Bridge Usage

List calendars:

```bash
rm -f /tmp/darktime-calendars.json
open -W .build/DarktimeCalendarBridge.app --args list-calendars --output /tmp/darktime-calendars.json
cat /tmp/darktime-calendars.json
```

List events:

```bash
rm -f /tmp/darktime-events.json
open -W .build/DarktimeCalendarBridge.app --args list-events \
  --start 2026-06-28T09:00:00+08:00 \
  --end 2026-06-28T18:00:00+08:00 \
  --output /tmp/darktime-events.json
cat /tmp/darktime-events.json
```

Create an event:

```bash
rm -f /tmp/darktime-create.json
open -W .build/DarktimeCalendarBridge.app --args create-event \
  --title "Darktime focus block" \
  --start 2026-06-28T10:00:00+08:00 \
  --end 2026-06-28T11:00:00+08:00 \
  --availability busy \
  --output /tmp/darktime-create.json
cat /tmp/darktime-create.json
```

## MCP Server

Run the local MCP server:

```bash
npm run mcp
```

MCP clients can launch:

```bash
node /Users/lyshen/Desktop/project/darktime/dist/mcp-server.js
```

The MCP server looks for the signed app in this order:

- `DARKTIME_CALENDAR_APP`
- `dist/mac/Darktime Calendar Bridge.app`
- `.build/DarktimeCalendarBridge.app`
- `~/Applications/Darktime Calendar Bridge.app`
- `/Applications/Darktime Calendar Bridge.app`

This keeps Apple Calendar TCC permission matched to the app identity.

Available tools:

- `calendar_authorization_status`
- `calendar_request_access`
- `calendar_list_calendars`
- `calendar_list_events`
- `calendar_find_free_slots`
- `calendar_create_event`
- `calendar_update_event`
- `calendar_delete_event`

Write tools require `confirm: true`.

## Design

See [docs/calendar-mvp-design.md](/Users/lyshen/Desktop/project/darktime/docs/calendar-mvp-design.md).
