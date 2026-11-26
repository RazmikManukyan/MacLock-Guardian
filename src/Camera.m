#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>

@interface FrameGrabber : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property(nonatomic) dispatch_semaphore_t done;
@property(nonatomic, copy) NSString *outputPath;
@property(nonatomic) NSInteger frames;
@property(nonatomic) BOOL saved;
@end

@implementation FrameGrabber
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sample fromConnection:(AVCaptureConnection *)connection {
    @synchronized(self) {
        if (self.saved || ++self.frames < 20) return;
        CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sample);
        if (!pixelBuffer) return;
        CIImage *image = [CIImage imageWithCVImageBuffer:pixelBuffer];
        CGRect bounds = image.extent;
        if (bounds.size.width <= 0 || bounds.size.height <= 0) return;
        CIContext *context = [CIContext contextWithOptions:nil];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CIImage *small = [image imageByApplyingTransform:CGAffineTransformMakeScale(8.0/bounds.size.width, 8.0/bounds.size.height)];
        unsigned char pixels[8*8*4] = {0};
        [context render:small toBitmap:pixels rowBytes:8*4 bounds:CGRectMake(0,0,8,8) format:kCIFormatRGBA8 colorSpace:space];
        double brightness = 0;
        for (int i=0; i<64; i++) brightness += (pixels[i*4] + pixels[i*4+1] + pixels[i*4+2])/3.0;
        brightness /= 64.0;
        if (brightness >= 1.0) {
            NSData *jpeg = [context JPEGRepresentationOfImage:image colorSpace:space options:@{}];
            if (jpeg && [jpeg writeToFile:self.outputPath atomically:YES]) {
                self.saved = YES;
                dispatch_semaphore_signal(self.done);
            }
        }
        CGColorSpaceRelease(space);
    }
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) { fprintf(stderr, "Usage: MacLockCamera <output.jpg>\n"); return 1; }
        [NSApplication sharedApplication];
        AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        if (status == AVAuthorizationStatusNotDetermined) {
            __block BOOL allowed = NO;
            dispatch_semaphore_t permission = dispatch_semaphore_create(0);
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                allowed = granted;
                dispatch_semaphore_signal(permission);
            }];
            if (dispatch_semaphore_wait(permission,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC)) != 0 || !allowed) {
                NSLog(@"Camera permission unavailable"); return 2;
            }
        } else if (status != AVAuthorizationStatusAuthorized) {
            NSLog(@"Camera permission denied"); return 2;
        }
        AVCaptureDevice *device = ([AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified] ?: [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo]);
        if (!device) { NSLog(@"No camera found"); return 3; }
        NSError *error = nil;
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
        if (!input) { NSLog(@"Camera input error: %@",error); return 4; }
        AVCaptureSession *session = [AVCaptureSession new];
        AVCaptureVideoDataOutput *output = [AVCaptureVideoDataOutput new];
        output.alwaysDiscardsLateVideoFrames = YES;
        if (![session canAddInput:input] || ![session canAddOutput:output]) return 5;
        [session addInput:input]; [session addOutput:output];
        FrameGrabber *grabber = [FrameGrabber new];
        grabber.outputPath = [NSString stringWithUTF8String:argv[1]];
        grabber.done = dispatch_semaphore_create(0);
        [output setSampleBufferDelegate:grabber queue:dispatch_queue_create("maclock.frames",DISPATCH_QUEUE_SERIAL)];
        [session startRunning];
        long timedOut = dispatch_semaphore_wait(grabber.done, dispatch_time(DISPATCH_TIME_NOW,12*NSEC_PER_SEC));
        [session stopRunning];
        if (timedOut || !grabber.saved) { NSLog(@"No usable image received"); return 6; }
        return 0;
    }
}
