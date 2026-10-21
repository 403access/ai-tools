#!/usr/bin/env bash
#
# Builds OpenCodeBar and assembles a standalone macOS .app bundle in dist/.
#
# Usage:
#   Scripts/build-app.sh            # release build (default)
#   CONFIG=debug Scripts/build-app.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP_NAME="OpenCodeBar"
BUNDLE="$ROOT/dist/$APP_NAME.app"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)"

echo "==> Building $APP_NAME ($CONFIG)"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
if [ ! -x "$BIN" ]; then
    echo "error: binary not found at $BIN" >&2
    exit 1
fi

echo "==> Assembling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"

# App icon (generated once, cached in Assets/).
if [ ! -f "$ROOT/Assets/AppIcon.icns" ]; then
    echo "==> Generating app icon"
    mkdir -p "$ROOT/Assets"
    if swift "$ROOT/Scripts/make-icon.swift" "$ROOT/Assets/AppIcon.iconset"; then
        iconutil -c icns "$ROOT/Assets/AppIcon.iconset" -o "$ROOT/Assets/AppIcon.icns" || true
        rm -rf "$ROOT/Assets/AppIcon.iconset"
    fi
fi
if [ -f "$ROOT/Assets/AppIcon.icns" ]; then
    cp "$ROOT/Assets/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>OpenCodeBar</string>
    <key>CFBundleIdentifier</key>
    <string>dev.opencode.opencodebar</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>OpenCodeBar uses the microphone to dictate prompts into a session.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>OpenCodeBar turns your spoken prompt into text, on the device when the language supports it.</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>OpenCodeBar</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so the app launches cleanly without a Developer ID.
if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$BUNDLE" >/dev/null 2>&1 || echo "  (codesign skipped)"
fi

echo "==> Built $BUNDLE"
