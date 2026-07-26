#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AudioSwitch"
VERSION="${VERSION:-0.1.4}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AudioSwitch-notary}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
RELEASE_DIR="$ROOT_DIR/release"
STAGING_DIR="$ROOT_DIR/.build/dmg-release"
DMG_PATH="$RELEASE_DIR/${APP_NAME}-v${VERSION}-macOS-universal.dmg"

if [[ -z "$DEVELOPER_ID_APPLICATION" ]]; then
    echo "DEVELOPER_ID_APPLICATION is required." >&2
    echo "Example: Developer ID Application: Your Name (TEAMID)" >&2
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"$DEVELOPER_ID_APPLICATION\""; then
    echo "The requested Developer ID Application identity is not available in Keychain." >&2
    exit 1
fi

cd "$ROOT_DIR"
SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" VERSION="$VERSION" "$ROOT_DIR/tools/build_app.sh"

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

codesign \
    --force \
    --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" \
    "$DMG_PATH"

xcrun notarytool submit \
    "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"
(
    cd "$RELEASE_DIR"
    shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256"
)

echo "Created notarized release $DMG_PATH"
