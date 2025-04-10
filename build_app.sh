#!/bin/bash
# Script to build the StageWhisper app bundle

set -e # Exit on error

echo "Building StageWhisper app..."

# Build the executable
swift build -c release

# Create app bundle structure
APP_PATH="./StageWhisper.app"
CONTENTS="$APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Clean old app if it exists
if [ -d "$APP_PATH" ]; then
  rm -rf "$APP_PATH"
fi

# Create directories
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Copy executable
cp ./.build/release/StageWhisper "$MACOS/"

# Create Info.plist file directly
cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>StageWhisper</string>
    <key>CFBundleIdentifier</key>
    <string>com.yourdomain.StageWhisper</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>StageWhisper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.3</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025. All rights reserved.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>StageWhisper needs microphone access to record audio for speech recognition.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# You can also copy the compiled resources from the build directory
if [ -d ./.build/release/StageWhisper_StageWhisper.resources ]; then
  cp -R ./.build/release/StageWhisper_StageWhisper.resources/* "$RESOURCES/"
fi

echo "App bundle created at $APP_PATH"
echo "You can now run the app by double-clicking it or with:"
echo "open $APP_PATH"