#!/bin/bash
set -uo pipefail
umask 077
DIR="$HOME/.maclock-guardian"
LOG="$DIR/monitor.log"
LOCK="$DIR/last-event"
# Fail-closed for spam: cooldown suppresses bursts, including genuine attempts.
# Do not run a separate monitor alongside this one.
while true; do
  /usr/bin/log stream --style compact --info \
    --predicate 'process == "loginwindow" AND eventMessage CONTAINS[c] "INCORRECT password"' 2>>"$LOG" |
  while IFS= read -r line; do
    case "$line" in
      *'INCORRECT password'*)
        now=$(date +%s)
        previous=0
        if [ -r "$LOCK" ]; then read -r previous < "$LOCK" || previous=0; fi
        case "$previous" in ''|*[!0-9]*) previous=0;; esac
        if (( now - previous >= 30 )); then
          printf '%s\n' "$now" > "$LOCK"
          "$DIR/notify.sh" >>"$LOG" 2>&1 &
        fi
        ;;
    esac
  done
  echo "$(date): log stream disconnected; retrying" >> "$LOG"
  sleep 5
done
