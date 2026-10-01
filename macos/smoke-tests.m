#import <Cocoa/Cocoa.h>
#import <ScreenSaver/ScreenSaver.h>
#import <QuartzCore/CAMetalLayer.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <assert.h>

@interface ScreenSaverView (DisplayTesting)
- (BOOL)shouldAnimateOnCurrentDisplay;
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
@end
@implementation TestWindow
- (NSScreen *)screen { return self.testScreen; }
@end

static unsigned animatedFrames, blackFrames;
static void recordFrame(id self, SEL selector, const void *frame) {
    if (frame) ++animatedFrames;
    else ++blackFrames;
    struct objc_super parent = {self, class_getSuperclass(object_getClass(self))};
    ((void (*)(struct objc_super *, SEL, const void *))objc_msgSendSuper)(&parent, selector, frame);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        [NSApplication sharedApplication];
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil;
        assert([bundle loadAndReturnError:&error]);
        Class saverClass = bundle.principalClass;
        assert([saverClass isSubclassOfClass:[ScreenSaverView class]]);
        Class trackedClass = objc_allocateClassPair(saverClass, "DisplayTestSaver", 0);
        Method render = class_getInstanceMethod(saverClass, NSSelectorFromString(@"renderFrame:"));
        assert(render);
        assert(class_addMethod(trackedClass, method_getName(render), (IMP)recordFrame,
                               method_getTypeEncoding(render)));
        objc_registerClassPair(trackedClass);
        ScreenSaverView *a = [[saverClass alloc] initWithFrame:NSMakeRect(0,0,640,480) isPreview:YES];
        ScreenSaverView *b = [[trackedClass alloc] initWithFrame:NSMakeRect(0,0,1920,1080) isPreview:NO];
        assert(a && b && !a.hasConfigureSheet && !b.hasConfigureSheet);
        assert([a.layer isKindOfClass:[CAMetalLayer class]]);
        assert(((CAMetalLayer *)a.layer).device);
        assert([a shouldAnimateOnCurrentDisplay]);
        assert(![b shouldAnimateOnCurrentDisplay]);
        TestScreen *primary = [TestScreen new];
        primary.displayID = @(CGMainDisplayID());
        TestScreen *secondary = [TestScreen new];
        secondary.displayID = @(CGMainDisplayID() == 1 ? 2 : 1);
        TestWindow *window = [[TestWindow alloc] initWithContentRect:NSMakeRect(0,0,1920,1080)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.contentView = b;
        window.testScreen = primary;
        assert([b shouldAnimateOnCurrentDisplay]);
        [a startAnimation]; [b startAnimation];
        for(int i=0;i<30;++i) {
            [a animateOneFrame]; [b animateOneFrame];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0/60.0]];
        }
        assert(animatedFrames > 0 && blackFrames == 0);
        unsigned beforeBlack = animatedFrames;
        window.testScreen = secondary;
        assert(![b shouldAnimateOnCurrentDisplay]);
        for (int i=0; i<3; ++i) [b animateOneFrame];
        assert(animatedFrames == beforeBlack && blackFrames == 3);
        window.testScreen = [TestScreen new];
        assert(![b shouldAnimateOnCurrentDisplay]);
        [b animateOneFrame];
        assert(blackFrames == 4);
        window.testScreen = primary;
        [b animateOneFrame];
        assert(animatedFrames == beforeBlack + 1);
        window.contentView = a;
        window.testScreen = secondary;
        assert([a shouldAnimateOnCurrentDisplay]);
        [a setFrameSize:NSMakeSize(800,600)]; [a layoutSubtreeIfNeeded];
        assert(((CAMetalLayer *)a.layer).drawableSize.width == 800 * window.backingScaleFactor);
        [a stopAnimation]; assert(!a.isAnimating);
        [a startAnimation]; assert(a.isAnimating); [a animateOneFrame];
        [a stopAnimation]; [b stopAnimation];
        NSLog(@"Passed bundle loading, Metal compilation, primary/secondary/unknown display selection, black transitions, preview exemption, resize and restart.");
    }
    return 0;
}
