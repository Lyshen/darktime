#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"
ICONSET_DIR="$ASSETS_DIR/DarktimeAppIcon.iconset"
PREVIEW_PNG="$ASSETS_DIR/darktime-logo.png"
ICNS_PATH="$ASSETS_DIR/DarktimeAppIcon.icns"

mkdir -p "$ASSETS_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

/usr/bin/swift "$ROOT_DIR/scripts/render-logo.swift" "$PREVIEW_PNG"

/usr/bin/sips -z 16 16 "$PREVIEW_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
/usr/bin/sips -z 32 32 "$PREVIEW_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
/usr/bin/sips -z 32 32 "$PREVIEW_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
/usr/bin/sips -z 64 64 "$PREVIEW_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
/usr/bin/sips -z 128 128 "$PREVIEW_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
/usr/bin/sips -z 256 256 "$PREVIEW_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
/usr/bin/sips -z 256 256 "$PREVIEW_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
/usr/bin/sips -z 512 512 "$PREVIEW_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
/usr/bin/sips -z 512 512 "$PREVIEW_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
/usr/bin/sips -z 1024 1024 "$PREVIEW_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Logo PNG: $PREVIEW_PNG"
echo "App icon: $ICNS_PATH"
