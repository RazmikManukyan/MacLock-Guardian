#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for f in "$ROOT"/scripts/*.sh; do
    /bin/bash -n "$f"
done
/usr/bin/python3 - "$ROOT" <<'PYSMOKE'
import pathlib, plistlib, sys
root = pathlib.Path(sys.argv[1])
with (root/'Info-Location.plist').open('rb') as h:
    plist = plistlib.load(h)
assert plist['NSLocationUsageDescription']
assert (root/'src/Camera.m').exists()
assert (root/'src/Location.m').exists()
PYSMOKE
printf 'PASS: shell syntax, plist, source presence\n'
