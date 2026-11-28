#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$HOME/.maclock-guardian"
AGENTS="$HOME/Library/LaunchAgents"
if [ "$(uname -s)" != 'Darwin' ]; then echo 'macOS only' >&2; exit 1; fi
# Installation must NEVER disturb the original five services.
if /bin/launchctl list | /usr/bin/grep -Eq 'com\.macsecurity\.(alert|photo|cleanup|health|notify)'; then
  echo 'Existing com.macsecurity services detected. Installation blocked to prevent duplicate alerts.' >&2
  echo 'Test on a different macOS account or Mac. Your existing services were not modified.' >&2
  exit 1
fi
if /bin/launchctl print "gui/$(id -u)/org.maclockguardian.monitor" >/dev/null 2>&1; then
  echo 'Already installed. See scripts/status.sh' >&2
  exit 1
fi
for app in MacLockCamera MacLockLocation; do
  if [ ! -x "$ROOT/build/$app.app/Contents/MacOS/$app" ]; then
    echo "Missing $app build. First run bash scripts/build-all.sh" >&2
    exit 1
  fi
done
printf 'Telegram bot token (hidden): '
IFS= read -rs TOKEN; printf '\n'
printf 'Telegram private chat ID: '
IFS= read -r CHAT
case "$TOKEN" in ''|*[!0-9A-Za-z_:\-]*) echo 'Invalid token' >&2; exit 1;; esac
case "$CHAT" in ''|*[!0-9-]*) echo 'Numeric chat ID required' >&2; exit 1;; esac
mkdir -p "$DIR/photos" "$AGENTS"
chmod 700 "$DIR" "$DIR/photos"
for script in monitor notify cleanup health; do
  cp "$ROOT/scripts/$script.sh" "$DIR/$script.sh"
  chmod 700 "$DIR/$script.sh"
done
for app in MacLockCamera MacLockLocation; do
  /usr/bin/ditto "$ROOT/build/$app.app" "$DIR/$app.app"
done
printf '%s\n' "$TOKEN" > "$DIR/bot-token"
printf '%s\n' "$CHAT" > "$DIR/chat-id"
chmod 600 "$DIR/bot-token" "$DIR/chat-id"
# Location after failed unlock remains OFF until the user runs enable-location.sh
/usr/bin/python3 - "$DIR" "$AGENTS" <<'PYPLIST'
import pathlib, plistlib, sys
root = pathlib.Path(sys.argv[1]); agents = pathlib.Path(sys.argv[2])
entries = [('org.maclockguardian.monitor', 'monitor.sh', 'keepalive'),
           ('org.maclockguardian.cleanup', 'cleanup.sh', 86400),
           ('org.maclockguardian.health', 'health.sh', 900)]
for label, script, schedule in entries:
    item = dict(Label=label, ProgramArguments=['/bin/bash',str(root/script)],
                RunAtLoad=True, StandardErrorPath=str(root/(label+'.err.log')))
    if schedule == 'keepalive': item['KeepAlive'] = True
    else: item['StartInterval'] = schedule
    with (agents/(label+'.plist')).open('wb') as handle:
        plistlib.dump(item, handle)
PYPLIST
for label in org.maclockguardian.monitor org.maclockguardian.cleanup org.maclockguardian.health; do
  /usr/bin/plutil -lint "$AGENTS/$label.plist" >/dev/null
  /bin/launchctl bootstrap "gui/$(id -u)" "$AGENTS/$label.plist"
done
printf 'Installed v1.1 preview. Auto location is OFF by default.\n'
printf 'Authorize camera/location in an unlocked user session, then test.\n'
printf 'Do not modify any of your prior com.macsecurity services.\n'
