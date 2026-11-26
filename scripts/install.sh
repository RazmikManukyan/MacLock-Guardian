#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$HOME/.maclock-guardian"
AGENTS="$HOME/Library/LaunchAgents"
LABEL="org.maclockguardian.monitor"
CLEAN="org.maclockguardian.cleanup"
if [ "$(uname -s)" != 'Darwin' ]; then echo 'macOS only' >&2; exit 1; fi
# Avoid a second failed-unlock watcher on machines with the earlier custom setup.
if launchctl list | grep -q 'com.macsecurity.alert\|com.macsecurity.photo'; then
  echo 'Existing Mac security monitors detected. Do NOT install alongside them.' >&2
  echo 'Keep your working setup unchanged; test this project on a separate account/Mac.' >&2
  exit 1
fi
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  echo 'Already installed. Use scripts/status.sh or uninstall first.' >&2
  exit 1
fi
if [ ! -x "$ROOT/build/MacLockCamera.app/Contents/MacOS/MacLockCamera" ]; then
  echo 'First run: bash scripts/build-camera.sh' >&2; exit 1
fi
printf 'Telegram bot token (input hidden): '
IFS= read -rs TOKEN; printf '\n'
printf 'Telegram chat ID: '
IFS= read -r CHAT
case "$TOKEN" in *[!0-9A-Za-z_:\-]*|'') echo 'Invalid token format' >&2; exit 1;; esac
case "$CHAT" in ''|*[!0-9-]*) echo 'Chat ID must contain only digits or a leading minus sign' >&2; exit 1;; esac
mkdir -p "$DIR/photos" "$AGENTS"
chmod 700 "$DIR" "$DIR/photos"
cp "$ROOT/scripts/monitor.sh" "$ROOT/scripts/notify.sh" "$ROOT/scripts/cleanup.sh" "$DIR/"
chmod 700 "$DIR/monitor.sh" "$DIR/notify.sh" "$DIR/cleanup.sh"
cp -R "$ROOT/build/MacLockCamera.app" "$DIR/"
printf 'TELEGRAM_BOT_TOKEN=%q\nTELEGRAM_CHAT_ID=%q\n' "$TOKEN" "$CHAT" > "$DIR/config"
chmod 600 "$DIR/config"
# Absolute paths are provided as separate plist arguments (no shell interpolation).
/usr/bin/python3 - "$DIR" "$AGENTS" <<'PY'
import plistlib, sys, pathlib
root=pathlib.Path(sys.argv[1]); agents=pathlib.Path(sys.argv[2])
entries=[('org.maclockguardian.monitor','monitor.sh',None),('org.maclockguardian.cleanup','cleanup.sh',86400)]
for label, script, interval in entries:
    obj={'Label':label,'ProgramArguments':['/bin/bash',str(root/script)],'RunAtLoad':True,
         'StandardErrorPath':str(root/(label+'.err.log'))}
    if interval: obj['StartInterval']=interval
    else: obj['KeepAlive']=True
    with (agents/(label+'.plist')).open('wb') as f: plistlib.dump(obj,f)
PY
for label in "$LABEL" "$CLEAN"; do
  /usr/bin/plutil -lint "$AGENTS/$label.plist" >/dev/null
  /bin/launchctl bootstrap "gui/$(id -u)" "$AGENTS/$label.plist"
done
echo 'Installed. Check: bash scripts/status.sh'
echo "Mac camera permission: test the app while unlocked, then use the lock-screen test."
