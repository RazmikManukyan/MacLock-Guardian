// MacLock Guardian v1.2 desktop preview — macOS 14+
// AppKit GUI; READ-ONLY monitor status. No LaunchAgents are modified.
// Telegram and location actions require a deliberate button click and confirmation.
#import <Cocoa/Cocoa.h>
#import <CoreLocation/CoreLocation.h>
#include <math.h>
#include <unistd.h>

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
@property(nonatomic, strong) NSTextField *message;
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

- (NSString *)statusForService:(NSString *)identifier {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/launchctl";
    task.arguments = @[@"print", [NSString stringWithFormat:@"gui/%d/%@", getuid(), identifier]];
    NSPipe *output = [NSPipe pipe];
    task.standardOutput = output;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) return @"Unable to check";
    // Drain before waitUntilExit, avoiding pipe-buffer deadlocks.
    NSData *data = [[output fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus != 0) return @"Not installed";
    NSString *details = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if ([details containsString:@"state = running"]) return @"Running";
    if ([details containsString:@"state = waiting"]) return @"Loaded / idle";
    return @"Loaded / inspect";
}

- (void)refresh:(id)sender {
    (void)sender;
    for (NSUInteger index = 0; index < self.serviceIDs.count; index++) {
        NSString *status = [self statusForService:self.serviceIDs[index]];
        NSTextField *field = self.serviceStatusLabels[index];
        field.stringValue = status;
        field.textColor = [status isEqualToString:@"Running"] ? [NSColor systemGreenColor] :
             [status isEqualToString:@"Not installed"] ? [NSColor secondaryLabelColor] : [NSColor systemOrangeColor];
    }
    [self.message setStringValue:@"Status refreshed. These are process checks only; they cannot guarantee alert delivery."];
}

- (void)openLog:(id)sender {
    (void)sender;
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".mac-security/monitor.log"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [self.message setStringValue:@"Legacy monitor.log not found. The dashboard does not create or change log files."];
        return;
    }
    [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
    [self.message setStringValue:@"Selected the existing text-monitor log in Finder (read only). Keep your bot-token private."];
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
        [self.message setStringValue:@"Enter a valid Telegram bot token and numeric chat ID. Nothing was sent."];
        return NO;
    }
    *tokenOut = token;
    *chatOut = chat;
    return YES;
}

- (void)sendTelegramMethod:(NSString *)method payload:(NSDictionary *)payload token:(NSString *)token {
    if (self.sending) return;
    self.sending = YES;
    [self.message setStringValue:@"Sending your one-time Telegram request..."];
    NSString *address = [NSString stringWithFormat:@"https://api.telegram.org/bot%@/%@", token, method];
    NSURL *url = [NSURL URLWithString:address];
    if (!url) {
        self.sending = NO;
        [self.message setStringValue:@"Unable to construct Telegram request URL. Nothing sent."];
        return;
    }
    NSError *serializeError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&serializeError];
    if (!data) {
        self.sending = NO;
        [self.message setStringValue:@"Could not prepare Telegram request. Nothing sent."];
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
                [strongSelf.message setStringValue:@"Telegram accepted the request. Check your private chat. No credentials or coordinates were saved."];
            } else if (networkError) {
                [strongSelf.message setStringValue:@"Network error. Telegram request failed. Check your connection and retry manually."];
            } else {
                [strongSelf.message setStringValue:[NSString stringWithFormat:@"Telegram rejected the request (HTTP %ld). Check bot token/chat ID.", (long)code]];
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
        @"text":@"MacLock Guardian v1.2 desktop test. No security settings were changed." } token:token];
}

- (void)requestLocation:(id)sender {
    (void)sender;
    self.lastLocation = nil;
    self.mapButton.enabled = NO;
    if (![CLLocationManager locationServicesEnabled]) {
        [self.message setStringValue:@"Location Services is disabled. Enable it in macOS Privacy & Security settings."];
        return;
    }
    self.requestingLocation = YES;
    CLAuthorizationStatus status = self.locationManager.authorizationStatus;
    if (status == kCLAuthorizationStatusNotDetermined) {
        [self.message setStringValue:@"Requesting macOS location permission. No location will be sent automatically."];
        [self.locationManager requestWhenInUseAuthorization];
    } else if (status == kCLAuthorizationStatusAuthorizedAlways) {
        [self.message setStringValue:@"Requesting a location estimate. Nothing sent to Telegram."];
        [self.locationManager requestLocation];
    } else {
        self.requestingLocation = NO;
        [self.message setStringValue:@"Location permission denied or restricted. Nothing sent."];
    }
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (!self.requestingLocation) return;
    CLAuthorizationStatus status = manager.authorizationStatus;
    if (status == kCLAuthorizationStatusAuthorizedAlways) {
        [self.message setStringValue:@"Permission granted. Getting one location estimate..."];
        [manager requestLocation];
    } else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        self.requestingLocation = NO;
        [self.message setStringValue:@"Location permission was not granted. Nothing sent."];
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
        [self.message setStringValue:@"No recent, accurate-enough location. Try again later."];
        return;
    }
    self.lastLocation = fix;
    self.mapButton.enabled = YES;
    [self.message setStringValue:[NSString stringWithFormat:
         @"Location obtained (estimated accuracy ±%.0f m). Not sent. Click Send Map to confirm.",
         fix.horizontalAccuracy]];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    (void)manager;
    self.requestingLocation = NO;
    self.mapButton.enabled = NO;
    [self.message setStringValue:[NSString stringWithFormat:@"Location unavailable (error %ld). Nothing sent.", (long)error.code]];
}

- (void)sendMap:(id)sender {
    (void)sender;
    if (self.sending || !self.lastLocation ||
        fabs([self.lastLocation.timestamp timeIntervalSinceNow]) > 120.0) {
        self.mapButton.enabled = NO;
        [self.message setStringValue:@"Location expired. Request a fresh location before sending."];
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

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSRect frame = NSMakeRect(0, 0, 750, 675);
    self.window = [[NSWindow alloc] initWithContentRect:frame
      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                 NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
      backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"MacLock Guardian — Desktop Preview";
    [self.window setMinSize:NSMakeSize(750, 675)];
    [self.window center];
    NSView *content = self.window.contentView;

    NSTextField *title = MakeLabel(@"MacLock Guardian", NSMakeRect(25, 623, 640, 34), 27, YES);
    [content addSubview:title];
    NSTextField *subtitle = MakeLabel(@"v1.2 alpha — read-only service dashboard + opt-in Telegram / location tests",
                                       NSMakeRect(25, 594, 690, 24), 12, NO);
    subtitle.textColor = [NSColor secondaryLabelColor];
    [content addSubview:subtitle];

    NSTextField *section = MakeLabel(@"Security services (read only)", NSMakeRect(25, 558, 460, 24), 16, YES);
    [content addSubview:section];
    [content addSubview:MakeButton(@"Refresh", NSMakeRect(620, 555, 100, 28), self, @selector(refresh:))];

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
    [content addSubview:MakeButton(@"Refresh Status", NSMakeRect(365, 189, 165, 30), self, @selector(refresh:))];
    [content addSubview:MakeButton(@"Get Location", NSMakeRect(32, 144, 169, 30), self, @selector(requestLocation:))];
    self.mapButton = MakeButton(@"Send One Map", NSMakeRect(213, 144, 169, 30), self, @selector(sendMap:));
    self.mapButton.enabled = NO;
    [content addSubview:self.mapButton];
    [content addSubview:MakeButton(@"Open Monitor Log", NSMakeRect(395, 144, 169, 30), self, @selector(openLog:))];

    self.message = MakeLabel(@"Ready. No messages or location requests have been sent.",
                             NSMakeRect(32, 59, 680, 72), 12, NO);
    self.message.maximumNumberOfLines = 4;
    self.message.lineBreakMode = NSLineBreakByWordWrapping;
    [content addSubview:self.message];
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
