#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AudioSwitch"
VERSION="${VERSION:-0.2.0}"
RELEASE_DIR="$ROOT_DIR/release"
STAGING_DIR="$ROOT_DIR/.build/dmg-local"
DMG_PATH="$RELEASE_DIR/${APP_NAME}-v${VERSION}-macOS-universal-local.dmg"

cd "$ROOT_DIR"
SIGN_IDENTITY=- VERSION="$VERSION" "$ROOT_DIR/tools/build_app.sh"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$RELEASE_DIR"
ditto "$ROOT_DIR/dist/$APP_NAME.app" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH" "$DMG_PATH.sha256"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
(
    cd "$RELEASE_DIR"
    shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256"
)

echo "Created local test package $DMG_PATH"
echo "This package is ad-hoc signed and is not suitable for public distribution."
