#!/usr/bin/env bash
# Assemble a macOS .app bundle from the SwiftPM build output.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
BUILD_DIR="$(cd "$REPO_ROOT" && swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="$REPO_ROOT/.build/utv.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Clean previous bundle
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Copy executable
cp "$BUILD_DIR/utv" "$MACOS/utv"

# Copy resource files directly into Resources/ (flat, no bundle wrapper)
if [ -d "$BUILD_DIR/utv_utv.bundle" ]; then
    cp -R "$BUILD_DIR/utv_utv.bundle/"* "$RESOURCES/" 2>/dev/null || true
fi

# Build app icon from .iconset (no Xcode/actool needed)
ICONSET="$REPO_ROOT/AppIcon.iconset"
if [ -d "$ICONSET" ]; then
    iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
fi

# Generate Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>utv</string>
    <key>CFBundleIdentifier</key>
    <string>com.utv.app</string>
    <key>CFBundleName</key>
    <string>utv</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.entertainment</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

codesign --force --sign - \
    --entitlements "$REPO_ROOT/Sources/utv.entitlements" \
    "$APP_DIR"

echo "Bundled: $APP_DIR"
