#!/bin/bash
set -euo pipefail
AGENTS="$HOME/Library/LaunchAgents"
for label in org.maclockguardian.monitor org.maclockguardian.cleanup org.maclockguardian.health; do
  /bin/launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  /bin/rm -f "$AGENTS/$label.plist"
done
echo 'Unloaded only MacLock Guardian services. Private config, logs, photos remain.'
echo 'Your pre-existing com.macsecurity.* agents were not touched.'
