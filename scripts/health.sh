#!/bin/bash
set -uo pipefail
umask 077
DIR="$HOME/.maclock-guardian"
STATE="$DIR/health-state"
NOW='RUNNING'
if ! /bin/launchctl print "gui/$(id -u)/org.maclockguardian.monitor" 2>/dev/null | /usr/bin/grep -q 'state = running'; then NOW='STOPPED'; fi
if [ ! -e "$STATE" ]; then
    printf '%s\n' "$NOW" > "$STATE"
    exit 0
fi
IFS= read -r BEFORE < "$STATE"
if [ "$NOW" = "$BEFORE" ]; then exit 0; fi
if [ -r "$DIR/bot-token" ] && [ -r "$DIR/chat-id" ]; then
    IFS= read -r TOKEN < "$DIR/bot-token"
    IFS= read -r CHAT < "$DIR/chat-id"
    if /usr/bin/curl -fsS --max-time 15 \
       "https://api.telegram.org/bot${TOKEN}/sendMessage" \
       --data-urlencode "chat_id=${CHAT}" \
       --data-urlencode "text=MacLock Guardian watcher changed: $BEFORE -> $NOW" \
       >/dev/null 2>&1; then
      printf '%s\n' "$NOW" > "$STATE"
    fi
fi
