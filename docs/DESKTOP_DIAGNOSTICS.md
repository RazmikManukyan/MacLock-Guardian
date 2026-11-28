# Desktop diagnostics design — v1.2.1

## Read-only invariants

- Checks the eight **hardcoded** launchd labels using `/bin/launchctl print gui/<uid>/<label>` only.
- No `launchctl bootstrap`, `bootout`, `kickstart`, `enable`, `disable`, `load`, `unload`, `start`, `stop`, agents edits, crontab or sudo.
- Legacy `~/.mac-security/monitor.log` is accessed as a bounded, non-symlinked, regular-file read. The app never creates/modifies it, reads webcam photos, or reads bot-token files.
- The log view is **local and opt-in**, with best-effort regex redaction. It is **not a guaranteed sanitization tool**; don't post sensitive logs.
- `Copy Status` only copies fixed service labels with transient read-only states, safe to share without credential material.
- Opt-in Telegram tests use an ephemeral URL session. They transmit only when the user enters credentials and confirms. The secure field clears on send. Optional `Get Location` alone never shares the estimate.

## Semantics

- **Running**: launchctl output had a `state = running` line.
- **Loaded / idle**: launchctl output had a `state = waiting` line. Normal for some periodically scheduled LaunchAgents.
- **Loaded / inspect**: service exists, but state isn't recognized.
- **Not loaded / unavailable**: command failed. Does not necessarily prove the service is uninstalled; it might be inaccessible.
- **Check failed**: the `launchctl` process could not start.

Status counters include only Running and Loaded variants. These are registration/process checks, **not evidence that password failures are detected or messages are delivered**.

## Test procedure

1. Run `bash tests/desktop-smoke.sh` and then `bash scripts/build-desktop.sh`.
2. Open the app. Refresh; verify all 5 legacy rows match expectations; missing optional GitHub edition is normal.
3. Click Copy Status, paste in a local temporary note, verify no token/chat ID/log appears.
4. Click View Log; confirm masked token fields when present, and that log contents do not contain anything unexpected. Do not paste the full log publicly.
5. Confirm existing five live LaunchAgents remain unaffected (the GUI does not mutate them).

The code was not compiled or run on macOS in the packaging environment; users must confirm behavior locally.
