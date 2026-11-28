#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MacLockLocation.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/Info-Location.plist" "$APP/Contents/Info.plist"
clang -fno-modules -fobjc-arc -framework Cocoa -framework CoreLocation \
  "$ROOT/src/Location.m" -o "$APP/Contents/MacOS/MacLockLocation"
codesign --force --sign - "$APP"
echo 'BUILD SUCCESS: MacLockLocation.app'
echo "To authorize and test location manually: open -n '$APP'"
