#!/bin/bash
# Publish source preview to the intended GitHub repository. Does not touch local security agents.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/Documents/MacLock-Guardian-v11-Publish"
URL='https://github.com/RazmikManukyan/MacLock-Guardian.git'

if [ -e "$DEST" ]; then
  echo "STOP: $DEST already exists. No files were changed." >&2
  echo 'Review or rename that directory manually before retrying.' >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo 'Git is not installed.' >&2; exit 1
fi
if command -v gh >/dev/null 2>&1; then
  if ! gh auth status >/dev/null 2>&1; then
    echo 'Run gh auth login before publishing.' >&2; exit 1
  fi
  gh auth setup-git
fi
bash "$ROOT/tests/smoke.sh"
mkdir -p "$HOME/Documents"
git clone "$URL" "$DEST"
# Copy source only (do not include runtime private folders or build outputs).
cp -R "$ROOT/README.md" "$ROOT/CONTRIBUTING.md" "$ROOT/LICENSE" \
      "$ROOT/VERSION" "$ROOT/.gitignore" "$ROOT/Info-Location.plist" "$DEST/"
cp -R "$ROOT/src" "$ROOT/scripts" "$ROOT/tests" "$ROOT/docs" "$DEST/"
cd "$DEST"
git add -- README.md CONTRIBUTING.md LICENSE VERSION .gitignore Info-Location.plist src scripts tests docs
git diff --cached --check
printf '\n=== Source files about to be committed ===\n'
git status --short
printf '\nONLY project source should be listed. If not, enter anything other than PUBLISH.\n'
printf 'Type PUBLISH to commit and push to GitHub: '
IFS= read -r ANSWER
if [ "$ANSWER" != 'PUBLISH' ]; then
  echo 'Cancelled: no GitHub commit or push. Review staging in the isolated clone.'
  exit 0
fi
if ! git config user.email >/dev/null || ! git config user.name >/dev/null; then
  echo 'Git author name/email not configured. Set them in this clone and retry manually.' >&2
  exit 1
fi
if git diff --cached --quiet; then
  echo 'Nothing new to commit.'
  exit 0
fi
git commit -m 'MacLock Guardian v1.1 alpha: opt-in location and reliability'
git branch -M main
git push -u origin main
echo 'Push completed. Open https://github.com/RazmikManukyan/MacLock-Guardian'
