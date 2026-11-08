#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_BUNDLE="$HOME/Applications/QuickFind.app"
USER_APPS_DIR="$HOME/Applications"

swift build --package-path "$PROJECT_ROOT" --configuration release
mkdir -p "$USER_APPS_DIR"
INSTALL_DIR=$(mktemp -d "$USER_APPS_DIR/.QuickFind-install.XXXXXX")
STAGED_APP="$INSTALL_DIR/QuickFind.app"
BACKUP_APP="$INSTALL_DIR/Previous.app"
mkdir -p "$STAGED_APP/Contents/MacOS"
mkdir -p "$STAGED_APP/Contents/Resources"
BIN_PATH="$PROJECT_ROOT/.build/release/QuickFind"
if [ ! -f "$BIN_PATH" ]; then
    BIN_PATH="$PROJECT_ROOT/.build/out/Products/Release/QuickFind"
fi

cp "$BIN_PATH" "$STAGED_APP/Contents/MacOS/QuickFind"
cp "$PROJECT_ROOT/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
if [ -f "$PROJECT_ROOT/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
fi
/usr/bin/codesign --force --deep --sign - "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"

killall QuickFind 2>/dev/null || true
if [ -e "$APP_BUNDLE" ]; then
    mv "$APP_BUNDLE" "$BACKUP_APP"
fi
if ! mv "$STAGED_APP" "$APP_BUNDLE"; then
    if [ -e "$BACKUP_APP" ]; then mv "$BACKUP_APP" "$APP_BUNDLE"; fi
    printf 'Could not install QuickFind; restored the previous app if available.\n' >&2
    exit 1
fi
if ! /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"; then
    mv "$APP_BUNDLE" "$STAGED_APP"
    if [ -e "$BACKUP_APP" ]; then mv "$BACKUP_APP" "$APP_BUNDLE"; fi
    printf 'The new app did not pass signature verification; restored the previous app if available.\n' >&2
    exit 1
fi

/bin/rm -rf "$BACKUP_APP"
rmdir "$INSTALL_DIR"

printf 'Built %s\n' "$APP_BUNDLE"
