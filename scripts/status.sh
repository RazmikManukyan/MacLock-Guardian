#!/bin/bash
set -uo pipefail
for label in org.maclockguardian.monitor org.maclockguardian.cleanup org.maclockguardian.health; do
  echo "=== $label ==="
  /bin/launchctl print "gui/$(id -u)/$label" 2>&1 | /usr/bin/grep -E 'state =|pid =|last exit code|Could not find service' || true
done
if [ -f "$HOME/.maclock-guardian/location-enabled" ]; then
  echo 'Optional failed-unlock location: ENABLED (experimental)'
else
  echo 'Optional failed-unlock location: OFF'
fi
