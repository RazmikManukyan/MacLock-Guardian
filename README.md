# MacLock Guardian

**Open-source macOS failed-unlock alerts to Telegram, with an optional webcam photo.**

> **Early prototype / not audited.** Adapted from a setup manually tested on one Intel MacBook running macOS Sonoma 14. The repository version has **not yet been tested end-to-end on another Mac**. Do not rely on it as your only security measure.

## Features

- Watches macOS `loginwindow` logs for the phrase `INCORRECT password`.
- Sends a Telegram text alert; optionally captures a camera frame and sends the photo.
- Waits for camera warm-up and uses a permissive low-light brightness check (which does not reliably reject black images).
- Uses 30-second event cooldown to reduce bursts (this can also suppress distinct attempts).
- Automatically deletes generated photos older than 14 days.
- Runs as user-level `launchd` agents; requires no third-party runtime libraries beyond native macOS frameworks, shell, and system developer tools to compile.
- Stores Telegram credentials in a local file with restrictive permissions, excluded from Git.

## Supported environment and limitations

- **Prototype tested on:** Intel MacBook Air, macOS Sonoma 14. Other machines/OS versions need verification.
- The low-light brightness filter is provisional. A clear photo on one Mac does not guarantee it will reject black frames or work in every environment.
- Requires a local, signed/ad-hoc-signed camera app and explicit **Camera** privacy permission in macOS Settings.
- Intended for **your own Mac**, with informed consent from anyone using the camera-equipped machine.
- Does not bypass camera privacy controls. On some Macs the camera is unavailable at the lock screen; this can produce no photo even when text alerts work.
- Requires a **logged-in user session**; not active at FileVault initial login, when off, or reliably during sleep.
- `loginwindow` logging format can change after macOS updates. Detection is best effort.
- Internet required for Telegram messages; Telegram is an external service, so sent photos leave your Mac and are subject to its policies.
- No protection from malware/admin tampering or password theft; use FileVault and Find My Mac.

## Before installing

**If you already run `com.macsecurity.alert` / `com.macsecurity.photo`**, do not install this prototype alongside them: you could receive duplicate messages. Its installer detects those services and stops. Test on a different Mac or separate macOS account first.

Create a bot using [@BotFather](https://t.me/BotFather). Start a private chat with the bot and obtain your numeric chat ID through Telegram's bot API (`getUpdates`) or another trustworthy method. **Never post your bot token or chat ID in screenshots, issues, repositories, or chat messages.**

## Build and test on a separate test Mac

1. Download the repository (as ZIP) or clone it.
2. Open Terminal in the extracted project folder.
3. Run `bash scripts/build-camera.sh` (requires Apple Command Line Tools and a working `clang`).
4. Test camera **while unlocked**: `open -W build/MacLockCamera.app --args "$PWD/build/test.jpg"`. Approve Camera permission. Check `build/test.jpg` locally.
5. Run `bash scripts/install.sh` and enter your **own** Telegram bot token and chat ID. Credentials are stored only in `~/.maclock-guardian/config`, not in the repo.
6. Check `bash scripts/status.sh`.
7. Lock the Mac (`Control+Command+Q`), enter one wrong password, then unlock. Verify text and photograph separately. Test again after reboot and login.

For extra safety, test in a non-primary account and review the source before installing. No `sudo` or system daemon is needed.

## Uninstall

Run `bash scripts/uninstall.sh`. It stops **only** the `org.maclockguardian.*` agents created by this project. Local photos, logs and configuration are **kept** for your review. Manually delete `~/.maclock-guardian` if no longer needed.

## Technical design

`log stream` → one `monitor.sh` watcher → `notify.sh` → Telegram text → authorized `MacLockCamera.app` → Telegram photo.

The second agent runs daily cleanup. A single watcher avoids having two separate log-stream processes for notifications; event cooldown applies to both text and camera alerts together.

## Security and privacy

- The camera is enabled only for failed-unlock event handling; no continuous recording.
- Camera permission is requested normally by macOS.
- Do not commit secrets or personal photos. `.gitignore` excludes common sensitive files; **review `git status` before every push**.
- Photos are kept locally for 14 days unless manually removed. Telegram copies are not deleted automatically.
- Telegram bots should be private; rotate any token accidentally published.
- Local logs may include diagnostic information. Do not upload them without review.

## Project status

**v0.1 alpha**: source prepared for review and community testing; not yet independently validated or published. Contributions and reproducible issues welcome. Please include your macOS version and architecture but **never secrets or personal images**.

## License

MIT. See `LICENSE`.
