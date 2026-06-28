#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/DarktimeCalendarBridge.app"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"

cp "$ROOT_DIR/.build/release/calendar-bridge" "$APP_PATH/Contents/MacOS/calendar-bridge"
cp "$ROOT_DIR/Sources/CalendarBridge/Info.plist" "$APP_PATH/Contents/Info.plist"

codesign --force --deep --sign - "$APP_PATH"

echo "$APP_PATH"
