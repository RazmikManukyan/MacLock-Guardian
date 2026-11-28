#!/bin/bash
set -euo pipefail
DIR="$HOME/.maclock-guardian"
/bin/rm -f "$DIR/location-enabled"
echo 'Event-triggered location disabled. No change to monitoring or Telegram alerts.'
