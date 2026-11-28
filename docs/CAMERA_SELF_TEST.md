# v1.3 Camera Self-Test — design and acceptance

## Boundaries

- `src/CameraPreview.{h,m}` implements only a video preview, with `AVCaptureVideoPreviewLayer`.
- No `AVCapturePhotoOutput`, `AVCaptureVideoDataOutput`, or file output; no microphone source.
- The desktop app only allocates a camera controller when **Open Camera Test** is clicked; the controller only begins authorization/session creation when **Start Preview** is confirmed.
- `NSCameraUsageDescription` is required in Info.plist to avoid a macOS privacy termination.
- Camera session operations occur on a serial background queue. The preview layer is attached/detached on the main thread.
- Closing or minimizing the camera test window calls `stopPreview` and invalidates pending permission/session callbacks; closing the entire app also calls `stopPreview`.
- No changes to `com.macsecurity.*` LaunchAgents, private scripts or credential files.

## What to validate on an Intel MacBook Air with macOS Sonoma 14

1. `bash tests/desktop-smoke.sh` passes.
2. `bash scripts/build-desktop.sh` finishes `BUILD SUCCESS` without new errors.
3. Opening the main app or clicking **Open Camera Test** does **not** prompt for camera permission or illuminate camera activity indicator.
4. Clicking **Start Preview** shows a separate confirmation and then macOS camera permission if not previously set.
5. Video appears within a few seconds, remains local and no new photo/video files are created by the test.
6. Clicking **Stop Preview** switches the preview off; closing or minimizing the test window also stops it, even if permission was still pending.
7. If permission is denied, show an error; do not crash or loop permission requests.
8. Existing dashboard Refresh/Copy Status/View Log and optional manual Telegram/location tests still work.
9. All five existing production LaunchAgents stay loaded and unchanged. In particular, confirm photo alerts again **after** stopping the camera preview, because competing for the same hardware may interfere temporarily.

## Known limitations

- Static checks have passed in the packaging environment; this source is **not compiled on macOS** here.
- A live preview does not test the original production camera capture path or photo delivery.
- No installer, recording, background streaming, image storage, or automatic alerts are part of this module.
- MacOS TCC privacy permissions may be affected by app bundle identifiers and code signatures during local development. If permissions behave unexpectedly, report the error without exposing secrets.
