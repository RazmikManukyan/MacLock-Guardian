// MacLock Guardian v1.3 desktop camera self-test — macOS 14+
// AppKit GUI; READ-ONLY monitor status. No LaunchAgents are modified.
// Telegram and location actions require a deliberate button click and confirmation.
#import <Cocoa/Cocoa.h>
#import "CameraPreview.h"
#import <CoreLocation/CoreLocation.h>
#include <math.h>
#include <unistd.h>
#include <sys/stat.h>

static NSTextField *MakeLabel(NSString *value, NSRect frame, CGFloat fontSize, BOOL bold) {
    NSTextField *field = [NSTextField labelWithString:value];
    field.frame = frame;
    field.font = bold ? [NSFont boldSystemFontOfSize:fontSize] : [NSFont systemFontOfSize:fontSize];
    return field;
}

static NSButton *MakeButton(NSString *title, NSRect frame, id target, SEL action) {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.target = target;
    button.action = action;
    return button;
}

@interface DesktopController : NSObject <NSApplicationDelegate, CLLocationManagerDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *statusMessageLabel;
@property(nonatomic, strong) NSTextField *summaryLabel;
@property(nonatomic, strong) NSMutableArray<NSButton *> *refreshButtons;
@property(nonatomic, strong) NSArray<NSString *> *serviceStatuses;
@property(nonatomic, strong) NSWindow *logWindow;
@property(nonatomic, strong) CameraPreviewController *cameraPreview;
@property(nonatomic) BOOL refreshInProgress;
@property(nonatomic, strong) NSTextField *chatField;
@property(nonatomic, strong) NSSecureTextField *tokenField;
@property(nonatomic, strong) NSArray<NSString *> *serviceIDs;
@property(nonatomic, strong) NSMutableArray<NSTextField *> *serviceStatusLabels;
@property(nonatomic, strong) CLLocationManager *locationManager;
@property(nonatomic, strong) CLLocation *lastLocation;
@property(nonatomic, strong) NSButton *mapButton;
@property(nonatomic) BOOL requestingLocation;
@property(nonatomic) BOOL sending;
@end

@implementation DesktopController

- (void)showStatus:(NSString *)value {
    self.statusMessageLabel.stringValue = value ?: @"";
}

// Only checks the launchd registration/status. No control commands are executed.
// Run this method off the main thread so unresponsive launchctl cannot freeze the GUI.
- (NSString *)statusForService:(NSString *)identifier {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/launchctl";
    task.arguments = @[@"print", [NSString stringWithFormat:@"gui/%u/%@", (unsigned int)getuid(), identifier]];
    NSPipe *output = [NSPipe pipe];
    task.standardOutput = output;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) return @"Check failed";
    NSData *data = [[output fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) return @"Not loaded / unavailable";
    NSString *details = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    // Look for exact launchctl state lines, rather than arbitrary substring matches.
    NSRegularExpression *running = [NSRegularExpression regularExpressionWithPattern:
        @"(?m)^\\s*state = running\\s*$" options:0 error:NULL];
    NSRegularExpression *waiting = [NSRegularExpression regularExpressionWithPattern:
        @"(?m)^\\s*state = waiting\\s*$" options:0 error:NULL];
    NSRange full = NSMakeRange(0, details.length);
    if ([running firstMatchInString:details options:0 range:full]) return @"Running";
    if ([waiting firstMatchInString:details options:0 range:full]) return @"Loaded / idle";
    return @"Loaded / inspect";
}

- (void)refresh:(id)sender {
    (void)sender;
    if (self.refreshInProgress) return;
    self.refreshInProgress = YES;
    for (NSButton *button in self.refreshButtons) button.enabled = NO;
    for (NSTextField *field in self.serviceStatusLabels) {
        field.stringValue = @"Checking...";
        field.textColor = [NSColor secondaryLabelColor];
    }
    self.summaryLabel.stringValue = @"Checking service registrations...";
    NSArray<NSString *> *identifiers = [self.serviceIDs copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableArray<NSString *> *results = [NSMutableArray arrayWithCapacity:identifiers.count];
        for (NSString *identifier in identifiers) {
            [results addObject:[self statusForService:identifier]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.serviceStatuses = [results copy];
            NSUInteger legacyLoaded = 0, editionLoaded = 0;
            for (NSUInteger index = 0; index < results.count; index++) {
                NSString *status = results[index];
                NSTextField *field = self.serviceStatusLabels[index];
                field.stringValue = status;
                BOOL loaded = [status isEqualToString:@"Running"] || [status hasPrefix:@"Loaded"];
                if (loaded) {
                    if (index < 5) legacyLoaded++; else editionLoaded++;
                }
                field.textColor = [status isEqualToString:@"Running"] ? [NSColor systemGreenColor] :
                    [status hasPrefix:@"Loaded"] ? [NSColor systemOrangeColor] :
                    [NSColor secondaryLabelColor];
            }
            NSDateFormatter *clock = [[NSDateFormatter alloc] init];
            clock.dateStyle = NSDateFormatterNoStyle;
            clock.timeStyle = NSDateFormatterMediumStyle;
            self.summaryLabel.stringValue = [NSString stringWithFormat:
                @"Legacy: %lu/5 loaded   ·   GitHub edition: %lu/3 loaded   ·   Checked %@",
                (unsigned long)legacyLoaded, (unsigned long)editionLoaded,
                [clock stringFromDate:[NSDate date]]];
            self.refreshInProgress = NO;
            for (NSButton *button in self.refreshButtons) button.enabled = YES;
            [self showStatus:@"Registration check complete. Loaded/running does not prove that alert delivery works."];
        });
    });
}

- (void)copyStatus:(id)sender {
    (void)sender;
    if (self.refreshInProgress || self.serviceStatuses.count != self.serviceIDs.count) {
        [self showStatus:@"Refresh the service statuses first. Nothing copied."];
        return;
    }
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:
        @"MacLock Guardian v1.3 — read-only service registrations (not a delivery test)"];
    for (NSUInteger index = 0; index < self.serviceIDs.count; index++) {
        [lines addObject:[NSString stringWithFormat:@"%@: %@",
            self.serviceIDs[index], self.serviceStatuses[index]]];
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:[lines componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];
    [self showStatus:@"Copied service labels and states only. No bot token, chat ID, photos or logs included."];
}

// Read a fixed, bounded tail of the existing local log; do not create or modify it.
// Redaction is best effort: never publish the displayed log without reviewing it.
- (NSString *)redactedLogTail {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".mac-security/monitor.log"];
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0 || !S_ISREG(st.st_mode)) {
        return @"No regular legacy monitor.log was found. Nothing was changed.";
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return @"Cannot read the existing monitor.log. Nothing was changed.";
    @try {
        unsigned long long length = [handle seekToEndOfFile];
        [handle seekToFileOffset:(length > 65536 ? length - 65536 : 0)];
        NSData *data = [handle readDataToEndOfFile];
        NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!value) value = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (!value) return @"Log data cannot be displayed as text.";
        NSArray<NSString *> *lines = [value componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSUInteger start = lines.count > 100 ? lines.count - 100 : 0;
        NSString *tail = [[lines subarrayWithRange:NSMakeRange(start, lines.count - start)] componentsJoinedByString:@"\n"];
        NSArray<NSArray<NSString *> *> *patterns = @[
          @[@"https?://api\\.telegram\\.org/bot[0-9]+:[A-Za-z0-9_-]+", @"[REDACTED TELEGRAM URL]"],
          @[@"[0-9]{5,}:[A-Za-z0-9_-]{16,}", @"[REDACTED TOKEN]"],
          @[@"(?i)(chat[_-]?id\\s*[=:]\\s*)-?[0-9]{5,}", @"$1[REDACTED]"],
          @[@"(?i)(authorization\\s*:\\s*bearer\\s+)[^\\s]+", @"$1[REDACTED]"],
          @[@"(?i)(token\\s*[=:]\\s*)[^\\s]+", @"$1[REDACTED]"]
        ];
        for (NSArray<NSString *> *pair in patterns) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pair[0]
                options:0 error:NULL];
            if (regex) tail = [regex stringByReplacingMatchesInString:tail options:0
                range:NSMakeRange(0, tail.length) withTemplate:pair[1]];
        }
        return tail.length ? tail : @"The existing monitor.log is empty.";
    } @catch (NSException *exception) {
        (void)exception;
        return @"Could not read the existing monitor.log. Nothing was changed.";
    } @finally {
        [handle closeFile];
    }
}

- (void)viewLog:(id)sender {
    (void)sender;
    NSString *text = [self redactedLogTail];
    if (!self.logWindow) {
        self.logWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 850, 520)
            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
            backing:NSBackingStoreBuffered defer:NO];
        self.logWindow.title = @"MacLock Guardian — Local log preview (read only)";
        [self.logWindow setMinSize:NSMakeSize(600, 350)];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(15, 15, 820, 490)];
        scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        scroll.hasVerticalScroller = YES;
        scroll.borderType = NSBezelBorder;
        NSTextView *viewer = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 815, 480)];
        viewer.editable = NO;
        viewer.selectable = YES;
        viewer.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
        viewer.autoresizingMask = NSViewWidthSizable;
        scroll.documentView = viewer;
        [self.logWindow.contentView addSubview:scroll];
    }
    NSScrollView *scroll = self.logWindow.contentView.subviews.firstObject;
    NSTextView *viewer = (NSTextView *)scroll.documentView;
    viewer.string = [NSString stringWithFormat:
        @"Showing up to 100 recent lines (max 64 KiB), locally, with best-effort redaction.\n"
        @"Review carefully before copying or sharing: other sensitive information may remain.\n\n%@", text];
    [self.logWindow center];
    [self.logWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self showStatus:@"Opened the local log viewer. This did not change or upload the log."];
}

- (void)openLog:(id)sender {
    (void)sender;
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".mac-security/monitor.log"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self showStatus:@"Legacy monitor.log not found. The dashboard does not create or change log files."];
        return;
    }
    [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
    [self showStatus:@"Selected the existing text-monitor log in Finder (read only). Keep your bot-token private."];
}

- (BOOL)readTelegramToken:(NSString * __autoreleasing *)tokenOut
                     chat:(NSString * __autoreleasing *)chatOut {
    NSString *token = [self.tokenField.stringValue stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *chat = [self.chatField.stringValue stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRegularExpression *tokenRegex = [NSRegularExpression
        regularExpressionWithPattern:@"^[0-9]+:[A-Za-z0-9_-]+$" options:0 error:NULL];
    NSRegularExpression *chatRegex = [NSRegularExpression
        regularExpressionWithPattern:@"^-?[0-9]+$" options:0 error:NULL];
    if ([tokenRegex numberOfMatchesInString:token options:0 range:NSMakeRange(0, token.length)] != 1 ||
        [chatRegex numberOfMatchesInString:chat options:0 range:NSMakeRange(0, chat.length)] != 1) {
        [self showStatus:@"Enter a valid Telegram bot token and numeric chat ID. Nothing was sent."];
        return NO;
    }
    *tokenOut = token;
    *chatOut = chat;
    return YES;
}

- (void)sendTelegramMethod:(NSString *)method payload:(NSDictionary *)payload token:(NSString *)token {
    if (self.sending) return;
    self.sending = YES;
    [self showStatus:@"Sending your one-time Telegram request..."];
    NSString *address = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/%@", token, method];
    NSURL *url = [NSURL URLWithString:address];
    if (!url) {
        self.sending = NO;
        [self showStatus:@"Unable to construct Telegram request URL. Nothing sent."];
        return;
    }
    NSError *serializeError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&serializeError];
    if (!data) {
        self.sending = NO;
        [self showStatus:@"Could not prepare Telegram request. Nothing sent."];
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = data;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 15;
    configuration.timeoutIntervalForResource = 20;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
      completionHandler:^(NSData *responseData, NSURLResponse *response, NSError *networkError) {
        NSInteger code = [(NSHTTPURLResponse *)response statusCode];
        BOOL ok = NO;
        if (!networkError && responseData) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:NULL];
            ok = [json isKindOfClass:[NSDictionary class]] && [json[@"ok"] boolValue] && code == 200;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            DesktopController *strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.sending = NO;
            if (ok) {
                [strongSelf showStatus:@"Telegram accepted the request. Check your private chat. No credentials or coordinates were saved."];
            } else if (networkError) {
                [strongSelf showStatus:@"Network error. Telegram request failed. Check your connection and retry manually."];
            } else {
                [strongSelf showStatus:[NSString stringWithFormat:@"Telegram rejected the request (HTTP %ld). Check bot token/chat ID.", (long)code]];
            }
        });
        [session finishTasksAndInvalidate];
    }];
    [task resume];
}

- (void)sendMessage:(id)sender {
    (void)sender;
    if (self.sending) return;
    NSString *token = nil;
    NSString *chat = nil;
    if (![self readTelegramToken:&token chat:&chat]) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Send a test Telegram message?";
    alert.informativeText = [NSString stringWithFormat:
        @"Send one text message to chat %@? This will not trigger monitoring or collect photos/location.", chat];
    [alert addButtonWithTitle:@"Send Test"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    self.tokenField.stringValue = @"";
    [self sendTelegramMethod:@"sendMessage" payload:@{ @"chat_id":chat,
        @"text":@"MacLock Guardian v1.3 desktop test. No security settings were changed." } token:token];
}

- (void)requestLocation:(id)sender {
    (void)sender;
    self.lastLocation = nil;
    self.mapButton.enabled = NO;
    if (![CLLocationManager locationServicesEnabled]) {
        [self showStatus:@"Location Services is disabled. Enable it in macOS Privacy & Security settings."];
        return;
    }
    self.requestingLocation = YES;
    CLAuthorizationStatus status = self.locationManager.authorizationStatus;
    if (status == kCLAuthorizationStatusNotDetermined) {
        [self showStatus:@"Requesting macOS location permission. No location will be sent automatically."];
        [self.locationManager requestWhenInUseAuthorization];
    } else if (status == kCLAuthorizationStatusAuthorizedAlways) {
        [self showStatus:@"Requesting a location estimate. Nothing sent to Telegram."];
        [self.locationManager requestLocation];
    } else {
        self.requestingLocation = NO;
        [self showStatus:@"Location permission denied or restricted. Nothing sent."];
    }
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (!self.requestingLocation) return;
    CLAuthorizationStatus status = manager.authorizationStatus;
    if (status == kCLAuthorizationStatusAuthorizedAlways) {
        [self showStatus:@"Permission granted. Getting one location estimate..."];
        [manager requestLocation];
    } else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        self.requestingLocation = NO;
        [self showStatus:@"Location permission was not granted. Nothing sent."];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    (void)manager;
    if (!self.requestingLocation) return;
    self.requestingLocation = NO;
    CLLocation *fix = locations.lastObject;
    if (!fix || !CLLocationCoordinate2DIsValid(fix.coordinate) ||
        fix.horizontalAccuracy < 0 || fix.horizontalAccuracy > 5000 ||
        fabs([fix.timestamp timeIntervalSinceNow]) > 120.0) {
        [self showStatus:@"No recent, accurate-enough location. Try again later."];
        return;
    }
    self.lastLocation = fix;
    self.mapButton.enabled = YES;
    [self showStatus:[NSString stringWithFormat:
         @"Location obtained (estimated accuracy ±%.0f m). Not sent. Click Send Map to confirm.",
         fix.horizontalAccuracy]];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    (void)manager;
    self.requestingLocation = NO;
    self.mapButton.enabled = NO;
    [self showStatus:[NSString stringWithFormat:@"Location unavailable (error %ld). Nothing sent.", (long)error.code]];
}

- (void)sendMap:(id)sender {
    (void)sender;
    if (self.sending || !self.lastLocation ||
        fabs([self.lastLocation.timestamp timeIntervalSinceNow]) > 120.0) {
        self.mapButton.enabled = NO;
        [self showStatus:@"Location expired. Request a fresh location before sending."];
        return;
    }
    NSString *token = nil;
    NSString *chat = nil;
    if (![self readTelegramToken:&token chat:&chat]) return;
    CLLocation *fix = self.lastLocation;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Share this Mac's location with Telegram?";
    alert.informativeText = [NSString stringWithFormat:
        @"Send one map pin to chat %@ (accuracy ±%.0f m)? This shares precise coordinates with Telegram. No automatic tracking will be enabled.",
        chat, fix.horizontalAccuracy];
    [alert addButtonWithTitle:@"Send One Map"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    self.tokenField.stringValue = @"";
    self.mapButton.enabled = NO;
    self.lastLocation = nil;
    [self sendTelegramMethod:@"sendLocation" payload:@{
        @"chat_id":chat,
        @"latitude":@(fix.coordinate.latitude),
        @"longitude":@(fix.coordinate.longitude),
        @"horizontal_accuracy":@(MIN(1500.0, MAX(0.0, fix.horizontalAccuracy)))
    } token:token];
}

- (void)openCameraTest:(id)sender {
    (void)sender;
    if (!self.cameraPreview) self.cameraPreview = [[CameraPreviewController alloc] init];
    [self.cameraPreview openWindow];
    [self showStatus:@"Camera test window opened. The camera remains OFF until you press Start Preview."];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self.cameraPreview stopPreview];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSRect frame = NSMakeRect(0, 0, 750, 675);
    self.window = [[NSWindow alloc] initWithContentRect:frame
      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                 NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
      backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"MacLock Guardian — Camera Preview v1.3";
    [self.window setMinSize:NSMakeSize(750, 675)];
    [self.window center];
    NSView *content = self.window.contentView;

    NSTextField *title = MakeLabel(@"MacLock Guardian", NSMakeRect(25, 623, 640, 34), 27, YES);
    [content addSubview:title];
    NSTextField *subtitle = MakeLabel(@"v1.3 alpha — diagnostics + camera self-test (explicit, local only)",
                                       NSMakeRect(25, 594, 690, 24), 12, NO);
    subtitle.textColor = [NSColor secondaryLabelColor];
    [content addSubview:subtitle];

    NSTextField *section = MakeLabel(@"Security services (read only)", NSMakeRect(25, 558, 460, 24), 16, YES);
    [content addSubview:section];
    self.refreshButtons = [NSMutableArray array];
    NSButton *refreshButton = MakeButton(@"Refresh", NSMakeRect(620, 555, 100, 28), self, @selector(refresh:));
    [self.refreshButtons addObject:refreshButton];
    [content addSubview:refreshButton];
    [content addSubview:MakeButton(@"Copy Status", NSMakeRect(500, 555, 112, 28), self, @selector(copyStatus:))];

    self.serviceIDs = @[
      @"com.macsecurity.alert", @"com.macsecurity.photo", @"com.macsecurity.cleanup",
      @"com.macsecurity.health", @"com.macsecurity.notify",
      @"org.maclockguardian.monitor", @"org.maclockguardian.cleanup", @"org.maclockguardian.health"
    ];
    NSArray<NSString *> *names = @[
      @"Legacy  ·  Telegram text alerts", @"Legacy  ·  Webcam photo alerts",
      @"Legacy  ·  Cleanup", @"Legacy  ·  Health checks",
      @"Legacy  ·  Health notifications", @"GitHub edition  ·  Security watcher",
      @"GitHub edition  ·  Cleanup", @"GitHub edition  ·  Health checks"
    ];
    self.serviceStatusLabels = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.serviceIDs.count; i++) {
        CGFloat y = 524 - i * 28;
        NSTextField *item = MakeLabel(names[i], NSMakeRect(32, y, 460, 22), 13, NO);
        [content addSubview:item];
        NSTextField *status = MakeLabel(@"Checking...", NSMakeRect(530, y, 186, 22), 13, YES);
        [content addSubview:status];
        [self.serviceStatusLabels addObject:status];
    }

    self.summaryLabel = MakeLabel(@"Not yet checked", NSMakeRect(32, 300, 690, 22), 12, NO);
    self.summaryLabel.textColor = [NSColor secondaryLabelColor];
    [content addSubview:self.summaryLabel];

    NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(25, 293, 700, 1)];
    divider.boxType = NSBoxSeparator;
    [content addSubview:divider];

    [content addSubview:MakeLabel(@"One-time Telegram tests — not saved", NSMakeRect(25, 263, 520, 25), 16, YES)];
    [content addSubview:MakeLabel(@"Bot token", NSMakeRect(32, 229, 110, 20), 13, NO)];
    [content addSubview:MakeLabel(@"Chat ID", NSMakeRect(32, 195, 110, 20), 13, NO)];
    self.tokenField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(145, 226, 375, 26)];
    self.tokenField.placeholderString = @"Enter locally; never paste tokens in chat";
    [content addSubview:self.tokenField];
    self.chatField = [[NSTextField alloc] initWithFrame:NSMakeRect(145, 192, 205, 26)];
    self.chatField.placeholderString = @"Numeric chat ID";
    [content addSubview:self.chatField];
    [content addSubview:MakeButton(@"Send Test Text", NSMakeRect(535, 224, 185, 30), self, @selector(sendMessage:))];
    NSButton *refreshStatusButton = MakeButton(@"Refresh Status", NSMakeRect(365, 189, 165, 30), self, @selector(refresh:));
    [self.refreshButtons addObject:refreshStatusButton];
    [content addSubview:refreshStatusButton];
    [content addSubview:MakeButton(@"Get Location", NSMakeRect(32, 144, 169, 30), self, @selector(requestLocation:))];
    self.mapButton = MakeButton(@"Send One Map", NSMakeRect(213, 144, 169, 30), self, @selector(sendMap:));
    self.mapButton.enabled = NO;
    [content addSubview:self.mapButton];
    [content addSubview:MakeButton(@"Reveal Log", NSMakeRect(395, 144, 147, 30), self, @selector(openLog:))];
    [content addSubview:MakeButton(@"View Log", NSMakeRect(553, 144, 167, 30), self, @selector(viewLog:))];

    [content addSubview:MakeLabel(@"Camera self-test (off by default)",
                                  NSMakeRect(32, 106, 425, 22), 14, YES)];
    [content addSubview:MakeButton(@"Open Camera Test", NSMakeRect(525, 104, 195, 30),
                                   self, @selector(openCameraTest:))];

    self.statusMessageLabel = MakeLabel(@"Ready. No messages, location or camera requests have been sent.",
                             NSMakeRect(32, 48, 680, 50), 12, NO);
    self.statusMessageLabel.maximumNumberOfLines = 4;
    self.statusMessageLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [content addSubview:self.statusMessageLabel];
    NSTextField *footer = MakeLabel(@"Preview only: this app never starts, stops, installs or edits monitoring agents.",
                                    NSMakeRect(25, 19, 700, 23), 11, NO);
    footer.textColor = [NSColor secondaryLabelColor];
    [content addSubview:footer];

    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self refresh:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}
@end

int main(int argc, const char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        DesktopController *controller = [[DesktopController alloc] init];
        app.delegate = controller;
        [app run];
    }
    return 0;
}
