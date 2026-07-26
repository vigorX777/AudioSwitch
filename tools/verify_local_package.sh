#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DMG_PATH="${1:-$ROOT_DIR/release/AudioSwitch-v0.1.4-macOS-universal-local.dmg}"
MOUNT_DIR="$(mktemp -d /tmp/AudioSwitch-verify.XXXXXX)"

cleanup() {
    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
APP_PATH="$MOUNT_DIR/AudioSwitch.app"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
lipo -info "$APP_PATH/Contents/MacOS/AudioSwitch"
plutil -lint "$APP_PATH/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP_PATH/Contents/Info.plist")" = "true"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" = "com.vigor.AudioSwitch"

echo "Local package verification passed: $DMG_PATH"
