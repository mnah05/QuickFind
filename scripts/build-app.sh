#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_BUNDLE="$HOME/Applications/QuickFind.app"

killall QuickFind 2>/dev/null || true

swift build --package-path "$PROJECT_ROOT" --configuration release
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
BIN_PATH="$PROJECT_ROOT/.build/release/QuickFind"
if [ ! -f "$BIN_PATH" ]; then
    BIN_PATH="$PROJECT_ROOT/.build/out/Products/Release/QuickFind"
fi

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/QuickFind"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "$PROJECT_ROOT/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"

printf 'Built %s\n' "$APP_BUNDLE"
