#!/usr/bin/env zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/EloquentHotkey.app"
RESOURCE_DIR="$ROOT_DIR/Resources"

if ps -axo comm= | awk -v executable="$APP_DIR/Contents/MacOS/EloquentHotkey" '$0 == executable { found = 1 } END { exit !found }'; then
  print -u2 "Quit EloquentHotkey before rebuilding so macOS can verify the running app's signature."
  exit 1
fi

source "$ROOT_DIR/scripts/signing-identity.sh"
PREVIOUS_IDENTITY=""
if [[ -d "$APP_DIR" ]]; then
  PREVIOUS_IDENTITY="$(codesign -d --verbose=2 "$APP_DIR" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)"
fi
AVAILABLE_IDENTITIES="$(security find-identity -vp codesigning 2>/dev/null || true)"
SIGNING_IDENTITY="$(select_signing_identity "${CODE_SIGN_IDENTITY:-}" "$PREVIOUS_IDENTITY" "$AVAILABLE_IDENTITIES")"

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

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR" >/dev/null
  echo "Signed with $SIGNING_IDENTITY"
else
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
  echo "Warning: no stable signing identity found; fell back to ad hoc signing, which can invalidate Accessibility trust after rebuilds."
fi

echo "Built $APP_DIR"
