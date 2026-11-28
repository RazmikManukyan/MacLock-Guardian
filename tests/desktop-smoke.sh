#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$ROOT/scripts/build-desktop.sh"
python3 - "$ROOT" <<'PYTEST'
import pathlib, plistlib, re, sys
root=pathlib.Path(sys.argv[1])
with (root/'Info-Desktop.plist').open('rb') as f: meta=plistlib.load(f)
assert meta['CFBundleExecutable']=='MacLockGuardianDesktop'
assert meta['CFBundleShortVersionString']=='1.2.1'
assert 'NSLocationUsageDescription' in meta
s=(root/'src/Desktop.m').read_text()
assert 'showStatus:' in s and 'statusMessageLabel' in s
assert 'setMessage:' not in s
assert 'NSApplication sharedApplication' in s
assert 'QOS_CLASS_UTILITY' in s and 'dispatch_get_main_queue' in s
assert 'copyStatus:' in s and 'redactedLogTail' in s and 'viewLog:' in s
assert 'lstat(' in s and 'S_ISREG(' in s
for agent in ('alert','photo','cleanup','health','notify'):
    assert 'com.macsecurity.'+agent in s
assert 'org.maclockguardian.monitor' in s
for forbidden in (r'@"bootstrap"',r'@"bootout"',r'@"kickstart"',r'@"enable"',r'@"disable"',r'@"unload"',r'@"load"',r'@"stop"',r'@"start"'):
    assert not re.search(forbidden,s), 'Forbidden launchctl command: '+forbidden
assert 'task.arguments = @[@"print"' in s
assert 'api.telegram.org' in s  # the one-time manual test is retained
print('PASS: shell, plist, read-only service queries, diagnostics, GUI source checks')
PYTEST
