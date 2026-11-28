# v1.1.0-alpha.1 — Source preview

## Changes since v0.1
- Includes Objective-C low-light webcam capture based on limited user testing.
- Adds a separate MacLockLocation.app with an explicit foreground permission workflow and one-time manual Telegram map test.
- Adds **experimental** failed-unlock location sharing, **disabled by default** and enabled with explicit user consent.
- Location checks reject stale or very inaccurate fixes and never log coordinates.
- Monitors Telegram alerts with a single watcher, a cooldown and fallback when photo/location fail.
- Adds scheduled local photo cleanup and a health state-change alert.
- Adds `tests/smoke.sh` and an installer guard against pre-existing `com.macsecurity.*` services.

## Validation
- Linux-based shell syntax and static tests were run; the macOS binary source must be compiled/tested on macOS.
- One Mac running Sonoma has previously demonstrated the underlying camera and manually-triggered location features in separate prototypes, **not** this integrated release.
- **No end-to-end v1.1 integration testing has been performed on an independent Mac.**

## Security notes
- Not security-audited; not a replacement for Find My or FileVault.
- Never publish Telegram tokens, private chat IDs, coordinates or photo files.
- Uses macOS user-session log events that may vary across versions.
- Camera and background location depend on privacy permission and may fail while locked.
- No automatic location until explicit opt-in.
