// MacLock Guardian v1.3: manual, in-memory camera preview only.
#import <Cocoa/Cocoa.h>

@interface CameraPreviewController : NSObject <NSWindowDelegate>
- (void)openWindow;
- (void)stopPreview;
@end
