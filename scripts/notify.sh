#!/bin/bash
# Sends one text alert, an optional camera image, and experimental opt-in location.
set -uo pipefail
umask 077
DIR="$HOME/.maclock-guardian"
TOKEN_FILE="$DIR/bot-token"; CHAT_FILE="$DIR/chat-id"
[ -r "$TOKEN_FILE" ] && [ -r "$CHAT_FILE" ] || exit 1
IFS= read -r BOT_TOKEN < "$TOKEN_FILE"
IFS= read -r CHAT_ID < "$CHAT_FILE"
[ -n "$BOT_TOKEN" ] && [ -n "$CHAT_ID" ] || exit 1
BASE="https://api.telegram.org/bot${BOT_TOKEN}"
TEXT='MacLock Guardian: incorrect unlock password detected'
# Always attempt text; failure of photo/location must never suppress text.
if ! /usr/bin/curl -fsS --retry 1 --max-time 20 "$BASE/sendMessage" \
    --data-urlencode "chat_id=$CHAT_ID" --data-urlencode "text=$TEXT" >/dev/null 2>&1; then
    echo "$(date): ERROR Telegram text send failed" >&2
fi
APP="$DIR/MacLockCamera.app"
PHOTO="$DIR/photos/attempt-$(date +%s)-$$.jpg"
if [ -x "$APP/Contents/MacOS/MacLockCamera" ]; then
  /usr/bin/open -n -W "$APP" --args "$PHOTO" >/dev/null 2>&1 &
  starter=$!
  for ((i=0;i<16;i++)); do
    [ -s "$PHOTO" ] && break
    sleep 1
  done
  if kill -0 "$starter" 2>/dev/null; then kill "$starter" 2>/dev/null || true; fi
  wait "$starter" 2>/dev/null || true
  if [ -s "$PHOTO" ]; then
    /bin/chmod 600 "$PHOTO"
    if ! /usr/bin/curl -fsS --retry 1 --max-time 20 "$BASE/sendPhoto" \
      -F "chat_id=$CHAT_ID" -F 'caption=MacLock Guardian failed-unlock photo' \
      -F "photo=@$PHOTO" >/dev/null 2>&1; then
        echo "$(date): ERROR Telegram photo upload failed" >&2
    fi
  else
    echo "$(date): Camera did not save usable photo" >&2
  fi
fi
# Opt-in experimental location; never prompt for authorization in background.
if [ -f "$DIR/location-enabled" ] && [ -x "$DIR/MacLockLocation.app/Contents/MacOS/MacLockLocation" ]; then
  TEMP=$(/usr/bin/mktemp "$DIR/location.XXXXXXXX") || exit 1
  /usr/bin/open -n "$DIR/MacLockLocation.app" --args --once "$TEMP" >/dev/null 2>&1 || true
  for ((i=0;i<15;i++)); do
    [ -s "$TEMP" ] && break
    sleep 1
  done
  if [ -s "$TEMP" ]; then
    IFS=' ' read -r LAT LON ACC < "$TEMP" || true
    # Strict numeric checks. Never interpolate untrusted content as executable code.
    if [[ "${LAT:-}" =~ ^-?[0-9]+(\.[0-9]+)?$ && "${LON:-}" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
      if ! /usr/bin/curl -fsS --retry 1 --max-time 20 "$BASE/sendLocation" \
          --data-urlencode "chat_id=$CHAT_ID" \
          --data-urlencode "latitude=$LAT" \
          --data-urlencode "longitude=$LON" >/dev/null 2>&1; then
        echo "$(date): ERROR Telegram map upload failed" >&2
      fi
    else
      echo "$(date): Invalid location coordinates rejected" >&2
    fi
  else
    echo "$(date): Location unavailable at failed unlock (no map sent)" >&2
  fi
  /bin/rm -f "$TEMP"
fi
