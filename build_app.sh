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

# Copy Info.plist
cp ./Sources/StageWhisper/Resources/Info.plist "$CONTENTS/"

# Copy Resources
cp -R ./Sources/StageWhisper/Resources/Assets.xcassets "$RESOURCES/"

echo "App bundle created at $APP_PATH"
echo "You can now run the app by double-clicking it or with:"
echo "open $APP_PATH"