#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$ROOT/scripts/build-desktop.sh"
python3 - "$ROOT" <<'PYTEST'
import pathlib, plistlib, re, sys
root=pathlib.Path(sys.argv[1])
with (root/'Info-Desktop.plist').open('rb') as f: meta=plistlib.load(f)
assert meta['CFBundleExecutable']=='MacLockGuardianDesktop'
assert meta['CFBundleShortVersionString']=='1.3.0'
assert 'NSCameraUsageDescription' in meta and 'NSLocationUsageDescription' in meta
app=(root/'src/Desktop.m').read_text()
camera=(root/'src/CameraPreview.m').read_text()
assert 'showStatus:' in app and 'statusMessageLabel' in app
assert 'setMessage:' not in app
assert '@selector(openCameraTest:)' in app
assert 'CameraPreviewController' in app and 'openWindow' in app
assert 'QOS_CLASS_UTILITY' in app and 'dispatch_get_main_queue' in app
assert 'copyStatus:' in app and 'redactedLogTail' in app and 'viewLog:' in app
assert 'lstat(' in app and 'S_ISREG(' in app
for agent in ('alert','photo','cleanup','health','notify'):
    assert 'com.macsecurity.'+agent in app
assert 'org.maclockguardian.monitor' in app
for code in (app,camera):
    for forbidden in (r'@"bootstrap"',r'@"bootout"',r'@"kickstart"',r'@"enable"',r'@"disable"',r'@"unload"',r'@"load"',r'@"stop"',r'@"start"'):
        assert not re.search(forbidden,code), 'Forbidden launchctl control: '+forbidden
assert 'task.arguments = @[@"print"' in app
assert 'api.telegram.org' in app
assert 'api.telegram.org' not in camera
assert 'AVCaptureVideoPreviewLayer' in camera
assert 'AVCaptureDeviceDiscoverySession' in camera
assert 'requestAccessForMediaType:AVMediaTypeVideo' in camera
assert 'authorizationStatusForMediaType:AVMediaTypeVideo' in camera
assert '[self preparePreviewForGeneration:generation]' in camera
assert 'openWindow' in camera and 'startPreview:' in camera and 'stopPreview' in camera
assert '[AVCapture' not in app  # no camera setup during main app launch
assert '[readySession startRunning]' in camera
assert '[previousSession stopRunning]' in camera
assert 'windowWillClose:' in camera and 'windowDidMiniaturize:' in camera
assert 'captureSession' in camera
for forbidden in ('AVCapturePhotoOutput','AVCaptureMovieFileOutput','AVCaptureVideoDataOutput',
                  'NSFileManager', 'writeToFile:', 'writeToURL:', 'CGImageDestination'):
    assert forbidden not in camera, 'Unexpected recording/file output: '+forbidden
build=(root/'scripts/build-desktop.sh').read_text()
assert '-framework AVFoundation' in build and '-framework QuartzCore' in build
assert 'src/CameraPreview.m' in build and 'src/Desktop.m' in build
print('PASS: v1.3 privacy keys, manual camera preview, lifecycle, diagnostics, scripts')
PYTEST
