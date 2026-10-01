#import <Cocoa/Cocoa.h>
#import "ElectropaintView.h"

@interface PreviewView : ElectropaintView
@end
@implementation PreviewView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)event {
    NSEventModifierFlags modifiers = event.modifierFlags &
        (NSEventModifierFlagCommand | NSEventModifierFlagControl |
         NSEventModifierFlagOption | NSEventModifierFlagShift);
    if (modifiers == 0 && [event.charactersIgnoringModifiers isEqualToString:@" "]) {
        if (!event.isARepeat) {
            if (self.isAnimating) [self stopAnimation];
            else [self startAnimation];
        }
        return;
    }
    [super keyDown:event];
}
@end

@interface PreviewDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property ElectropaintView *saver;
@end
@implementation PreviewDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 960, 720)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    NSString *revision = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"ElectropaintGitRevision"];
    self.window.title = [NSString stringWithFormat:@"Electropaint — 1994 default script (%@)",
        revision.length ? revision : @"unknown"];
    self.window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
    self.saver = [[PreviewView alloc] initWithFrame:self.window.contentView.bounds isPreview:YES];
    if (!self.saver) { NSLog(@"Unable to initialize Electropaint"); [NSApp terminate:nil]; return; }
    self.saver.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = self.saver;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.saver];
    [NSApp activateIgnoringOtherApps:YES];
    [self.saver startAnimation];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return YES; }
- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification; [self.saver stopAnimation];
}
@end
int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        NSMenu *menuBar = [NSMenu new];
        NSMenuItem *applicationItem = [NSMenuItem new];
        NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"Electropaint"];
        NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Electropaint"
            action:@selector(terminate:) keyEquivalent:@"q"];
        quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
        quitItem.target = app;
        [applicationMenu addItem:quitItem];
        applicationItem.submenu = applicationMenu;
        [menuBar addItem:applicationItem];
        NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:NULL keyEquivalent:@""];
        NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
        NSMenuItem *closeItem = [[NSMenuItem alloc] initWithTitle:@"Close Window"
            action:@selector(performClose:) keyEquivalent:@"w"];
        closeItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
        [fileMenu addItem:closeItem];
        fileItem.submenu = fileMenu;
        [menuBar addItem:fileItem];
        NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:NULL keyEquivalent:@""];
        NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
        NSMenuItem *fullScreenItem = [[NSMenuItem alloc] initWithTitle:@"Toggle Full Screen"
            action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
        fullScreenItem.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagCommand;
        [viewMenu addItem:fullScreenItem];
        viewItem.submenu = viewMenu;
        [menuBar addItem:viewItem];
        app.mainMenu = menuBar;
        PreviewDelegate *delegate = [PreviewDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
