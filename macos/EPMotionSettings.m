#import "EPMotionSettings.h"
#import <ScreenSaver/ScreenSaver.h>
#include <math.h>

static NSString *const SpinRateKey = @"MaximumSpinRateDegreesPerSecond";
static NSString *const FlipRateKey = @"MaximumFlipRateDegreesPerSecond";
static NSString *const SpinHelp = @"Limits how fast the squares spin. Lower values reduce fast spins without slowing the rest of the animation.";
static NSString *const FlipHelp = @"Limits how fast the squares flip. Lower values reduce fast flips without slowing the rest of the animation.";

static double normalizedRate(double value, double maximum) {
    if (!isfinite(value)) return maximum;
    return round(fmin(maximum, fmax(0.1, value)) * 10) / 10;
}

static double storedRate(id value, double maximum) {
    if (![value isKindOfClass:[NSNumber class]]) return maximum;
    return normalizedRate([value doubleValue], maximum);
}

static NSString *rateText(double value) {
    NSString *number = [NSString stringWithFormat:@"%.1f", value];
    if ([number hasSuffix:@".0"]) number = [number substringToIndex:number.length - 2];
    return [number stringByAppendingString:@"°/second"];
}

@interface EPRateSlider : NSSlider
@end

@implementation EPRateSlider
- (void)setDoubleValue:(double)value {
    [super setDoubleValue:normalizedRate(value, self.maxValue)];
}

- (void)step:(double)delta {
    self.doubleValue += delta;
    [self sendAction:self.action to:self.target];
}

- (void)keyDown:(NSEvent *)event {
    NSString *characters = event.charactersIgnoringModifiers;
    NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (characters.length == 1 && !(modifiers & (NSEventModifierFlagShift |
        NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand))) {
        unichar key = [characters characterAtIndex:0];
        if (key == NSRightArrowFunctionKey || key == NSUpArrowFunctionKey) {
            [self step:0.1];
            return;
        }
        if (key == NSLeftArrowFunctionKey || key == NSDownArrowFunctionKey) {
            [self step:-0.1];
            return;
        }
    }
    [super keyDown:event];
}

- (BOOL)accessibilityPerformIncrement {
    [self step:0.1];
    return YES;
}

- (BOOL)accessibilityPerformDecrement {
    [self step:-0.1];
    return YES;
}
@end

@interface EPMotionSettingsWindow : NSWindow
@property (weak) NSPopover *helpPopover;
@end

@implementation EPMotionSettingsWindow
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (self.helpPopover.isShown && [event.charactersIgnoringModifiers isEqualToString:@"\e"]) {
        [self.helpPopover close];
        return YES;
    }
    return [super performKeyEquivalent:event];
}
@end

@implementation EPMotionSettings {
    NSUserDefaults *_defaults;
    void (^_apply)(EPMotionLimits);
    EPMotionSettingsWindow *_sheet;
    NSSlider *_spinSlider, *_flipSlider;
    NSTextField *_spinRate, *_flipRate;
    NSPopover *_helpPopover;
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

- (EPMotionLimits)loadLimits {
    return (EPMotionLimits){
        storedRate([_defaults objectForKey:SpinRateKey], EPMaximumMotionLimits.maxSpinDegreesPerSecond),
        storedRate([_defaults objectForKey:FlipRateKey], EPMaximumMotionLimits.maxFlipDegreesPerSecond)
    };
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    [_sheet.contentView addSubview:label];
    return label;
}

- (NSSlider *)slider:(NSString *)identifier label:(NSString *)label help:(NSString *)help
             maximum:(double)maximum x:(CGFloat)x width:(CGFloat)width y:(CGFloat)y {
    NSSlider *slider = [[EPRateSlider alloc] initWithFrame:NSMakeRect(x, y - 6, width, 32)];
    slider.identifier = identifier;
    slider.minValue = 0.1;
    slider.maxValue = maximum;
    slider.continuous = YES;
    slider.target = self;
    slider.action = @selector(rateChanged:);
    slider.accessibilityLabel = label;
    slider.accessibilityHelp = help;
    [_sheet.contentView addSubview:slider];
    return slider;
}

- (NSButton *)help:(NSString *)help label:(NSString *)label identifier:(NSString *)identifier
                 x:(CGFloat)x y:(CGFloat)y {
    NSButton *button = [NSButton buttonWithImage:
        [NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:label]
        target:self action:@selector(showHelp:)];
    button.frame = NSMakeRect(x, y - 2, 24, 24);
    button.bordered = NO;
    button.identifier = identifier;
    button.toolTip = help;
    button.accessibilityLabel = label;
    button.accessibilityHelp = help;
    [_sheet.contentView addSubview:button];
    return button;
}

- (NSButton *)button:(NSString *)title x:(CGFloat)x width:(CGFloat)width action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.frame = NSMakeRect(x, 20, width, 32);
    [_sheet.contentView addSubview:button];
    return button;
}

- (void)createSheet {
    CGFloat width = 590;
    _sheet = [[EPMotionSettingsWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, 280)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    _sheet.title = @"Electropaint Settings";
    _sheet.releasedWhenClosed = NO;
    NSTextField *title = [self label:@"Rotation limits" frame:NSMakeRect(24, 236, width - 48, 22)];
    title.font = [NSFont boldSystemFontOfSize:15];
    NSTextField *description = [NSTextField wrappingLabelWithString:
        @"Limit spin and flip speed. Reset restores the original limits of the 1994 Mello script."];
    description.frame = NSMakeRect(24, 190, width - 48, 36);
    [_sheet.contentView addSubview:description];
    NSTextField *spinLabel = [self label:@"Maximum spin" frame:NSZeroRect];
    NSTextField *flipLabel = [self label:@"Maximum flip" frame:NSZeroRect];
    [spinLabel sizeToFit];
    [flipLabel sizeToFit];
    CGFloat labelWidth = ceil(fmax(spinLabel.frame.size.width, flipLabel.frame.size.width));
    spinLabel.frame = NSMakeRect(24, 146, labelWidth, 20);
    flipLabel.frame = NSMakeRect(24, 98, labelWidth, 20);
    spinLabel.alignment = flipLabel.alignment = NSTextAlignmentRight;
    CGFloat helpX = NSMaxX(spinLabel.frame) + 4;
    NSButton *spinHelp = [self help:SpinHelp label:@"About maximum spin" identifier:@"spinHelp" x:helpX y:146];
    NSButton *flipHelp = [self help:FlipHelp label:@"About maximum flip" identifier:@"flipHelp" x:helpX y:98];
    _spinRate = [self label:@"313.8°/second" frame:NSZeroRect];
    _flipRate = [self label:@"600°/second" frame:NSZeroRect];
    [_spinRate sizeToFit];
    [_flipRate sizeToFit];
    CGFloat rateWidth = ceil(fmax(_spinRate.frame.size.width, _flipRate.frame.size.width)) + 4;
    CGFloat rateX = width - 24 - rateWidth;
    _spinRate.frame = NSMakeRect(rateX, 146, rateWidth, 20);
    _flipRate.frame = NSMakeRect(rateX, 98, rateWidth, 20);
    _spinRate.identifier = @"spinRate";
    _flipRate.identifier = @"flipRate";
    _spinRate.alignment = _flipRate.alignment = NSTextAlignmentRight;
    CGFloat sliderX = NSMaxX(spinHelp.frame) + 8;
    CGFloat sliderWidth = rateX - 8 - sliderX;
    _spinSlider = [self slider:@"maximumSpin" label:@"Maximum spin, degrees per second" help:SpinHelp
        maximum:EPMaximumMotionLimits.maxSpinDegreesPerSecond x:sliderX width:sliderWidth y:146];
    _flipSlider = [self slider:@"maximumFlip" label:@"Maximum flip, degrees per second" help:FlipHelp
        maximum:EPMaximumMotionLimits.maxFlipDegreesPerSecond x:sliderX width:sliderWidth y:98];
    NSButton *reset = [self button:@"Reset" x:20 width:88 action:@selector(reset:)];
    NSButton *cancel = [self button:@"Cancel" x:width - 208 width:88 action:@selector(cancel:)];
    cancel.keyEquivalent = @"\e";
    NSButton *save = [self button:@"Save" x:width - 112 width:88 action:@selector(save:)];
    save.keyEquivalent = @"\r";
    _spinSlider.nextKeyView = spinHelp;
    spinHelp.nextKeyView = _flipSlider;
    _flipSlider.nextKeyView = flipHelp;
    flipHelp.nextKeyView = reset;
    reset.nextKeyView = cancel;
    cancel.nextKeyView = save;
    save.nextKeyView = _spinSlider;
    _sheet.initialFirstResponder = _spinSlider;
}

- (void)showHelp:(NSButton *)sender {
    [_helpPopover close];
    if (!_helpPopover) {
        _helpPopover = [[NSPopover alloc] init];
        _helpPopover.behavior = NSPopoverBehaviorTransient;
        _sheet.helpPopover = _helpPopover;
    }
    NSTextField *text = [NSTextField wrappingLabelWithString:sender.toolTip];
    NSSize size = [text sizeThatFits:NSMakeSize(280, CGFLOAT_MAX)];
    text.frame = NSMakeRect(16, 16, 280, ceil(size.height));
    NSViewController *content = [[NSViewController alloc] init];
    content.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 312, ceil(size.height) + 32)];
    [content.view addSubview:text];
    _helpPopover.contentViewController = content;
    [_helpPopover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSRectEdgeMaxY];
}

- (void)rateChanged:(NSSlider *)sender {
    sender.doubleValue = normalizedRate(sender.doubleValue, sender.maxValue);
    NSTextField *label = sender == _spinSlider ? _spinRate : _flipRate;
    label.stringValue = rateText(sender.doubleValue);
    sender.accessibilityValueDescription = label.stringValue;
}

- (void)fillLimits:(EPMotionLimits)limits {
    _spinSlider.doubleValue = limits.maxSpinDegreesPerSecond;
    _flipSlider.doubleValue = limits.maxFlipDegreesPerSecond;
    [self rateChanged:_spinSlider];
    [self rateChanged:_flipSlider];
}

- (NSWindow *)sheet {
    if (!_sheet) [self createSheet];
    if (!_sheet.sheetParent) [self fillLimits:[self loadLimits]];
    return _sheet;
}

- (void)closeWithResponse:(NSModalResponse)response {
    [_helpPopover close];
    [_sheet.sheetParent endSheet:_sheet returnCode:response];
    [_sheet orderOut:nil];
}

- (void)save:(id)sender {
    (void)sender;
    [self rateChanged:_spinSlider];
    [self rateChanged:_flipSlider];
    EPMotionLimits limits = {_spinSlider.doubleValue, _flipSlider.doubleValue};
    [_defaults setDouble:limits.maxSpinDegreesPerSecond forKey:SpinRateKey];
    [_defaults setDouble:limits.maxFlipDegreesPerSecond forKey:FlipRateKey];
    [_defaults synchronize];
    if (_apply) _apply(limits);
    [self closeWithResponse:NSModalResponseOK];
}

- (void)cancel:(id)sender {
    (void)sender;
    [self fillLimits:[self loadLimits]];
    [self closeWithResponse:NSModalResponseCancel];
}

- (void)reset:(id)sender {
    (void)sender;
    [self fillLimits:EPMaximumMotionLimits];
}
@end
