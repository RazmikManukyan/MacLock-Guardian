#!/bin/bash
set -euo pipefail
DIR="$HOME/.maclock-guardian/photos"
[ -d "$DIR" ] || exit 0
/usr/bin/find "$DIR" -type f -name 'attempt-*.jpg' -mtime +13 -delete
