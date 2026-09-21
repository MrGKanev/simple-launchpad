#!/bin/sh
set -e

# Assumes build-app-bundle.sh has already produced the .app. Packages it as
# a drag-to-Applications DMG for manual, first-time installs — the in-app
# updater (UpdateChecker.swift) keeps using the plain .zip asset, so this is
# additive, not a replacement.

APP_NAME="Simple Launchpad"
BUILD_DIR=".build/release"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "Built $DMG_PATH"
