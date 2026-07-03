#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_APP_PATH="$ROOT_DIR/.build/Darktime.app"
DIST_DIR="$ROOT_DIR/dist/mac"
DIST_APP_PATH="$DIST_DIR/Darktime.app"
ZIP_PATH="$DIST_DIR/Darktime-mac.zip"
ICON_PATH="$ROOT_DIR/assets/DarktimeAppIcon.icns"

bash "$ROOT_DIR/scripts/generate-app-icon.sh"
swift build -c release --package-path "$ROOT_DIR"

rm -rf \
  "$BUILD_APP_PATH" \
  "$DIST_APP_PATH" \
  "$ZIP_PATH" \
  "$DIST_DIR/Darktime Calendar Bridge.app" \
  "$DIST_DIR/Darktime-Calendar-Bridge-mac.zip"
mkdir -p "$BUILD_APP_PATH/Contents/MacOS" "$BUILD_APP_PATH/Contents/Resources" "$DIST_DIR"

cp "$ROOT_DIR/.build/release/darktime" "$BUILD_APP_PATH/Contents/MacOS/darktime"
cp "$ROOT_DIR/Sources/Darktime/Info.plist" "$BUILD_APP_PATH/Contents/Info.plist"
cp "$ICON_PATH" "$BUILD_APP_PATH/Contents/Resources/DarktimeAppIcon.icns"

codesign --force --deep --sign - "$BUILD_APP_PATH"

cp -R "$BUILD_APP_PATH" "$DIST_APP_PATH"
codesign --force --deep --sign - "$DIST_APP_PATH"

/usr/bin/ditto -c -k --keepParent "$DIST_APP_PATH" "$ZIP_PATH"

echo "Development app: $BUILD_APP_PATH"
echo "Installable app: $DIST_APP_PATH"
echo "Zip artifact: $ZIP_PATH"
