#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MacLockCamera.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.maclockguardian.camera</string>
<key>CFBundleExecutable</key><string>MacLockCamera</string>
<key>CFBundleName</key><string>MacLockCamera</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSCameraUsageDescription</key><string>Take a photo after a failed unlock attempt, with your permission.</string>
</dict></plist>
PLIST
clang -fno-modules -fobjc-arc -framework Foundation -framework AVFoundation -framework AppKit -framework CoreImage -framework CoreMedia "$ROOT/src/Camera.m" -o "$APP/Contents/MacOS/MacLockCamera"
codesign --force --sign - "$APP"
echo "Built: $APP"
echo "Test while unlocked: open -W '$APP' --args '$ROOT/build/test.jpg'"
