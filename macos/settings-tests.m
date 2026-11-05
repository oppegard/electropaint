#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "EPMotionSettings.h"
#import "ElectropaintView.h"
#include "settings-test-support.h"
#include <assert.h>
#include <math.h>

static NSTextField *field(NSWindow *sheet, NSString *identifier) {
    for (NSView *view in sheet.contentView.subviews)
        if ([view.identifier isEqualToString:identifier]) return (NSTextField *)view;
    assert(false);
    return nil;
}

static void click(NSWindow *sheet, NSString *title) {
    for (NSView *view in sheet.contentView.subviews) {
        if ([view isKindOfClass:[NSButton class]] && [((NSButton *)view).title isEqualToString:title]) {
            [(NSButton *)view performClick:nil];
            return;
        }
    }
    assert(false);
}

static void checkLimits(EPMotionLimits actual, double spin, double flip) {
    assert(fabs(actual.maxSpinDegreesPerSecond - spin) < 1e-9);
    assert(fabs(actual.maxFlipDegreesPerSecond - flip) < 1e-9);
}

static EPState *engine(ElectropaintView *view) {
    Ivar ivar = class_getInstanceVariable([ElectropaintView class], "_engine");
    assert(ivar);
    return *(EPState **)((char *)(__bridge void *)view + ivar_getOffset(ivar));
}

static void snapshot(NSWindow *sheet, NSString *path) {
    NSView *content = sheet.contentView;
    NSImage *image = [[NSImage alloc] initWithSize:content.bounds.size];
    [image lockFocus];
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(content.bounds);
    [[NSPDFImageRep imageRepWithData:[content dataWithPDFInsideRect:content.bounds]]
        drawInRect:content.bounds];
    [image unlockFocus];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    assert([png writeToFile:path atomically:YES]);
}

static void edit(NSWindow *sheet, NSString *spin, NSString *flip) {
    field(sheet, @"maximumSpin").stringValue = spin;
    field(sheet, @"maximumFlip").stringValue = flip;
}

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyProhibited;
        [app finishLaunching];
        NSString *suite = [@"com.oppegard.electropaint.settings-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        __block EPMotionLimits applied = {-1, -1};
        __block unsigned saves = 0;
        EPMotionSettings *settings = [[EPMotionSettings alloc] initWithDefaults:defaults apply:^(EPMotionLimits limits) {
            applied = limits;
            ++saves;
        }];
        NSNumberFormatter *formatter = [settings valueForKey:@"formatter"];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
        checkLimits([settings loadLimits], 120, 120);
        NSWindow *sheet = settings.sheet;
        snapshot(sheet, @"/tmp/electropaint-motion-settings-defaults.png");
        assert(sheet == settings.sheet);
        assert([field(sheet, @"maximumSpin").stringValue isEqualToString:@"120"]);
        assert([field(sheet, @"maximumFlip").stringValue isEqualToString:@"120"]);
        NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,480)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [parent beginSheet:sheet completionHandler:nil];
        NSArray<NSString *> *invalid = @[@"", @" ", @"junk", @"12junk", @"12.5 trailing", @"12.5.5", @"1 2", @"0x10", @"1,2", @"NaN", @"∞", @"inf", @"-1", @"313.8001", @"600", @"1e999"];
        for (NSString *value in invalid) {
            edit(sheet, value, @"99.5");
            click(sheet, @"Save");
            assert(saves == 0 && sheet.sheetParent == parent);
            assert(field(sheet, @"spinError").stringValue.length > 0);
            assert(field(sheet, @"flipError").stringValue.length == 0);
            checkLimits([settings loadLimits], 120, 120);
            assert(defaults.dictionaryRepresentation[@"MaximumSpinDegreesPerSecond"] == nil);
            assert(defaults.dictionaryRepresentation[@"MaximumFlipDegreesPerSecond"] == nil);
        }
        edit(sheet, @"12.5", @"600.0001");
        click(sheet, @"Save");
        assert(saves == 0 && sheet.sheetParent == parent);
        assert(field(sheet, @"spinError").stringValue.length == 0);
        assert(field(sheet, @"flipError").stringValue.length > 0);

        snapshot(sheet, @"/tmp/electropaint-motion-settings.png");

        edit(sheet, @"12.5", @"599.75");
        click(sheet, @"Save");
        assert(saves == 1 && !sheet.sheetParent);
        checkLimits(applied, 12.5, 599.75);
        checkLimits([settings loadLimits], 12.5, 599.75);
        EPMotionSettings *reloaded = [[EPMotionSettings alloc] initWithDefaults:
            [[NSUserDefaults alloc] initWithSuiteName:suite] apply:nil];
        checkLimits([reloaded loadLimits], 12.5, 599.75);
        sheet = settings.sheet;
        click(sheet, @"Restore Original");
        assert([field(sheet, @"maximumSpin").stringValue isEqualToString:@"313.8"]);
        assert([field(sheet, @"maximumFlip").stringValue isEqualToString:@"600"]);
        checkLimits([settings loadLimits], 12.5, 599.75);
        click(sheet, @"Cancel");
        assert(saves == 1);
        sheet = settings.sheet;
        assert([field(sheet, @"maximumSpin").stringValue isEqualToString:@"12.5"]);
        click(sheet, @"Restore Original");
        click(sheet, @"Save");
        checkLimits(applied, EPMaximumMotionLimits.maxSpinDegreesPerSecond,
                    EPMaximumMotionLimits.maxFlipDegreesPerSecond);
        sheet = settings.sheet;
        edit(sheet, @"0", @"87.25");
        click(sheet, @"Save");
        checkLimits(applied, 0, 87.25);
        sheet = settings.sheet;
        edit(sheet, @"42.75", @"0");
        click(sheet, @"Save");
        checkLimits(applied, 42.75, 0);
        unsigned before = saves;
        sheet = settings.sheet;
        [parent beginSheet:sheet completionHandler:nil];
        [sheet makeFirstResponder:field(sheet, @"maximumSpin")];
        NSText *editor = field(sheet, @"maximumSpin").currentEditor;
        assert(editor);
        editor.string = @"33.25";
        click(sheet, @"Save");
        checkLimits(applied, 33.25, 0);
        sheet = settings.sheet;
        [parent beginSheet:sheet completionHandler:nil];
        [sheet makeFirstResponder:field(sheet, @"maximumSpin")];
        editor = field(sheet, @"maximumSpin").currentEditor;
        assert(editor);
        editor.string = @"junk";
        before = saves;
        click(sheet, @"Save");
        assert(saves == before && sheet.sheetParent == parent);
        click(sheet, @"Restore Original");
        assert([field(sheet, @"maximumSpin").stringValue isEqualToString:@"313.8"]);
        if (field(sheet, @"maximumSpin").currentEditor)
            assert([field(sheet, @"maximumSpin").currentEditor.string isEqualToString:@"313.8"]);
        click(sheet, @"Cancel");
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"fr_FR"];
        sheet = settings.sheet;
        edit(sheet, @"12,5", @"99,75");
        click(sheet, @"Save");
        checkLimits(applied, 12.5, 99.75);
        sheet = settings.sheet;
        before = saves;
        edit(sheet, @"12,5junk", @"99,75");
        click(sheet, @"Save");
        assert(saves == before && field(sheet, @"spinError").stringValue.length > 0);
        click(sheet, @"Cancel");

        [defaults setDouble:1000 forKey:@"MaximumSpinDegreesPerSecond"];
        [defaults setDouble:1000 forKey:@"MaximumFlipDegreesPerSecond"];
        checkLimits([settings loadLimits], EPMaximumMotionLimits.maxSpinDegreesPerSecond,
                    EPMaximumMotionLimits.maxFlipDegreesPerSecond);
        for (id invalidStored in @[@(-1), @(NAN), @(INFINITY), @"12", @[], @{}]) {
            [defaults setObject:invalidStored forKey:@"MaximumSpinDegreesPerSecond"];
            [defaults setObject:invalidStored forKey:@"MaximumFlipDegreesPerSecond"];
            checkLimits([settings loadLimits], 120, 120);
        }
        [defaults setDouble:0 forKey:@"MaximumSpinDegreesPerSecond"];
        [defaults setDouble:75.25 forKey:@"MaximumFlipDegreesPerSecond"];
        checkLimits([settings loadLimits], 0, 75.25);
        ElectropaintView *a = [[ElectropaintView alloc] initWithFrame:NSMakeRect(0,0,64,64)
            isPreview:YES defaults:defaults];
        ElectropaintView *b = [[ElectropaintView alloc] initWithFrame:NSMakeRect(0,0,64,64)
            isPreview:NO defaults:defaults];
        assert(a && b && a.hasConfigureSheet && b.hasConfigureSheet);
        assert(a.configureSheet == a.configureSheet && a.configureSheet != b.configureSheet);
        checkLimits(ep_test_motion_state(engine(a)).limits, 0, 75.25);
        checkLimits(ep_test_motion_state(engine(b)).limits, 0, 75.25);
        EPState *originalEngine = engine(a);
        ep_step(originalEngine, 64, 64);
        EPMotionTestState original = ep_test_motion_state(originalEngine);
        sheet = a.configureSheet;
        edit(sheet, @"45.5", @"0");
        click(sheet, @"Save");
        assert(engine(a) == originalEngine && ep_test_motion_state(originalEngine).frames == original.frames);
        assert(ep_test_motion_state(originalEngine).random == original.random);
        checkLimits(ep_test_motion_state(engine(a)).limits, 45.5, 0);
        checkLimits(ep_test_motion_state(engine(b)).limits, 0, 75.25);
        [b startAnimation];
        checkLimits(ep_test_motion_state(engine(b)).limits, 45.5, 0);
        [b stopAnimation];
        ElectropaintView *fresh = [[ElectropaintView alloc] initWithFrame:NSMakeRect(0,0,64,64)
            isPreview:YES defaults:[[NSUserDefaults alloc] initWithSuiteName:suite]];
        checkLimits(ep_test_motion_state(engine(fresh)).limits, 45.5, 0);
        __block NSString *moduleName;
        Method factory = class_getClassMethod([ScreenSaverDefaults class], @selector(defaultsForModuleWithName:));
        IMP replacement = imp_implementationWithBlock(^id(id receiver, NSString *name) {
            (void)receiver;
            moduleName = name;
            return defaults;
        });
        IMP originalFactory = method_setImplementation(factory, replacement);
        ElectropaintView *standard = [[ElectropaintView alloc] initWithFrame:NSMakeRect(0,0,64,64) isPreview:YES];
        method_setImplementation(factory, originalFactory);
        imp_removeBlock(replacement);
        assert([moduleName isEqualToString:@"com.oppegard.electropaint.screensaver"]);
        checkLimits(ep_test_motion_state(engine(standard)).limits, 45.5, 0);
        __weak ElectropaintView *releasedView;
        __weak EPMotionSettings *releasedSettings;
        @autoreleasepool {
            ElectropaintView *temporary = [[ElectropaintView alloc] initWithFrame:NSMakeRect(0,0,64,64)
                isPreview:YES defaults:defaults];
            releasedView = temporary;
            releasedSettings = [temporary valueForKey:@"motionSettings"];
            (void)temporary.configureSheet;
            [temporary startAnimation];
            [temporary stopAnimation];
        }
        assert(!releasedView && !releasedSettings);
        [defaults removePersistentDomainForName:suite];
        [defaults synchronize];
        NSLog(@"Passed settings bounds, strict decimal and locale validation, atomic Save, Cancel, Restore Original, isolated persistence, corrupt preferences, independent views, reload, immediate application without reset, and lifecycle release.");
    }
    return 0;
}
