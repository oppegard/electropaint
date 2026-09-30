#import <Cocoa/Cocoa.h>
#import <ScreenSaver/ScreenSaver.h>
#import <QuartzCore/CAMetalLayer.h>
#include <assert.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        [NSApplication sharedApplication];
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil;
        assert([bundle loadAndReturnError:&error]);
        Class saverClass = bundle.principalClass;
        assert([saverClass isSubclassOfClass:[ScreenSaverView class]]);
        ScreenSaverView *a = [[saverClass alloc] initWithFrame:NSMakeRect(0,0,640,480) isPreview:YES];
        ScreenSaverView *b = [[saverClass alloc] initWithFrame:NSMakeRect(0,0,1920,1080) isPreview:NO];
        assert(a && b && !a.hasConfigureSheet && !b.hasConfigureSheet);
        assert([a.layer isKindOfClass:[CAMetalLayer class]]);
        assert(((CAMetalLayer *)a.layer).device);
        [a startAnimation]; [b startAnimation];
        for(int i=0;i<30;++i) {
            [a animateOneFrame]; [b animateOneFrame];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0/60.0]];
        }
        [a setFrameSize:NSMakeSize(800,600)]; [a layoutSubtreeIfNeeded];
        assert(((CAMetalLayer *)a.layer).drawableSize.width == 800);
        [a stopAnimation]; assert(!a.isAnimating);
        [a startAnimation]; assert(a.isAnimating); [a animateOneFrame];
        [a stopAnimation]; [b stopAnimation];
        NSLog(@"Passed bundle loading, Metal shader compilation, independent preview/full-size views, resize and restart.");
    }
    return 0;
}
