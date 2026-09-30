#import <Cocoa/Cocoa.h>
#import "ElectropaintView.h"

@interface PreviewDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property ElectropaintView *saver;
@property NSTimer *timer;
@end
@implementation PreviewDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 720)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Electropaint — 1994 default script";
    self.saver = [[ElectropaintView alloc] initWithFrame:self.window.contentView.bounds isPreview:YES];
    if (!self.saver) { NSLog(@"Unable to initialize Electropaint"); [NSApp terminate:nil]; return; }
    self.saver.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = self.saver;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.saver startAnimation];
    __weak PreviewDelegate *weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:1.0/60.0 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        if (weakSelf.saver.isAnimating) [weakSelf.saver animateOneFrame];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return YES; }
- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification; [self.timer invalidate]; [self.saver stopAnimation];
}
@end
int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        PreviewDelegate *delegate = [PreviewDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
