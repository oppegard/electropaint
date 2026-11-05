#import "EPMotionSettings.h"
#import <ScreenSaver/ScreenSaver.h>
#include <math.h>

static NSString *const SpinPercentKey = @"MaximumSpinPercent";
static NSString *const FlipPercentKey = @"MaximumFlipPercent";
static NSString *const LegacySpinKey = @"MaximumSpinDegreesPerSecond";
static NSString *const LegacyFlipKey = @"MaximumFlipDegreesPerSecond";

typedef struct {
    NSInteger spin, flip;
} EPMotionPercentages;

static NSInteger boundedPercent(double value) {
    return lround(fmin(100, fmax(1, value)));
}

static NSInteger percentFromDegrees(double degrees, double maximum) {
    return boundedPercent(fmin(maximum, fmax(0, degrees)) / maximum * 100);
}

static NSInteger storedPercent(id percent, id legacy, double maximum, double defaultRate) {
    NSInteger fallback = percentFromDegrees(defaultRate, maximum);
    id value = percent ?: legacy;
    if (![value isKindOfClass:[NSNumber class]]) return fallback;
    double number = [value doubleValue];
    if (!isfinite(number)) return fallback;
    return percent ? boundedPercent(number) : percentFromDegrees(number, maximum);
}

static EPMotionLimits limitsFromPercentages(EPMotionPercentages percentages) {
    return (EPMotionLimits){
        EPMaximumMotionLimits.maxSpinDegreesPerSecond * percentages.spin / 100.0,
        EPMaximumMotionLimits.maxFlipDegreesPerSecond * percentages.flip / 100.0
    };
}

@implementation EPMotionSettings {
    NSUserDefaults *_defaults;
    void (^_apply)(EPMotionLimits);
    NSWindow *_sheet;
    NSSlider *_spinSlider, *_flipSlider;
    NSTextField *_spinPercentage, *_flipPercentage;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                          apply:(void (^)(EPMotionLimits))apply {
    self = [super init];
    if (!self) return nil;
    _defaults = defaults ?: [ScreenSaverDefaults defaultsForModuleWithName:
        @"com.oppegard.electropaint.screensaver"];
    _apply = [apply copy];
    return self;
}

- (EPMotionPercentages)loadPercentages {
    return (EPMotionPercentages){
        storedPercent([_defaults objectForKey:SpinPercentKey], [_defaults objectForKey:LegacySpinKey],
                      EPMaximumMotionLimits.maxSpinDegreesPerSecond, EPDefaultMotionLimits.maxSpinDegreesPerSecond),
        storedPercent([_defaults objectForKey:FlipPercentKey], [_defaults objectForKey:LegacyFlipKey],
                      EPMaximumMotionLimits.maxFlipDegreesPerSecond, EPDefaultMotionLimits.maxFlipDegreesPerSecond)
    };
}

- (EPMotionLimits)loadLimits {
    return limitsFromPercentages([self loadPercentages]);
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    [_sheet.contentView addSubview:label];
    return label;
}

- (NSSlider *)slider:(NSString *)identifier label:(NSString *)label y:(CGFloat)y {
    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(190, y, 250, 32)];
    slider.identifier = identifier;
    slider.minValue = 1;
    slider.maxValue = 100;
    slider.numberOfTickMarks = 100;
    slider.allowsTickMarkValuesOnly = YES;
    slider.continuous = YES;
    slider.target = self;
    slider.action = @selector(percentageChanged:);
    slider.accessibilityLabel = label;
    slider.accessibilityHelp = @"Percentage of the original maximum, from 1 to 100 percent.";
    [_sheet.contentView addSubview:slider];
    return slider;
}

- (NSButton *)button:(NSString *)title x:(CGFloat)x width:(CGFloat)width action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.frame = NSMakeRect(x, 20, width, 32);
    [_sheet.contentView addSubview:button];
    return button;
}

- (void)createSheet {
    _sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 530, 260)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    _sheet.title = @"Electropaint Settings";
    _sheet.releasedWhenClosed = NO;
    NSTextField *title = [self label:@"Rotation limits" frame:NSMakeRect(24, 216, 482, 22)];
    title.font = [NSFont boldSystemFontOfSize:15];
    [self label:@"Set each limit as a percentage of its original maximum."
          frame:NSMakeRect(24, 188, 482, 20)];
    [self label:@"Maximum spin" frame:NSMakeRect(24, 146, 160, 20)];
    _spinSlider = [self slider:@"maximumSpin" label:@"Maximum spin, percent of original maximum" y:136];
    _spinPercentage = [self label:@"" frame:NSMakeRect(450, 146, 56, 20)];
    _spinPercentage.identifier = @"spinPercentage";
    _spinPercentage.alignment = NSTextAlignmentRight;
    [self label:@"Maximum flip" frame:NSMakeRect(24, 98, 160, 20)];
    _flipSlider = [self slider:@"maximumFlip" label:@"Maximum flip, percent of original maximum" y:88];
    _flipPercentage = [self label:@"" frame:NSMakeRect(450, 98, 56, 20)];
    _flipPercentage.identifier = @"flipPercentage";
    _flipPercentage.alignment = NSTextAlignmentRight;
    [self button:@"Restore Original" x:20 width:150 action:@selector(restoreOriginal:)];
    NSButton *cancel = [self button:@"Cancel" x:322 width:88 action:@selector(cancel:)];
    cancel.keyEquivalent = @"\e";
    NSButton *save = [self button:@"Save" x:418 width:88 action:@selector(save:)];
    save.keyEquivalent = @"\r";
    _spinSlider.nextKeyView = _flipSlider;
    _flipSlider.nextKeyView = save;
    _sheet.initialFirstResponder = _spinSlider;
}

- (void)percentageChanged:(NSSlider *)sender {
    NSTextField *label = sender == _spinSlider ? _spinPercentage : _flipPercentage;
    label.stringValue = [NSString stringWithFormat:@"%ld%%", (long)sender.integerValue];
    sender.accessibilityValueDescription = [NSString stringWithFormat:@"%ld percent of original maximum",
                                            (long)sender.integerValue];
}

- (void)fillPercentages:(EPMotionPercentages)percentages {
    _spinSlider.integerValue = percentages.spin;
    _flipSlider.integerValue = percentages.flip;
    [self percentageChanged:_spinSlider];
    [self percentageChanged:_flipSlider];
}

- (NSWindow *)sheet {
    if (!_sheet) [self createSheet];
    if (!_sheet.sheetParent) [self fillPercentages:[self loadPercentages]];
    return _sheet;
}

- (void)closeWithResponse:(NSModalResponse)response {
    [_sheet.sheetParent endSheet:_sheet returnCode:response];
    [_sheet orderOut:nil];
}

- (void)save:(id)sender {
    (void)sender;
    EPMotionPercentages percentages = {_spinSlider.integerValue, _flipSlider.integerValue};
    [_defaults setInteger:percentages.spin forKey:SpinPercentKey];
    [_defaults setInteger:percentages.flip forKey:FlipPercentKey];
    [_defaults synchronize];
    if (_apply) _apply(limitsFromPercentages(percentages));
    [self closeWithResponse:NSModalResponseOK];
}

- (void)cancel:(id)sender {
    (void)sender;
    [self fillPercentages:[self loadPercentages]];
    [self closeWithResponse:NSModalResponseCancel];
}

- (void)restoreOriginal:(id)sender {
    (void)sender;
    [self fillPercentages:(EPMotionPercentages){100, 100}];
}
@end
