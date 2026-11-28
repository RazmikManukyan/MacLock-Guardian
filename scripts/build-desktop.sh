#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MacLockGuardianDesktop.app"
if [ "$(uname -s)" != "Darwin" ]; then
  echo 'macOS required for this AppKit build' >&2
  exit 1
fi
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/Info-Desktop.plist" "$APP/Contents/Info.plist"
/usr/bin/clang -fno-modules -fobjc-arc -Wall -Wextra -Werror=incompatible-pointer-types -mmacosx-version-min=14.0 \
  -framework AppKit -framework Foundation -framework CoreLocation \
  -framework AVFoundation -framework QuartzCore \
  "$ROOT/src/Desktop.m" "$ROOT/src/CameraPreview.m" -o "$APP/Contents/MacOS/MacLockGuardianDesktop"
/usr/bin/codesign --force --sign - "$APP"
echo "BUILD SUCCESS: $APP"
echo "Open with: open -n '$APP'"
