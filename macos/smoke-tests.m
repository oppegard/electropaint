#import <Cocoa/Cocoa.h>
#import <ScreenSaver/ScreenSaver.h>
#import <QuartzCore/CAMetalLayer.h>
#include <assert.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreGraphics/CoreGraphics.h>

static IMP originalRender;
static unsigned updates, displayUpdates;
static __weak id observedView;
static void countedRender(id view, SEL selector, double timestamp, id drawable) {
    ++updates;
    if (view == observedView) ++displayUpdates;
    ((void (*)(id,SEL,double,id))originalRender)(view,selector,timestamp,drawable);
}
static void pump(double seconds) {
    NSTimer *stop = [NSTimer timerWithTimeInterval:seconds repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        [NSApp stop:nil];
        [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
            location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
            context:nil subtype:0 data1:0 data2:0] atStart:NO];
    }];
    [[NSRunLoop mainRunLoop] addTimer:stop forMode:NSRunLoopCommonModes];
    [NSApp run];
    [stop invalidate];
}

@interface ScreenSaverView (DisplayTesting)
- (BOOL)shouldAnimateOnCurrentDisplay;
- (void)renderAtTimestamp:(double)timestamp drawable:(id<CAMetalDrawable>)drawable;
@end

@interface TestScreen : NSScreen
@property NSNumber *displayID;
@end
@implementation TestScreen
- (NSDictionary *)deviceDescription {
    return self.displayID ? @{@"NSScreenNumber": self.displayID} : @{};
}
@end

@interface TestWindow : NSWindow
@property NSScreen *testScreen;
@property BOOL useTestScreen;
@end
@implementation TestWindow
- (NSScreen *)screen { return self.useTestScreen ? self.testScreen : [super screen]; }
@end

static unsigned animatedFrames, blackFrames;
static void recordFrame(id self, SEL selector, const void *frame, id<CAMetalDrawable> drawable) {
    if (frame) ++animatedFrames;
    else ++blackFrames;
    struct objc_super parent = {self, class_getSuperclass(object_getClass(self))};
    ((void (*)(struct objc_super *, SEL, const void *, id<CAMetalDrawable>))objc_msgSendSuper)(&parent, selector, frame, drawable);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        [app finishLaunching];
        NSDictionary *session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
        BOOL displayLocked = [session[@"CGSSessionScreenIsLocked"] boolValue];
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil;
        assert([bundle loadAndReturnError:&error]);
        Class saverClass = bundle.principalClass;
        assert([saverClass isSubclassOfClass:[ScreenSaverView class]]);
        Method rendering = class_getInstanceMethod(saverClass, NSSelectorFromString(@"renderAtTimestamp:drawable:"));
        assert(rendering);
        originalRender = method_setImplementation(rendering, (IMP)countedRender);
        Class trackedClass = objc_allocateClassPair(saverClass, "DisplayTestSaver", 0);
        Method render = class_getInstanceMethod(saverClass, NSSelectorFromString(@"renderFrame:drawable:"));
        assert(render);
        assert(class_addMethod(trackedClass, method_getName(render), (IMP)recordFrame,
                               method_getTypeEncoding(render)));
        objc_registerClassPair(trackedClass);
        ScreenSaverView *a = [[saverClass alloc] initWithFrame:NSMakeRect(0,0,640,480) isPreview:YES];
        ScreenSaverView *b = [[trackedClass alloc] initWithFrame:NSMakeRect(0,0,1920,1080) isPreview:NO];
        assert(a && b && !a.hasConfigureSheet && !b.hasConfigureSheet);
        assert([a.layer isKindOfClass:[CAMetalLayer class]]);
        assert(((CAMetalLayer *)a.layer).device);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,480)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        observedView = a;
        window.contentView = a;
        [window makeKeyAndOrderFront:nil];
        [app activateIgnoringOtherApps:YES];
        [a startAnimation]; [b startAnimation];
        pump(0.5);
        assert(updates>0 && displayUpdates>0);
        if (!displayLocked) assert(displayUpdates>=10);
        unsigned before=updates;
        for(int i=0;i<30;++i) { [a animateOneFrame]; [b animateOneFrame]; }
        assert(updates==before); // Host callbacks cannot drive duplicate frames.
        assert([a shouldAnimateOnCurrentDisplay]);
        assert(![b shouldAnimateOnCurrentDisplay]);
        TestScreen *primary = [TestScreen new];
        primary.displayID = @(CGMainDisplayID());
        TestScreen *secondary = [TestScreen new];
        secondary.displayID = @(CGMainDisplayID() == 1 ? 2 : 1);
        TestWindow *displayWindow = [[TestWindow alloc] initWithContentRect:NSMakeRect(0,0,1920,1080)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        displayWindow.useTestScreen = YES;
        displayWindow.contentView = b;
        displayWindow.testScreen = primary;
        assert([b shouldAnimateOnCurrentDisplay]);
        unsigned beforeAnimated = animatedFrames, beforeBlack = blackFrames;
        [b renderAtTimestamp:1 drawable:nil];
        assert(animatedFrames == beforeAnimated+1 && blackFrames == beforeBlack);
        beforeAnimated = animatedFrames;
        displayWindow.testScreen = secondary;
        assert(![b shouldAnimateOnCurrentDisplay]);
        for (int i=0;i<3;++i) [b renderAtTimestamp:2+i drawable:nil];
        assert(animatedFrames == beforeAnimated && blackFrames == beforeBlack+3);
        displayWindow.testScreen = [TestScreen new];
        assert(![b shouldAnimateOnCurrentDisplay]);
        [b renderAtTimestamp:5 drawable:nil];
        assert(blackFrames == beforeBlack+4);
        displayWindow.testScreen = primary;
        [b renderAtTimestamp:6 drawable:nil];
        assert(animatedFrames == beforeAnimated+1 && blackFrames == beforeBlack+4);
        displayWindow.useTestScreen = NO;
        [a setFrameSize:NSMakeSize(800,600)]; [a layoutSubtreeIfNeeded];
        CGFloat scale=window.backingScaleFactor;
        assert(((CAMetalLayer *)a.layer).drawableSize.width == 800*scale);
        [a stopAnimation]; [b stopAnimation];
        assert(!a.isAnimating && !b.isAnimating);
        before=updates; pump(0.1); assert(updates==before);
        [a startAnimation]; [a startAnimation]; assert(a.isAnimating);
        pump(0.5);
        if (!displayLocked) assert(updates>before);
        window.contentView = [NSView new]; // Exercise driver replacement on detach.
        before=updates; pump(0.1); assert(updates>before);
        [a stopAnimation];
        [window orderOut:nil];
        displayWindow.contentView = a;
        displayWindow.testScreen = secondary;
        displayWindow.useTestScreen = YES;
        assert([a shouldAnimateOnCurrentDisplay]);
        displayWindow.useTestScreen = NO;
        displayWindow.contentView = [NSView new];
        __weak ScreenSaverView *released;
        @autoreleasepool {
            ScreenSaverView *temporary = [[saverClass alloc] initWithFrame:NSMakeRect(0,0,64,64) isPreview:YES];
            released = temporary;
            [temporary startAnimation]; [temporary stopAnimation];
        }
        assert(!released);
        method_setImplementation(rendering, originalRender);
        if (displayLocked) NSLog(@"Display session locked: continuous Metal presentation and resumed display callbacks require an unlocked session.");
        NSLog(@"Passed bundle loading, Metal shader compilation, independent preview/full-size views, display-driven callbacks, suppressed host callbacks, resize, detach, stop/restart, primary-display selection, black transitions and preview exemption.");
    }
    return 0;
}
