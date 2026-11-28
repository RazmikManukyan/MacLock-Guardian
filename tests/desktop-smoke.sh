#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$ROOT/scripts/build-desktop.sh"
python3 - "$ROOT" <<'PY'
import pathlib, plistlib, sys
root=pathlib.Path(sys.argv[1])
with (root/'Info-Desktop.plist').open('rb') as f: data=plistlib.load(f)
assert data['CFBundleExecutable']=='MacLockGuardianDesktop'
assert 'NSLocationUsageDescription' in data
source=(root/'src/Desktop.m').read_text()
assert 'launchAndReturnError' in source
assert 'sendTelegramMethod' in source
assert 'NSApplication sharedApplication' in source
assert 'launchctl bootstrap' not in source
assert 'launchctl bootout' not in source
assert 'com.macsecurity.alert' in source
assert 'org.maclockguardian.monitor' in source
print('PASS: desktop plist, shell syntax, and expected source hooks')
PY
