#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "EPMotionSettings.h"
#import "ElectropaintView.h"
#include "settings-test-support.h"
#include <assert.h>
#include <float.h>
#include <math.h>

static NSView *control(NSWindow *sheet, NSString *identifier) {
    for (NSView *view in sheet.contentView.subviews)
        if ([view.identifier isEqualToString:identifier]) return view;
    assert(false);
    return nil;
}

static NSSlider *slider(NSWindow *sheet, NSString *identifier) {
    NSView *view = control(sheet, identifier);
    assert([view isKindOfClass:[NSSlider class]]);
    return (NSSlider *)view;
}

static NSTextField *percentage(NSWindow *sheet, NSString *identifier) {
    NSView *view = control(sheet, identifier);
    assert([view isKindOfClass:[NSTextField class]]);
    NSTextField *label = (NSTextField *)view;
    assert(!label.editable && !label.selectable);
    return label;
}

static NSButton *button(NSWindow *sheet, NSString *title) {
    for (NSView *view in sheet.contentView.subviews) {
        if ([view isKindOfClass:[NSButton class]] && [((NSButton *)view).title isEqualToString:title])
            return (NSButton *)view;
    }
    assert(false);
    return nil;
}

static void click(NSWindow *sheet, NSString *title) {
    [button(sheet, title) performClick:nil];
}

static void checkLimits(EPMotionLimits actual, double spin, double flip) {
    assert(fabs(actual.maxSpinDegreesPerSecond - spin) < 1e-9);
    assert(fabs(actual.maxFlipDegreesPerSecond - flip) < 1e-9);
}

static void checkPercents(EPMotionLimits actual, NSInteger spin, NSInteger flip) {
    checkLimits(actual, EPMaximumMotionLimits.maxSpinDegreesPerSecond * spin / 100.0,
                EPMaximumMotionLimits.maxFlipDegreesPerSecond * flip / 100.0);
    assert(actual.maxSpinDegreesPerSecond > 0 && actual.maxFlipDegreesPerSecond > 0);
    assert(actual.maxSpinDegreesPerSecond <= EPMaximumMotionLimits.maxSpinDegreesPerSecond);
    assert(actual.maxFlipDegreesPerSecond <= EPMaximumMotionLimits.maxFlipDegreesPerSecond);
}

static EPState *engine(ElectropaintView *view) {
    Ivar ivar = class_getInstanceVariable([ElectropaintView class], "_engine");
    assert(ivar);
    return *(EPState **)((char *)(__bridge void *)view + ivar_getOffset(ivar));
}

static void change(NSSlider *slider, double value) {
    slider.doubleValue = value;
    assert([slider sendAction:slider.action to:slider.target]);
}

static void edit(NSWindow *sheet, double spin, double flip) {
    change(slider(sheet, @"maximumSpin"), spin);
    change(slider(sheet, @"maximumFlip"), flip);
}

static void checkDraft(NSWindow *sheet, NSInteger spin, NSInteger flip) {
    assert(slider(sheet, @"maximumSpin").integerValue == spin);
    assert(slider(sheet, @"maximumFlip").integerValue == flip);
    assert(([percentage(sheet, @"spinPercentage").stringValue
        isEqualToString:[NSString stringWithFormat:@"%ld%%", (long)spin]]));
    assert(([percentage(sheet, @"flipPercentage").stringValue
        isEqualToString:[NSString stringWithFormat:@"%ld%%", (long)flip]]));
}

static void setPreference(NSUserDefaults *defaults, NSString *key, id value) {
    if (value) [defaults setObject:value forKey:key];
    else [defaults removeObjectForKey:key];
}

static void preferenceCase(NSUserDefaults *defaults, EPMotionSettings *settings,
                           id spin, id flip, id legacySpin, id legacyFlip,
                           NSInteger expectedSpin, NSInteger expectedFlip) {
    setPreference(defaults, @"MaximumSpinPercent", spin);
    setPreference(defaults, @"MaximumFlipPercent", flip);
    setPreference(defaults, @"MaximumSpinDegreesPerSecond", legacySpin);
    setPreference(defaults, @"MaximumFlipDegreesPerSecond", legacyFlip);
    NSDictionary *before = defaults.dictionaryRepresentation;
    checkPercents([settings loadLimits], expectedSpin, expectedFlip);
    assert([before isEqualToDictionary:defaults.dictionaryRepresentation]);
}

static void testPreferences(NSUserDefaults *defaults, EPMotionSettings *settings) {
    preferenceCase(defaults, settings, nil, nil, nil, nil, 38, 20);
    preferenceCase(defaults, settings, nil, nil, @120, @120, 38, 20);
    preferenceCase(defaults, settings, nil, nil, @0, @0, 1, 1);
    preferenceCase(defaults, settings, nil, nil, @313.8, @600, 100, 100);
    preferenceCase(defaults, settings, @66, @80, @0, @0, 66, 80);
    preferenceCase(defaults, settings, @66, nil, @0, @120, 66, 20);
    preferenceCase(defaults, settings, nil, @80, @120, @0, 38, 80);
    preferenceCase(defaults, settings, @65.5, @79.6, nil, nil, 66, 80);
    preferenceCase(defaults, settings, @38.4, @20.4, nil, nil, 38, 20);
    preferenceCase(defaults, settings, nil, nil,
                   @(313.8 * 0.385), @123, 39, 21);
    preferenceCase(defaults, settings, nil, nil,
                   @(313.8 * 0.386), @(600 * 0.206), 39, 21);
    preferenceCase(defaults, settings, nil, nil,
                   @(313.8 * 0.384), @(600 * 0.204), 38, 20);
    preferenceCase(defaults, settings, nil, nil, @(-1), @(-DBL_MAX), 1, 1);
    preferenceCase(defaults, settings, nil, nil, @(DBL_MAX), @(DBL_MAX), 100, 100);
    preferenceCase(defaults, settings, @0, @(-DBL_MAX), @313.8, @600, 1, 1);
    preferenceCase(defaults, settings, @(DBL_MAX), @101, nil, nil, 100, 100);
    for (id invalid in @[@(NAN), @(INFINITY), @(-INFINITY), @"12", @[], @{}]) {
        preferenceCase(defaults, settings, nil, nil, invalid, invalid, 38, 20);
        preferenceCase(defaults, settings, invalid, invalid, @313.8, @600, 38, 20);
        preferenceCase(defaults, settings, invalid, @80, @313.8, @600, 38, 80);
        preferenceCase(defaults, settings, @66, invalid, @313.8, @600, 66, 20);
    }
    for (NSInteger value = 1; value <= 100; ++value)
        preferenceCase(defaults, settings, @(value), @(value), nil, nil, value, value);
    preferenceCase(defaults, settings, nil, nil, nil, nil, 38, 20);
}

static void testNativeSliders(NSWindow *sheet) {
    for (NSString *identifier in @[@"maximumSpin", @"maximumFlip"]) {
        NSSlider *s = slider(sheet, identifier);
        assert(s.minValue == 1 && s.maxValue == 100);
        assert(s.numberOfTickMarks == 100 && s.allowsTickMarkValuesOnly && s.continuous);
        assert([s.accessibilityLabel containsString:@"percent of original maximum"]);
        assert([s.accessibilityHelp containsString:@"1 to 100 percent"]);
        for (NSInteger value = 1; value <= 100; ++value) {
            assert([s tickMarkValueAtIndex:value - 1] == value);
            change(s, value);
            assert(s.doubleValue == value);
            assert(([s.accessibilityValueDescription isEqualToString:
                [NSString stringWithFormat:@"%ld percent of original maximum", (long)value]]));
            NSString *label = [identifier isEqualToString:@"maximumSpin"] ? @"spinPercentage" : @"flipPercentage";
            assert(([percentage(sheet, label).stringValue isEqualToString:
                [NSString stringWithFormat:@"%ld%%", (long)value]]));
        }
        change(s, -DBL_MAX);
        assert(s.doubleValue == 1);
        change(s, 0);
        assert(s.doubleValue == 1);
        change(s, DBL_MAX);
        assert(s.doubleValue == 100);
        change(s, 38.4);
        assert(s.doubleValue == 38);
        change(s, 38.6);
        assert(s.doubleValue == 39);
        change(s, 38.5);
        assert(s.doubleValue == 38 || s.doubleValue == 39);
        change(s, 38);
        [s accessibilityPerformIncrement];
        assert(s.doubleValue == 39);
        assert([s.accessibilityValueDescription isEqualToString:@"39 percent of original maximum"]);
        [s accessibilityPerformDecrement];
        assert(s.doubleValue == 38);
        change(s, 100);
        [s accessibilityPerformIncrement];
        assert(s.doubleValue == 100);
        change(s, 1);
        [s accessibilityPerformDecrement];
        assert(s.doubleValue == 1);
    }
    assert(sheet.initialFirstResponder == slider(sheet, @"maximumSpin"));
    assert(slider(sheet, @"maximumSpin").nextKeyView == slider(sheet, @"maximumFlip"));
    assert(slider(sheet, @"maximumFlip").nextKeyView == button(sheet, @"Save"));
    assert([button(sheet, @"Save").keyEquivalent isEqualToString:@"\r"]);
    assert([button(sheet, @"Cancel").keyEquivalent isEqualToString:@"\e"]);
    for (NSView *view in sheet.contentView.subviews)
        if ([view isKindOfClass:[NSTextField class]]) assert(!((NSTextField *)view).editable);
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
            NSNumber *spin = [defaults objectForKey:@"MaximumSpinPercent"];
            NSNumber *flip = [defaults objectForKey:@"MaximumFlipPercent"];
            assert(spin.doubleValue == spin.integerValue && flip.doubleValue == flip.integerValue);
            checkPercents(limits, spin.integerValue, flip.integerValue);
        }];
        testPreferences(defaults, settings);
        NSWindow *sheet = settings.sheet;
        checkDraft(sheet, 38, 20);
        checkLimits([settings loadLimits], 119.244, 120);
        assert(sheet == settings.sheet);
        testNativeSliders(sheet);
        NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,480)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [parent beginSheet:sheet completionHandler:nil];
        edit(sheet, 66, 80);
        checkDraft(sheet, 66, 80);
        assert(settings.sheet == sheet);
        checkDraft(sheet, 66, 80);
        assert(saves == 0);
        checkPercents([settings loadLimits], 38, 20);
        assert([defaults objectForKey:@"MaximumSpinPercent"] == nil);
        assert([defaults objectForKey:@"MaximumFlipPercent"] == nil);
        click(sheet, @"Save");
        assert(saves == 1 && !sheet.sheetParent);
        checkPercents(applied, 66, 80);
        checkLimits(applied, 207.108, 480);
        checkPercents([settings loadLimits], 66, 80);
        EPMotionSettings *reloaded = [[EPMotionSettings alloc] initWithDefaults:
            [[NSUserDefaults alloc] initWithSuiteName:suite] apply:nil];
        checkPercents([reloaded loadLimits], 66, 80);
        checkDraft(reloaded.sheet, 66, 80);

        sheet = settings.sheet;
        NSDictionary *beforeCancel = defaults.dictionaryRepresentation;
        [parent beginSheet:sheet completionHandler:nil];
        click(sheet, @"Restore Original");
        checkDraft(sheet, 100, 100);
        assert(saves == 1 && sheet.sheetParent == parent);
        assert([beforeCancel isEqualToDictionary:defaults.dictionaryRepresentation]);
        click(sheet, @"Cancel");
        assert(saves == 1 && !sheet.sheetParent);
        assert([beforeCancel isEqualToDictionary:defaults.dictionaryRepresentation]);
        checkDraft(sheet, 66, 80);
        sheet = settings.sheet;
        [parent beginSheet:sheet completionHandler:nil];
        edit(sheet, 1, 1);
        click(sheet, @"Cancel");
        checkDraft(settings.sheet, 66, 80);
        assert(saves == 1);
        click(sheet, @"Restore Original");
        click(sheet, @"Save");
        assert(saves == 2);
        checkLimits(applied, EPMaximumMotionLimits.maxSpinDegreesPerSecond,
                    EPMaximumMotionLimits.maxFlipDegreesPerSecond);
        sheet = settings.sheet;
        edit(sheet, 0, -1);
        click(sheet, @"Save");
        assert(saves == 3);
        checkLimits(applied, 3.138, 6);
        checkDraft(settings.sheet, 1, 1);
        edit(sheet, 38.6, 79.6);
        click(sheet, @"Save");
        assert(saves == 4);
        checkPercents(applied, 39, 80);
        assert([[defaults objectForKey:@"MaximumSpinPercent"] integerValue] == 39);
        assert([[defaults objectForKey:@"MaximumFlipPercent"] integerValue] == 80);

        preferenceCase(defaults, settings, nil, nil, @120, @120, 38, 20);
        NSDictionary *legacy = defaults.dictionaryRepresentation;
        sheet = settings.sheet;
        checkDraft(sheet, 38, 20);
        click(sheet, @"Restore Original");
        click(sheet, @"Cancel");
        assert([legacy isEqualToDictionary:defaults.dictionaryRepresentation]);
        sheet = settings.sheet;
        click(sheet, @"Save");
        assert([[defaults objectForKey:@"MaximumSpinDegreesPerSecond"] doubleValue] == 120);
        assert([[defaults objectForKey:@"MaximumFlipDegreesPerSecond"] doubleValue] == 120);
        assert([[defaults objectForKey:@"MaximumSpinPercent"] integerValue] == 38);
        assert([[defaults objectForKey:@"MaximumFlipPercent"] integerValue] == 20);

        preferenceCase(defaults, settings, @1, @25, @0, @0, 1, 25);
        ElectropaintView *a = [[ElectropaintView alloc] initWithFrame:NSMakeRect(0,0,64,64)
            isPreview:YES defaults:defaults];
        ElectropaintView *b = [[ElectropaintView alloc] initWithFrame:NSMakeRect(0,0,64,64)
            isPreview:NO defaults:defaults];
        assert(a && b && a.hasConfigureSheet && b.hasConfigureSheet);
        assert(a.configureSheet == a.configureSheet && a.configureSheet != b.configureSheet);
        checkPercents(ep_test_motion_state(engine(a)).limits, 1, 25);
        checkPercents(ep_test_motion_state(engine(b)).limits, 1, 25);
        NSWindow *aSheet = a.configureSheet;
        NSWindow *bSheet = b.configureSheet;
        edit(aSheet, 66, 80);
        checkDraft(aSheet, 66, 80);
        checkDraft(bSheet, 1, 25);
        EPState *originalEngine = engine(a);
        ep_step(originalEngine, 64, 64);
        EPMotionTestState original = ep_test_motion_state(originalEngine);
        click(aSheet, @"Save");
        assert(engine(a) == originalEngine && ep_test_motion_state(originalEngine).frames == original.frames);
        assert(ep_test_motion_state(originalEngine).random == original.random);
        checkPercents(ep_test_motion_state(engine(a)).limits, 66, 80);
        checkPercents(ep_test_motion_state(engine(b)).limits, 1, 25);
        checkDraft(bSheet, 1, 25);
        [b startAnimation];
        checkPercents(ep_test_motion_state(engine(b)).limits, 66, 80);
        [b stopAnimation];
        ElectropaintView *fresh = [[ElectropaintView alloc] initWithFrame:NSMakeRect(0,0,64,64)
            isPreview:YES defaults:[[NSUserDefaults alloc] initWithSuiteName:suite]];
        checkPercents(ep_test_motion_state(engine(fresh)).limits, 66, 80);
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
        checkPercents(ep_test_motion_state(engine(standard)).limits, 66, 80);
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
        NSLog(@"Passed all 100 native slider stops, bounds and fractional snapping, live percentage and accessibility labels, percent conversion, read-only preference migration and precedence, Save, Cancel, Restore Original, reload, independent views, application without reset, fixed domain, and lifecycle release. Real focused keyboard, dragging, VoiceOver, and complete visual checks remain pending on an unlocked desktop.");
    }
    return 0;
}
