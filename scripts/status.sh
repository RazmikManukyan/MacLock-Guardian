#!/bin/bash
for name in org.maclockguardian.monitor org.maclockguardian.cleanup; do
  echo "--- $name ---"
  launchctl print "gui/$(id -u)/$name" 2>&1 | grep -E 'state =|pid =|last exit code|Could not find service' || true
done
