#!/bin/bash
set -euo pipefail
umask 077
DIR="$HOME/.maclock-guardian"
APP="$DIR/MacLockLocation.app"
if [ ! -x "$APP/Contents/MacOS/MacLockLocation" ]; then
  echo 'Not installed. This is for a separately installed test Mac.' >&2; exit 1
fi
cat <<'TXT'
EXPERIMENTAL: When enabled, a failed unlock can transmit approximate coordinates
via your Telegram bot. On some Macs, background location is unavailable.
You must first open the Location app, request permission, and successfully test
sending a map. No guarantee of location during a locked session.
TXT
printf 'Have you tested location and explicitly consent to event-triggered sharing? (type YES): '
IFS= read -r AGREED
if [ "$AGREED" != 'YES' ]; then echo 'Cancelled, location remains unchanged.'; exit 0; fi
/usr/bin/touch "$DIR/location-enabled"
/bin/chmod 600 "$DIR/location-enabled"
echo 'Automatic location enabled for NEW events; no history or continuous tracking.'
