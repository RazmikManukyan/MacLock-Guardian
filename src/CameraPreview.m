// MacLock Guardian v1.3 camera self-test.
// Standalone, user-initiated AVFoundation video preview only:
// NO photo/video recording, NO microphone, NO network, NO disk writes,
// NO change to the five existing Mac security monitoring agents.
#import "CameraPreview.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

static NSTextField *CameraLabel(NSString *text, NSRect frame, CGFloat size, BOOL bold) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    label.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    return label;
}

static NSButton *CameraButton(NSString *title, NSRect frame, id target, SEL action) {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.target = target;
    button.action = action;
    return button;
}

@interface CameraPreviewController ()
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSView *previewContainer;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSButton *startButton;
@property(nonatomic, strong) NSButton *stopButton;
@property(nonatomic, strong) AVCaptureSession *captureSession;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, strong) dispatch_queue_t captureQueue;
@property(nonatomic) NSUInteger requestGeneration;
@property(nonatomic) BOOL wantsPreview;
@end

@implementation CameraPreviewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _captureQueue = dispatch_queue_create("org.maclockguardian.preview.camera", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)status:(NSString *)value {
    self.statusLabel.stringValue = value ?: @"";
}

- (void)openWindow {
    NSAssert([NSThread isMainThread], @"Camera test window must be used on the main thread");
    if (!self.window) {
        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 550)
            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
            backing:NSBackingStoreBuffered defer:NO];
        self.window.title = @"MacLock Guardian — Manual Camera Self-Test v1.3";
        self.window.delegate = self;
        NSView *content = self.window.contentView;
        [content addSubview:CameraLabel(@"Camera self-test", NSMakeRect(20, 507, 520, 29), 21, YES)];
        NSTextField *description = CameraLabel(
            @"Preview is OFF by default. No photos, video, audio or coordinates are saved or sent.",
            NSMakeRect(20, 482, 725, 20), 12, NO);
        description.textColor = [NSColor secondaryLabelColor];
        [content addSubview:description];

        self.previewContainer = [[NSView alloc] initWithFrame:NSMakeRect(20, 91, 720, 374)];
        self.previewContainer.wantsLayer = YES;
        self.previewContainer.layer.backgroundColor = [NSColor blackColor].CGColor;
        [content addSubview:self.previewContainer];

        self.startButton = CameraButton(@"Start Preview", NSMakeRect(20, 52, 160, 30),
                                        self, @selector(startPreview:));
        self.stopButton = CameraButton(@"Stop Preview", NSMakeRect(190, 52, 160, 30),
                                       self, @selector(stopButtonClicked:));
        self.stopButton.enabled = NO;
        [content addSubview:self.startButton];
        [content addSubview:self.stopButton];

        self.statusLabel = CameraLabel(@"Camera idle. Click Start Preview to request access.",
                                       NSMakeRect(363, 50, 377, 34), 12, NO);
        self.statusLabel.lineBreakMode = NSLineBreakByWordWrapping;
        self.statusLabel.maximumNumberOfLines = 2;
        [content addSubview:self.statusLabel];
        NSTextField *note = CameraLabel(
            @"Note: using the camera for this test can temporarily compete with live photo alerts.",
            NSMakeRect(20, 14, 725, 24), 11, NO);
        note.textColor = [NSColor secondaryLabelColor];
        [content addSubview:note];
        [self.window center];
    }
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    // Opening this window does not start a camera session or prompt for permission.
}

- (void)startPreview:(id)sender {
    (void)sender;
    if (self.wantsPreview) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Start a local camera preview?";
    alert.informativeText =
        @"This temporarily opens your Mac's camera and may compete with live webcam alerts. "
        @"No image is saved, transmitted, or uploaded. Click Stop Preview or close this window to stop.";
    [alert addButtonWithTitle:@"Start Preview"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    self.wantsPreview = YES;
    self.requestGeneration++;
    NSUInteger generation = self.requestGeneration;
    self.startButton.enabled = NO;
    self.stopButton.enabled = YES;

    AVAuthorizationStatus auth = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (auth == AVAuthorizationStatusAuthorized) {
        [self status:@"Camera authorized. Preparing preview..."];
        [self preparePreviewForGeneration:generation];
    } else if (auth == AVAuthorizationStatusNotDetermined) {
        [self status:@"Waiting for macOS camera permission. No image is saved."];
        __weak typeof(self) weakSelf = self;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                CameraPreviewController *strongSelf = weakSelf;
                if (!strongSelf || !strongSelf.wantsPreview ||
                    strongSelf.requestGeneration != generation) return;
                if (!granted) {
                    [strongSelf stopPreview];
                    [strongSelf status:@"Camera permission denied. Enable it in System Settings > Privacy & Security > Camera."];
                    return;
                }
                [strongSelf status:@"Permission granted. Preparing preview..."];
                [strongSelf preparePreviewForGeneration:generation];
            });
        }];
    } else {
        [self stopPreview];
        [self status:@"Camera access denied or restricted. Check System Settings > Privacy & Security > Camera."];
    }
}

// Hardware setup and startRunning never block the AppKit main thread.
- (void)preparePreviewForGeneration:(NSUInteger)generation {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.captureQueue, ^{
        AVCaptureDeviceDiscoverySession *discovery =
            [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[
                AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeExternal]
                mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
        AVCaptureDevice *camera = discovery.devices.firstObject;
        NSString *failure = nil;
        AVCaptureSession *session = nil;
        if (!camera) {
            failure = @"No compatible camera found. Check whether another app has exclusive access.";
        } else {
            NSError *error = nil;
            AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
            if (!input) {
                failure = [NSString stringWithFormat:@"Could not open camera input (error %ld).",
                           (long)error.code];
            } else {
                session = [[AVCaptureSession alloc] init];
                if ([session canSetSessionPreset:AVCaptureSessionPreset640x480]) {
                    session.sessionPreset = AVCaptureSessionPreset640x480;
                }
                if (![session canAddInput:input]) {
                    failure = @"The selected camera cannot be attached to a preview session.";
                    session = nil;
                } else {
                    [session addInput:input];  // video input only; NO recording outputs
                }
            }
        }

        AVCaptureSession *readySession = session;
        NSString *reason = failure;
        dispatch_async(dispatch_get_main_queue(), ^{
            CameraPreviewController *strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.wantsPreview ||
                strongSelf.requestGeneration != generation || !strongSelf.window.isVisible) return;
            if (!readySession) {
                [strongSelf stopPreview];
                [strongSelf status:reason ?: @"Camera could not be initialized."];
                return;
            }
            strongSelf.captureSession = readySession;
            AVCaptureVideoPreviewLayer *layer = [AVCaptureVideoPreviewLayer layerWithSession:readySession];
            layer.videoGravity = AVLayerVideoGravityResizeAspect;
            layer.frame = strongSelf.previewContainer.bounds;
            layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
            [strongSelf.previewContainer.layer addSublayer:layer];
            strongSelf.previewLayer = layer;
            [strongSelf status:@"Starting video-only preview..."];

            dispatch_async(strongSelf.captureQueue, ^{
                [readySession startRunning];
                BOOL running = readySession.isRunning;
                dispatch_async(dispatch_get_main_queue(), ^{
                    CameraPreviewController *owner = weakSelf;
                    if (!owner || owner.requestGeneration != generation || !owner.wantsPreview) {
                        // Stop Preview invalidates this generation and queues stopRunning
                        // on the same serial queue that ran startRunning.
                        return;
                    }
                    if (!running) {
                        [owner stopPreview];
                        [owner status:@"Camera preview could not start. Check camera availability."];
                    } else {
                        [owner status:@"Preview ACTIVE — local video only. Stop or close when finished."];
                    }
                });
            });
        });
    });
}

- (void)stopButtonClicked:(id)sender {
    (void)sender;
    [self stopPreview];
}

- (void)stopPreview {
    self.wantsPreview = NO;
    self.requestGeneration++;
    NSUInteger stoppedGeneration = self.requestGeneration;
    self.stopButton.enabled = NO;
    [self.previewLayer removeFromSuperlayer];
    self.previewLayer = nil;
    AVCaptureSession *previousSession = self.captureSession;
    self.captureSession = nil;
    self.startButton.enabled = previousSession == nil;
    if (previousSession) {
        [self status:@"Stopping camera..."];
        __weak typeof(self) weakSelf = self;
        dispatch_async(self.captureQueue, ^{
            if (previousSession.isRunning) [previousSession stopRunning];
            dispatch_async(dispatch_get_main_queue(), ^{
                CameraPreviewController *owner = weakSelf;
                if (!owner || owner.requestGeneration != stoppedGeneration) return;
                owner.startButton.enabled = YES;
                [owner status:@"Camera stopped. No images were saved or sent."];
            });
        });
    } else {
        [self status:@"Preview stopped. No images were saved or sent."];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    [self stopPreview];
}

- (void)windowDidMiniaturize:(NSNotification *)notification {
    (void)notification;
    [self stopPreview];
}

@end
