#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build-app.sh

APP_DIR="/Applications/NightCrawler.app"
rm -rf "$APP_DIR"

mkdir -p "$APP_DIR/Contents/MacOS"
cp .build/release/NightCrawler "$APP_DIR/Contents/MacOS/NightCrawler"

cat > "$APP_DIR/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NightCrawler</string>
    <key>CFBundleIdentifier</key>
    <string>ai.thinkbasis.nightcrawler</string>
    <key>CFBundleName</key>
    <string>NightCrawler</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "Installed $APP_DIR"
open "$APP_DIR"
