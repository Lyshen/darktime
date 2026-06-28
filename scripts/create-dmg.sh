#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/mac"
APP_PATH="$DIST_DIR/Darktime Calendar Bridge.app"
STAGING_DIR="$ROOT_DIR/.build/dmg/Darktime Calendar Bridge"
DMG_PATH="$DIST_DIR/Darktime-Calendar-Bridge-mac.dmg"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle at $APP_PATH. Run npm run build:all first." >&2
  exit 1
fi

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

/usr/bin/hdiutil create \
  -volname "Darktime Calendar Bridge" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "DMG artifact: $DMG_PATH"
