#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build-app.sh

APP_DIR="/Applications/NightCrawler.app"
rm -rf "$APP_DIR"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp .build/release/NightCrawler "$APP_DIR/Contents/MacOS/NightCrawler"
cp -R .build/release/NightCrawler_NightCrawler.bundle "$APP_DIR/NightCrawler_NightCrawler.bundle"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "Installed $APP_DIR"
open "$APP_DIR"
