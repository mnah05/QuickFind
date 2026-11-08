#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIST_DIR="$PROJECT_ROOT/dist"
STAGE_DIR="$DIST_DIR/QuickFind.app"
DMG_STAGE="$DIST_DIR/dmg-stage"

echo "==> Preparing build environment..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> Compiling Apple Silicon (arm64) binary..."
swift build --package-path "$PROJECT_ROOT" --configuration release --triple arm64-apple-macosx --scratch-path "$PROJECT_ROOT/.build/arm64"

echo "==> Compiling Intel (x86_64) binary..."
swift build --package-path "$PROJECT_ROOT" --configuration release --triple x86_64-apple-macosx --scratch-path "$PROJECT_ROOT/.build/x86_64"

ARM64_BIN="$PROJECT_ROOT/.build/arm64/out/Products/Release/QuickFind"
if [ ! -f "$ARM64_BIN" ]; then
    ARM64_BIN="$PROJECT_ROOT/.build/arm64/arm64-apple-macosx/release/QuickFind"
fi

X86_BIN="$PROJECT_ROOT/.build/x86_64/out/Products/Release/QuickFind"
if [ ! -f "$X86_BIN" ]; then
    X86_BIN="$PROJECT_ROOT/.build/x86_64/x86_64-apple-macosx/release/QuickFind"
fi

echo "==> Creating Universal Binary (arm64 + x86_64)..."
mkdir -p "$STAGE_DIR/Contents/MacOS"
mkdir -p "$STAGE_DIR/Contents/Resources"
lipo -create "$ARM64_BIN" "$X86_BIN" -output "$STAGE_DIR/Contents/MacOS/QuickFind"

echo "==> Copying App metadata and icons..."
cp "$PROJECT_ROOT/Resources/Info.plist" "$STAGE_DIR/Contents/Info.plist"
if [ -f "$PROJECT_ROOT/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$STAGE_DIR/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc signing app bundle..."
/usr/bin/codesign --force --deep --sign - "$STAGE_DIR"
/usr/bin/codesign --verify --deep --strict "$STAGE_DIR"

file "$STAGE_DIR/Contents/MacOS/QuickFind"

echo "==> Building ZIP archive..."
ditto -c -k --sequesterRsrc --keepParent "$STAGE_DIR" "$DIST_DIR/QuickFind.zip"

echo "==> Building DMG disk image..."
mkdir -p "$DMG_STAGE"
cp -R "$STAGE_DIR" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

cat << 'EOF' > "$DMG_STAGE/How to Install.txt"
QuickFind - Raycast-Style Spotlight Launcher for macOS
=====================================================

Installation:
1. Drag QuickFind.app into the Applications folder.
2. Open Applications and double-click QuickFind.
3. Use Option + Space to toggle QuickFind from anywhere.

Troubleshooting (macOS Gatekeeper):
If macOS displays an alert saying the app "cannot be opened because Apple cannot check it for malicious software" or "is damaged", right-click (or Control-click) QuickFind.app in Applications and select "Open", or run this one-line command in Terminal:
    xattr -cr /Applications/QuickFind.app
EOF

hdiutil create -volname "QuickFind" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DIST_DIR/QuickFind.dmg"
rm -rf "$DMG_STAGE"

echo "==> Release artifacts ready in $DIST_DIR:"
ls -lh "$DIST_DIR/QuickFind.dmg" "$DIST_DIR/QuickFind.zip"
shasum -a 256 "$DIST_DIR/QuickFind.dmg" "$DIST_DIR/QuickFind.zip"
