#!/bin/bash
set -euo pipefail
AGENTS="$HOME/Library/LaunchAgents"
for label in org.maclockguardian.monitor org.maclockguardian.cleanup; do
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    rm -f "$AGENTS/$label.plist"
done
printf 'Stopped agents and removed plists.\n'
printf 'Your private config, logs and photos remain in ~/.maclock-guardian.\n'
printf 'Delete that folder manually only if you no longer need its contents.\n'
