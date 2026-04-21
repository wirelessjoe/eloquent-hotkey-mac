#!/usr/bin/env zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/EloquentHotkey.app"

cd "$ROOT_DIR"
swift build -c release --jobs 1
BUILD_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$ROOT_DIR/App/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BUILD_DIR/EloquentHotkey" "$APP_DIR/Contents/MacOS/EloquentHotkey"

chmod +x "$APP_DIR/Contents/MacOS/EloquentHotkey"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
