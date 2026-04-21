#!/usr/bin/env zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/EloquentHotkey.app"
RESOURCE_DIR="$ROOT_DIR/Resources"

SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"

cd "$ROOT_DIR"
swift build -c release --jobs 1
BUILD_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$ROOT_DIR/App/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BUILD_DIR/EloquentHotkey" "$APP_DIR/Contents/MacOS/EloquentHotkey"

if [[ -d "$RESOURCE_DIR" ]]; then
  cp -R "$RESOURCE_DIR/." "$APP_DIR/Contents/Resources/"
fi

if [[ -f "$RESOURCE_DIR/AppIcon-1024.png" ]]; then
  ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET_DIR"

  render_icon() {
    local pixels="$1"
    local output_name="$2"
    sips -s format png -z "$pixels" "$pixels" \
      "$RESOURCE_DIR/AppIcon-1024.png" \
      --out "$ICONSET_DIR/$output_name" >/dev/null
  }

  render_icon 16 icon_16x16.png
  render_icon 32 icon_16x16@2x.png
  render_icon 32 icon_32x32.png
  render_icon 64 icon_32x32@2x.png
  render_icon 128 icon_128x128.png
  render_icon 256 icon_128x128@2x.png
  render_icon 256 icon_256x256.png
  render_icon 512 icon_256x256@2x.png
  render_icon 512 icon_512x512.png
  render_icon 1024 icon_512x512@2x.png

  iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
  rm -rf "$(dirname "$ICONSET_DIR")"
fi

chmod +x "$APP_DIR/Contents/MacOS/EloquentHotkey"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(
    security find-identity -vp codesigning 2>/dev/null |
      sed -n 's/.*"\(.*\)"/\1/p' |
      head -n 1
  )"
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR" >/dev/null
  echo "Signed with $SIGNING_IDENTITY"
else
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
  echo "Warning: no stable signing identity found; fell back to ad hoc signing, which can invalidate Accessibility trust after rebuilds."
fi

echo "Built $APP_DIR"
