#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AudioSwitch"
BUNDLE_ID="com.vigor.AudioSwitch"
VERSION="${VERSION:-0.1.4}"
BUILD_NUMBER="${BUILD_NUMBER:-9}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUILD_ROOT="$ROOT_DIR/.build/universal"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ICON_BASE="$ROOT_DIR/Support/AppIcon-base.png"
ICONSET_DIR="$ROOT_DIR/Support/AppIcon.iconset"
ICNS_PATH="$ROOT_DIR/Support/AppIcon.icns"

cd "$ROOT_DIR"

swift build \
    -c release \
    --product "$APP_NAME" \
    --triple arm64-apple-macosx13.0 \
    --scratch-path "$BUILD_ROOT/arm64"

swift build \
    -c release \
    --product "$APP_NAME" \
    --triple x86_64-apple-macosx13.0 \
    --scratch-path "$BUILD_ROOT/x86_64"

swift "$ROOT_DIR/tools/generate_app_icon.swift" "$ICON_BASE"
rm -rf "$ICONSET_DIR" "$ICNS_PATH"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_BASE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_BASE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_BASE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_BASE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_BASE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_BASE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_BASE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_BASE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_BASE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_BASE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ICNS_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"

lipo -create \
    "$BUILD_ROOT/arm64/arm64-apple-macosx/release/$APP_NAME" \
    "$BUILD_ROOT/x86_64/x86_64-apple-macosx/release/$APP_NAME" \
    -output "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign \
        --force \
        --sign - \
        --identifier "$BUNDLE_ID" \
        --requirements "=designated => identifier \"$BUNDLE_ID\"" \
        "$APP_DIR"
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGN_IDENTITY" \
        "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
lipo -info "$APP_DIR/Contents/MacOS/$APP_NAME"
echo "Built $APP_DIR"
