# MacLock Guardian

**v1.1.0-alpha.1** — experimental open-source macOS security alerts (source code).

A user-session tool that looks for a failed Mac unlock, then attempts to send a Telegram text alert and webcam photo. Includes a separately authorized **manual location map test** and an **experimental, opt-in event-triggered location** option.

> **Alpha / not security audited / not independently tested end-to-end.** Do not trust it as your only protection. Prefer **Find My**, FileVault and macOS security updates for lost/stolen devices.

## Main features

- Telegram failed-unlock text alerts, with best-effort webcam photos
- One event watcher and a 30-second cooldown (can suppress distinct attempts)
- Low-light webcam capture (minimum measured brightness threshold 1/255; does not guarantee usable image)
- Manual location map from the separate location app, with your explicit confirmation
- Optional location following failed unlock: **off by default**, experimental and not guaranteed while locked
- Daily cleanup of local `attempt-*.jpg` photos after 14 days
- Health state-change warning for the event watcher every 15 minutes
- No continuous photo, audio, video or location tracking

## Supported environment

**Target:** macOS 14 Sonoma, Intel Mac initially. Other Apple Silicon and macOS releases require testing. Use only with permission on a Mac you own or administer, respecting other users' privacy.

Needs active signed-in user session, network connectivity for Telegram, and macOS privacy permissions. Does not operate while shut down or before initial FileVault sign-in; camera or location might be unavailable while locked. macOS log wording may change.

## Safe installation and testing (on a SEPARATE Mac/account)

**Important for existing users:** The installer intentionally refuses to run if it detects the older `com.macsecurity.alert`, `.photo`, `.cleanup`, `.health`, or `.notify` services. **Do not install this project alongside the five services already working on your Mac.** The repository release is intended for independent testing first.

1. Get this source repository on the test Mac. Inspect all scripts.
2. Run `bash tests/smoke.sh` (static checks).
3. Run `bash scripts/build-all.sh` (requires Apple Command Line Tools with usable Objective-C `clang`, frameworks, and `codesign`).
4. Test the camera while unlocked: `open -n -W build/MacLockCamera.app --args "$PWD/build/camera-test.jpg"`. Inspect the local photo and macOS Camera permission.
5. Open the location app while unlocked: `open -n build/MacLockLocation.app`. Approve macOS Location Services and test detection. Telegram requires installation first because credentials have not yet been configured.
6. Run `bash scripts/install.sh` to configure a **new private Telegram bot token and chat ID** for this test installation (the installer stores them in `~/.maclock-guardian` with strict permissions).
7. Open the **installed** location app `open -n ~/.maclock-guardian/MacLockLocation.app` and test location/manual Telegram again, because it has the final installed app identity.
8. Run `bash scripts/status.sh` and test a wrong-password alert while signed in. Check text, image, and health separately.
9. **Only after manual location succeeds for the installed app**, optionally run `bash scripts/enable-location.sh` and acknowledge the explicit consent prompt. Re-test one failed unlock while the lid is open and the Mac stays awake. Location failure must not affect text/photo alerts.
10. After testing run `bash scripts/disable-location.sh` to stop automatic location without altering other alerts.

To uninstall this test edition run `bash scripts/uninstall.sh`. It leaves your photos, config and logs for manual review. It never touches `com.macsecurity.*` services.

## Source tree

- `src/Camera.m` — built-in camera capture
- `src/Location.m` — manual location and experimental single-fix background mode
- `scripts/build-all.sh` — builds both local app bundles, ad-hoc signs them
- `scripts/install.sh` — configures Telegram and MacLock Guardian LaunchAgents
- `scripts/monitor.sh` — failed-unlock watcher with 30-second cooldown
- `scripts/notify.sh` — independent text/photo/optional location attempts
- `scripts/enable-location.sh`, `disable-location.sh` — explicit opt-in control
- `scripts/cleanup.sh` — removes old local failed-unlock JPEGs
- `scripts/health.sh` — health-change warnings; no spam on stable state
- `tests/smoke.sh` — shell/plist sanity tests

## Privacy and limitations

- Location coordinates and photographs **leave your Mac** when sent to Telegram. The bot and Telegram service can access that data. Use a private chat and never post credentials publicly.
- User authorization is required for camera and location. Background location may not be available despite manual success; no attempt to bypass Apple's permission system.
- `--once` location writes temporary coordinates locally, then deletes them after sending or timeout. A crash may leave a temporary file; inspect `~/.maclock-guardian` carefully if needed.
- Telegram secrets live in `~/.maclock-guardian/bot-token` and `chat-id`, not in the repository. `.gitignore` excludes common secrets, but **always inspect staged files before pushing**.
- Not a stealth-monitoring tool: no hidden surveillance, password capture or audio recording. Admin consent required for deployments to other people's devices.
- Checks run inside a signed-in user session; not a substitute for system-level theft protections.

## Roadmap

See `docs/ROADMAP.md` and `docs/RELEASE_NOTES.md`. Next major milestone is a **native setup/status graphical application**. This repo is a source preview, not a downloadable notarized `.app` for the general public.

## License

MIT — see `LICENSE`.
