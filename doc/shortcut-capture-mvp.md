# Shortcut Capture MVP

## Purpose

Shortcut Capture lets the user send a quick thought from iPhone, Apple Watch, or Siri into Darktime without opening the Mac app.

This is not a sync system. iCloud Drive is only a drop-off point:

```text
iPhone / Siri / Apple Watch
-> Apple Shortcut writes a small file
-> iCloud Drive syncs it to the Mac
-> Darktime imports it into SQLite Inbox
-> Darktime moves the file out of the drop-off folder
```

The product promise is simple:

> Capture on your Apple devices. Clear later in Darktime on Mac.

## User Flow

### Daily Use

1. The user starts the Shortcut from iPhone:
   - Tap `Darktime` in the Shortcuts app.
   - Tap a Home Screen icon if the user added one.
   - Or say "Hey Siri, run Darktime."
2. Siri / Shortcuts asks for text or uses dictated text.
3. The shortcut saves a `.txt` file into:

   ```text
   iCloud Drive/Shortcuts/Darktime/Inbox
   ```

4. iCloud Drive syncs the file to the Mac.
5. Darktime imports the file into the local Inbox.
6. The user later opens Darktime and clears Inbox normally.

The user should not manage iCloud files during normal use.

## First-Time Setup

### Requirements

- iPhone or Apple Watch with Apple Shortcuts.
- iCloud Drive enabled for the user's Apple ID.
- Mac signed into the same Apple ID with iCloud Drive enabled.
- Darktime installed on the Mac.

### Recommended Setup

1. Open Darktime on Mac once.
2. Darktime creates the drop-off folders:

   ```text
   iCloud Drive/Shortcuts/Darktime/Inbox
   iCloud Drive/Shortcuts/Darktime/Imported
   iCloud Drive/Shortcuts/Darktime/Failed
   ```

3. The user opens `Shortcut Capture` from the Darktime app menu.
4. Darktime shows a QR code or link for the shared Apple Shortcut.
5. The user scans it with iPhone and taps `Add Shortcut`.
6. On first run, Apple Shortcuts asks for permission to save files to iCloud Drive.
7. The user runs the Shortcut once as a test.
8. Darktime imports the test capture into Inbox after iCloud syncs.

The QR code does not require a Darktime server. It only encodes Apple's shared Shortcut link, for example:

```text
https://www.icloud.com/shortcuts/...
```

### Manual Fallback

If the shared Shortcut link is not ready yet, the user can create the Shortcut manually:

1. Create a Shortcut named `Darktime`.
2. Add `Dictate Text` or `Ask for Input`.
3. Add `Save File`.
4. Save the text as a uniquely named `.txt` file into:

   ```text
   iCloud Drive/Shortcuts/Darktime/Inbox
   ```

5. Turn off `Ask Where to Save`.
6. Run it once and approve Apple's prompts.

The manual path is a fallback only. It is too complex for normal users.

## Permissions

### iPhone / Shortcuts

The Shortcut may ask for permission to save files into iCloud Drive. This permission belongs to Apple Shortcuts and Files, not Darktime.

The user may need to approve:

- Shortcuts saving a file.
- Shortcuts accessing the selected iCloud Drive folder.
- Siri running the Shortcut, if triggered by voice.

### Mac

For the current MVP, Darktime is an unsandboxed local Mac app. It reads the user's local iCloud Drive folder directly:

```text
~/Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/Darktime/Inbox
```

No iCloud API permission is required. No Apple developer iCloud container is required.

If Darktime becomes a sandboxed or Mac App Store app later, this access model must be revisited. It may require a user-selected folder, a security-scoped bookmark, or an app iCloud container.

## Data Management

iCloud Drive is transport, not storage.

Darktime should manage these folders automatically:

```text
iCloud Drive/Shortcuts/Darktime/Inbox      pending import
iCloud Drive/Shortcuts/Darktime/Imported   imported successfully
iCloud Drive/Shortcuts/Darktime/Failed     failed import
```

Import rules:

- `.txt` creates one Matter in Inbox.
- Empty files fail.
- `.json` may be supported for structured capture.
- Successful files move from `Inbox` to `Imported`.
- Failed files move from `Inbox` to `Failed`.
- SQLite is the source of truth after import.

The user should only open these folders for troubleshooting.

For compatibility, the Mac importer also watches the older root iCloud path:

```text
iCloud Drive/Darktime/Inbox
```

The recommended Shortcut path remains:

```text
iCloud Drive/Shortcuts/Darktime/Inbox
```

## Sync Expectations

iCloud Drive sync is not real-time and Darktime does not control its timing.

Expected behavior:

- Often syncs in a few seconds.
- Sometimes takes tens of seconds or a few minutes.
- May wait until the Mac is online and iCloud Drive is ready.

Product copy should avoid promising instant capture.

Recommended wording:

> Shortcut captures appear after iCloud Drive syncs.

## Shortcut Shape

### v0 Text File

The simplest Shortcut writes UTF-8 plain text.

File name:

```text
darktime-YYYYMMDD-HHMMSS.txt
```

File content:

```text
Call Alice after work about insurance
```

Darktime imports this as:

```text
status: inbox
source: shortcut
```

### Future JSON

Later, structured files can carry metadata:

```json
{
  "text": "Call Alice after work about insurance",
  "source": "shortcut",
  "captured_at": "2026-07-05T19:30:00+08:00"
}
```

## App UI

For this MVP, Darktime should expose Shortcut Capture as setup/troubleshooting, not as a main navigation item.

Possible placement:

- App menu: `Shortcut Capture`
- Capture screen secondary link: `Set up iPhone / Siri capture`

The setup view should focus on the user action:

- Scan the shared Shortcut QR code.
- Add the Shortcut on iPhone.
- Run it once and approve Apple's prompts.
- Tap the Shortcut, add it to Home Screen, or use Siri after the first successful run.

Troubleshooting should be secondary and collapsed by default:

- Drop-off folder path.
- Pending file count.
- Failed file count.
- Open Inbox / Failed folder buttons.
- Create Mac test capture button.

Do not put `Imported` into the main UI.

## Siri Behavior

Siri runs the Shortcut by name.

If the Shortcut is named `Darktime`, the user can try:

```text
Hey Siri, run Darktime
```

The exact phrase depends on Siri and the Shortcut name. The product should recommend a short, pronounceable shortcut name.

Siri should be presented as an optional convenience, not the only capture path. Tapping the Shortcut manually is the more reliable v0 path.

The Shortcut can either:

- Ask for text input.
- Dictate text.
- Accept shared text from another app.

For v0, dictation or text input is enough.

## Out Of Scope

- Native iPhone app.
- Native Apple Watch app.
- Real-time sync.
- Darktime iCloud account or hosted service.
- Editing captured items on iPhone.
- File attachment or image capture.
- Automatic ASR service outside Apple Shortcuts.
- Automatically generating Apple's shared Shortcut link from the Mac app.

## Open Questions

- What exact Shortcut name is easiest for Chinese Siri usage?
- Should `Imported` be auto-deleted after 7 days?
- Should `Failed` count appear in the app menu or setup view only?
- Should the app show the last imported Shortcut capture time?
- Should Shortcut Capture support JSON in this MVP or only `.txt`?

## Acceptance Criteria

- A user can understand what Shortcut Capture does from the setup doc/view.
- Darktime creates the iCloud drop-off folders.
- A `.txt` file saved to `iCloud Drive/Shortcuts/Darktime/Inbox` appears as a Matter in Darktime Inbox.
- Imported files are moved to `Imported`.
- Failed files are moved to `Failed`.
- The user is told that iCloud sync may not be instant.
