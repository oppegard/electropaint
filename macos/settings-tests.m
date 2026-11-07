#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "EPMotionSettings.h"
#import "ElectropaintView.h"
#include "settings-test-support.h"
#include <assert.h>
#include <float.h>
#include <math.h>

@interface EPTestDefaults : NSUserDefaults
@property NSString *domainName;
@property NSMutableArray<NSString *> *reads;
@property NSMutableArray<NSString *> *writes;
@end

@implementation EPTestDefaults
- (id)objectForKey:(NSString *)key {
    [self.reads addObject:key];
    return [super objectForKey:key];
}
- (void)setDouble:(double)value forKey:(NSString *)key {
    [self.writes addObject:key];
    [super setDouble:value forKey:key];
}
@end

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

static NSTextField *rate(NSWindow *sheet, NSString *identifier) {
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

static void checkDraft(NSWindow *sheet, double spin, double flip) {
    checkLimits((EPMotionLimits){slider(sheet, @"maximumSpin").doubleValue,
        slider(sheet, @"maximumFlip").doubleValue}, spin, flip);
}

static void setPreference(NSUserDefaults *defaults, NSString *key, id value) {
    if (value) [defaults setObject:value forKey:key];
    else [defaults removeObjectForKey:key];
}

static void preferenceCase(EPTestDefaults *defaults, EPMotionSettings *settings,
                           id spin, id flip, double expectedSpin, double expectedFlip) {
    setPreference(defaults, @"MaximumSpinRateDegreesPerSecond", spin);
    setPreference(defaults, @"MaximumFlipRateDegreesPerSecond", flip);
    NSDictionary *before = [defaults persistentDomainForName:defaults.domainName] ?: @{};
    NSUInteger writes = defaults.writes.count;
    [defaults.reads removeAllObjects];
    checkLimits([settings loadLimits], expectedSpin, expectedFlip);
    assert(([defaults.reads isEqualToArray:@[@"MaximumSpinRateDegreesPerSecond", @"MaximumFlipRateDegreesPerSecond"]]));
    assert(defaults.writes.count == writes);
    assert([before isEqualToDictionary:([defaults persistentDomainForName:defaults.domainName] ?: @{})]);
}

static void testPreferences(EPTestDefaults *defaults, EPMotionSettings *settings) {
    preferenceCase(defaults, settings, nil, nil, 313.8, 600);
    [defaults setObject:@0 forKey:@"MaximumSpinPercent"];
    [defaults setObject:@25 forKey:@"MaximumFlipPercent"];
    [defaults setObject:@120 forKey:@"MaximumSpinDegreesPerSecond"];
    [defaults setObject:@120 forKey:@"MaximumFlipDegreesPerSecond"];
    preferenceCase(defaults, settings, nil, nil, 313.8, 600);
    preferenceCase(defaults, settings, @66, @80, 66, 80);
    preferenceCase(defaults, settings, @66, nil, 66, 600);
    preferenceCase(defaults, settings, nil, @80, 313.8, 80);
    preferenceCase(defaults, settings, @65.54, @79.56, 65.5, 79.6);
    preferenceCase(defaults, settings, @38.45, @20.45, 38.5, 20.5);
    preferenceCase(defaults, settings, @0, @(-DBL_MAX), 0.1, 0.1);
    preferenceCase(defaults, settings, @(DBL_MAX), @601, 313.8, 600);
    preferenceCase(defaults, settings, @313.84, @600.04, 313.8, 600);
    for (id invalid in @[@(NAN), @(INFINITY), @(-INFINITY), @"12", @[], @{}]) {
        preferenceCase(defaults, settings, invalid, invalid, 313.8, 600);
        preferenceCase(defaults, settings, invalid, @80, 313.8, 80);
        preferenceCase(defaults, settings, @66, invalid, 66, 600);
    }
    for (NSInteger tenth = 1; tenth <= 6000; ++tenth) {
        double value = tenth / 10.0;
        preferenceCase(defaults, settings, @(value), @(value), fmin(313.8, value), value);
    }
    preferenceCase(defaults, settings, nil, nil, 313.8, 600);
}

static void arrow(NSSlider *slider, unichar key) {
    NSString *characters = [NSString stringWithCharacters:&key length:1];
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:0 timestamp:0 windowNumber:slider.window.windowNumber context:nil
        characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:0];
    [slider keyDown:event];
}

static void testNativeSliders(NSWindow *sheet) {
    for (NSString *identifier in @[@"maximumSpin", @"maximumFlip"]) {
        BOOL spin = [identifier isEqualToString:@"maximumSpin"];
        NSSlider *s = slider(sheet, identifier);
        NSString *labelID = spin ? @"spinRate" : @"flipRate";
        double maximum = spin ? 313.8 : 600;
        assert(s.minValue == 0.1 && s.maxValue == maximum);
        assert(s.numberOfTickMarks == 0 && !s.allowsTickMarkValuesOnly && s.continuous);
        assert([s.accessibilityLabel containsString:@"degrees per second"]);
        for (NSInteger tenth = 1; tenth <= lround(maximum * 10); ++tenth) {
            double value = tenth / 10.0;
            change(s, value);
            assert(fabs(s.doubleValue - value) < 1e-9);
            NSString *expected = tenth % 10 == 0 ?
                [NSString stringWithFormat:@"%ld°/second", (long)(tenth / 10)] :
                [NSString stringWithFormat:@"%ld.%ld°/second", (long)(tenth / 10), (long)(tenth % 10)];
            assert([rate(sheet, labelID).stringValue isEqualToString:expected]);
            assert([s.accessibilityValueDescription isEqualToString:expected]);
        }
        for (NSNumber *low in @[@(-DBL_MAX), @0, @0.04]) {
            change(s, low.doubleValue);
            assert(s.doubleValue == 0.1);
            assert([rate(sheet, labelID).stringValue isEqualToString:@"0.1°/second"]);
        }
        for (NSNumber *high in @[@(DBL_MAX), @(INFINITY), @(-INFINITY), @(NAN)]) {
            change(s, high.doubleValue);
            assert(s.doubleValue == maximum);
        }
        change(s, 38.44);
        assert(s.doubleValue == 38.4);
        change(s, 38.46);
        assert(s.doubleValue == 38.5);
        change(s, 38.45);
        assert(s.doubleValue == 38.5);
        change(s, 38);
        assert([s accessibilityPerformIncrement]);
        assert(s.doubleValue == 38.1);
        assert([rate(sheet, labelID).stringValue isEqualToString:@"38.1°/second"]);
        assert([s accessibilityPerformDecrement]);
        assert(s.doubleValue == 38);
        arrow(s, NSRightArrowFunctionKey);
        assert(s.doubleValue == 38.1);
        arrow(s, NSLeftArrowFunctionKey);
        assert(s.doubleValue == 38);
        arrow(s, NSUpArrowFunctionKey);
        assert(s.doubleValue == 38.1);
        arrow(s, NSDownArrowFunctionKey);
        assert(s.doubleValue == 38);
        change(s, maximum);
        [s accessibilityPerformIncrement];
        arrow(s, NSRightArrowFunctionKey);
        assert(s.doubleValue == maximum);
        change(s, 0.1);
        [s accessibilityPerformDecrement];
        arrow(s, NSLeftArrowFunctionKey);
        assert(s.doubleValue == 0.1);
    }
    assert(sheet.initialFirstResponder == slider(sheet, @"maximumSpin"));
    NSArray<NSView *> *loop = @[slider(sheet, @"maximumSpin"), control(sheet, @"spinHelp"),
        slider(sheet, @"maximumFlip"), control(sheet, @"flipHelp"), button(sheet, @"Reset"),
        button(sheet, @"Cancel"), button(sheet, @"Save")];
    for (NSUInteger i = 0; i < loop.count; ++i)
        assert(loop[i].nextKeyView == loop[(i + 1) % loop.count]);
    assert([button(sheet, @"Save").keyEquivalent isEqualToString:@"\r"]);
    assert([button(sheet, @"Cancel").keyEquivalent isEqualToString:@"\e"]);
    NSArray *helps = @[@"Limits how fast the squares spin. Lower values reduce fast spins without slowing the rest of the animation.",
        @"Limits how fast the squares flip. Lower values reduce fast flips without slowing the rest of the animation."];
    for (NSUInteger i = 0; i < 2; ++i) {
        NSButton *help = (NSButton *)control(sheet, i == 0 ? @"spinHelp" : @"flipHelp");
        assert([help isKindOfClass:[NSButton class]] && help.image && !help.bordered);
        assert([help.toolTip isEqualToString:helps[i]]);
        assert([help.accessibilityHelp isEqualToString:helps[i]]);
        assert([help.accessibilityLabel isEqualToString:i == 0 ? @"About maximum spin" : @"About maximum flip"]);
        assert(help.target && help.action);
    }
    BOOL descriptionFound = NO;
    for (NSView *view in sheet.contentView.subviews) {
        if ([view isKindOfClass:[NSTextField class]]) {
            NSTextField *text = (NSTextField *)view;
            assert(!text.editable);
            if ([text.stringValue isEqualToString:@"Limit spin and flip speed. Reset restores the original limits of the 1994 Mello script."]) {
                descriptionFound = YES;
                assert(text.cell.wraps);
            }
        }
    }
    assert(descriptionFound);
    assert(slider(sheet, @"maximumSpin").frame.origin.x == slider(sheet, @"maximumFlip").frame.origin.x);
    assert(rate(sheet, @"spinRate").frame.origin.x == rate(sheet, @"flipRate").frame.origin.x);
}

static void testHelp(NSWindow *parent, NSWindow *sheet) {
    __block NSPopover *shown;
    __block unsigned opens = 0;
    __block unsigned closes = 0;
    __block NSString *expected;
    NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
    id openObserver = [notifications addObserverForName:NSPopoverWillShowNotification object:nil queue:nil
        usingBlock:^(NSNotification *notification) {
            NSPopover *popover = notification.object;
            if (shown) assert(shown == popover);
            shown = popover;
            ++opens;
            assert(popover.behavior == NSPopoverBehaviorTransient);
            NSArray *content = popover.contentViewController.view.subviews;
            assert(content.count == 1 && [content[0] isKindOfClass:[NSTextField class]]);
            NSTextField *text = content[0];
            assert([text.stringValue isEqualToString:expected]);
            assert(text.cell.wraps);
            NSSize fitting = [text sizeThatFits:NSMakeSize(text.frame.size.width, CGFLOAT_MAX)];
            assert(text.frame.size.height >= fitting.height);
        }];
    id closeObserver = [notifications addObserverForName:NSPopoverWillCloseNotification object:nil queue:nil
        usingBlock:^(NSNotification *notification) {
            assert(notification.object == shown);
            ++closes;
        }];
    [parent orderFront:nil];
    [parent beginSheet:sheet completionHandler:nil];
    edit(sheet, 66.1, 80.2);
    NSButton *spin = (NSButton *)control(sheet, @"spinHelp");
    NSButton *flip = (NSButton *)control(sheet, @"flipHelp");
    expected = spin.toolTip;
    [spin performClick:nil];
    assert(opens == 1 && shown.isShown);
    shown.animates = NO;
    expected = flip.toolTip;
    [flip performClick:nil];
    assert(opens == 2 && closes == 1 && shown.isShown);
    NSEvent *escape = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:0 timestamp:0 windowNumber:sheet.windowNumber context:nil
        characters:@"\e" charactersIgnoringModifiers:@"\e" isARepeat:NO keyCode:53];
    assert([sheet performKeyEquivalent:escape]);
    assert(closes == 2 && !shown.isShown && sheet.sheetParent == parent);
    checkDraft(sheet, 66.1, 80.2);
    assert([sheet performKeyEquivalent:escape]);
    assert(!sheet.sheetParent);
    checkDraft(sheet, 313.8, 600);
    [parent beginSheet:sheet completionHandler:nil];
    expected = spin.toolTip;
    [spin performClick:nil];
    assert(opens == 3 && shown.isShown);
    click(sheet, @"Cancel");
    assert(closes == 3 && !shown.isShown && !sheet.sheetParent);
    [parent orderOut:nil];
    [notifications removeObserver:openObserver];
    [notifications removeObserver:closeObserver];
}

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyProhibited;
        [app finishLaunching];
        NSString *suite = [@"com.oppegard.electropaint.settings-tests." stringByAppendingString:NSUUID.UUID.UUIDString];
        EPTestDefaults *defaults = [[EPTestDefaults alloc] initWithSuiteName:suite];
        defaults.domainName = suite;
        defaults.reads = [NSMutableArray array];
        defaults.writes = [NSMutableArray array];
        __block EPMotionLimits applied = {-1, -1};
        __block unsigned saves = 0;
        EPMotionSettings *settings = [[EPMotionSettings alloc] initWithDefaults:defaults apply:^(EPMotionLimits limits) {
            applied = limits;
            ++saves;
            assert(defaults.writes.count == saves * 2);
            checkLimits(limits, [defaults doubleForKey:@"MaximumSpinRateDegreesPerSecond"],
                [defaults doubleForKey:@"MaximumFlipRateDegreesPerSecond"]);
        }];
        testPreferences(defaults, settings);
        NSDictionary *firstUse = [defaults persistentDomainForName:suite];
        NSWindow *sheet = settings.sheet;
        checkDraft(sheet, 313.8, 600);
        assert([rate(sheet, @"spinRate").stringValue isEqualToString:@"313.8°/second"]);
        assert([rate(sheet, @"flipRate").stringValue isEqualToString:@"600°/second"]);
        assert(sheet == settings.sheet);
        testNativeSliders(sheet);
        assert(defaults.writes.count == 0);
        assert([firstUse isEqualToDictionary:[defaults persistentDomainForName:suite]]);
        NSWindow *parent = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,480)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        testHelp(parent, settings.sheet);
        assert(saves == 0 && defaults.writes.count == 0);
        sheet = settings.sheet;
        [parent beginSheet:sheet completionHandler:nil];
        edit(sheet, 66.1, 80.2);
        checkDraft(sheet, 66.1, 80.2);
        assert(settings.sheet == sheet);
        checkDraft(sheet, 66.1, 80.2);
        assert(saves == 0 && defaults.writes.count == 0);
        checkLimits([settings loadLimits], 313.8, 600);
        click(sheet, @"Save");
        assert(saves == 1 && !sheet.sheetParent);
        checkLimits(applied, 66.1, 80.2);
        checkLimits([settings loadLimits], 66.1, 80.2);
        EPMotionSettings *reloaded = [[EPMotionSettings alloc] initWithDefaults:
            [[NSUserDefaults alloc] initWithSuiteName:suite] apply:nil];
        checkLimits([reloaded loadLimits], 66.1, 80.2);
        checkDraft(reloaded.sheet, 66.1, 80.2);

        sheet = settings.sheet;
        NSDictionary *beforeCancel = [defaults persistentDomainForName:suite];
        [parent beginSheet:sheet completionHandler:nil];
        click(sheet, @"Reset");
        checkDraft(sheet, 313.8, 600);
        assert(saves == 1 && sheet.sheetParent == parent);
        assert(defaults.writes.count == 2);
        assert([beforeCancel isEqualToDictionary:[defaults persistentDomainForName:suite]]);
        click(sheet, @"Cancel");
        assert(saves == 1 && !sheet.sheetParent);
        assert([beforeCancel isEqualToDictionary:[defaults persistentDomainForName:suite]]);
        checkDraft(sheet, 66.1, 80.2);
        sheet = settings.sheet;
        [parent beginSheet:sheet completionHandler:nil];
        edit(sheet, 0.1, 0.1);
        click(sheet, @"Cancel");
        checkDraft(settings.sheet, 66.1, 80.2);
        assert(saves == 1 && defaults.writes.count == 2);
        click(sheet, @"Reset");
        click(sheet, @"Save");
        assert(saves == 2);
        checkLimits(applied, 313.8, 600);
        sheet = settings.sheet;
        edit(sheet, 0, -1);
        click(sheet, @"Save");
        assert(saves == 3);
        checkLimits(applied, 0.1, 0.1);
        checkDraft(settings.sheet, 0.1, 0.1);
        edit(sheet, 38.46, 79.66);
        click(sheet, @"Save");
        assert(saves == 4);
        checkLimits(applied, 38.5, 79.7);
        assert([[defaults objectForKey:@"MaximumSpinPercent"] integerValue] == 0);
        assert([[defaults objectForKey:@"MaximumFlipPercent"] integerValue] == 25);
        assert([[defaults objectForKey:@"MaximumSpinDegreesPerSecond"] doubleValue] == 120);
        assert([[defaults objectForKey:@"MaximumFlipDegreesPerSecond"] doubleValue] == 120);
        preferenceCase(defaults, settings, @0.1, @25, 0.1, 25);
        ElectropaintView *a = [[ElectropaintView alloc] initWithFrame:NSMakeRect(0,0,64,64)
            isPreview:YES defaults:defaults];
        ElectropaintView *b = [[ElectropaintView alloc] initWithFrame:NSMakeRect(0,0,64,64)
            isPreview:NO defaults:defaults];
        assert(a && b && a.hasConfigureSheet && b.hasConfigureSheet);
        assert(a.configureSheet == a.configureSheet && a.configureSheet != b.configureSheet);
        checkLimits(ep_test_motion_state(engine(a)).limits, 0.1, 25);
        checkLimits(ep_test_motion_state(engine(b)).limits, 0.1, 25);
        NSWindow *aSheet = a.configureSheet;
        NSWindow *bSheet = b.configureSheet;
        edit(aSheet, 66, 80);
        checkDraft(aSheet, 66, 80);
        checkDraft(bSheet, 0.1, 25);
        EPState *originalEngine = engine(a);
        ep_step(originalEngine, 64, 64);
        EPMotionTestState original = ep_test_motion_state(originalEngine);
        click(aSheet, @"Save");
        assert(engine(a) == originalEngine && ep_test_motion_state(originalEngine).frames == original.frames);
        assert(ep_test_motion_state(originalEngine).random == original.random);
        checkLimits(ep_test_motion_state(engine(a)).limits, 66, 80);
        checkLimits(ep_test_motion_state(engine(b)).limits, 0.1, 25);
        checkDraft(bSheet, 0.1, 25);
        [b startAnimation];
        checkLimits(ep_test_motion_state(engine(b)).limits, 66, 80);
        [b stopAnimation];
        ElectropaintView *fresh = [[ElectropaintView alloc] initWithFrame:NSMakeRect(0,0,64,64)
            isPreview:YES defaults:[[NSUserDefaults alloc] initWithSuiteName:suite]];
        checkLimits(ep_test_motion_state(engine(fresh)).limits, 66, 80);
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
        checkLimits(ep_test_motion_state(engine(standard)).limits, 66, 80);
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
        NSLog(@"Passed rate preference and slider tenths, bounds, rounding, arrow and accessibility steps, live rate labels, help metadata and key loop, ignored older keys, Save, Cancel, Reset, reload, independent views, application without reset, fixed domain, and lifecycle release. Live dragging, focused keyboard, help presentation, VoiceOver, and visual checks remain for the unlocked desktop.");
    }
    return 0;
}
