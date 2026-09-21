#!/bin/sh
set -e

APP_NAME="Simple Launchpad"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/SimpleLaunchpad" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$(dirname "$0")/../Sources/SimpleLaunchpad/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$(dirname "$0")/../Sources/SimpleLaunchpad/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "Built $APP_DIR"
