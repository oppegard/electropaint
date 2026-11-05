#import "EPMotionSettings.h"
#import <ScreenSaver/ScreenSaver.h>
#include <math.h>

static NSString *const SpinKey = @"MaximumSpinDegreesPerSecond";
static NSString *const FlipKey = @"MaximumFlipDegreesPerSecond";

@implementation EPMotionSettings {
    NSUserDefaults *_defaults;
    void (^_apply)(EPMotionLimits);
    NSWindow *_sheet;
    NSTextField *_spinField, *_flipField, *_spinError, *_flipError;
    NSNumberFormatter *_formatter;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                          apply:(void (^)(EPMotionLimits))apply {
    self = [super init];
    if (!self) return nil;
    _defaults = defaults ?: [ScreenSaverDefaults defaultsForModuleWithName:
        @"com.oppegard.electropaint.screensaver"];
    _apply = [apply copy];
    _formatter = [NSNumberFormatter new];
    _formatter.locale = [NSLocale currentLocale];
    _formatter.numberStyle = NSNumberFormatterDecimalStyle;
    _formatter.usesGroupingSeparator = NO;
    _formatter.lenient = NO;
    _formatter.generatesDecimalNumbers = YES;
    _formatter.maximumFractionDigits = 10;
    return self;
}

static double storedLimit(id value, double fallback, double maximum) {
    if (![value isKindOfClass:[NSNumber class]]) return fallback;
    double number = [value doubleValue];
    if (!isfinite(number) || number < 0) return fallback;
    return MIN(number, maximum);
}

- (EPMotionLimits)loadLimits {
    return (EPMotionLimits){
        storedLimit([_defaults objectForKey:SpinKey], EPDefaultMotionLimits.maxSpinDegreesPerSecond,
                    EPMaximumMotionLimits.maxSpinDegreesPerSecond),
        storedLimit([_defaults objectForKey:FlipKey], EPDefaultMotionLimits.maxFlipDegreesPerSecond,
                    EPMaximumMotionLimits.maxFlipDegreesPerSecond)
    };
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    [_sheet.contentView addSubview:label];
    return label;
}

- (NSTextField *)field:(NSString *)identifier y:(CGFloat)y {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(220, y, 110, 24)];
    field.identifier = identifier;
    field.alignment = NSTextAlignmentRight;
    [_sheet.contentView addSubview:field];
    return field;
}

- (NSString *)rangeForMaximum:(double)maximum {
    return [NSString stringWithFormat:@"Allowed range: 0–%@", [_formatter stringFromNumber:@(maximum)]];
}

- (NSButton *)button:(NSString *)title x:(CGFloat)x width:(CGFloat)width action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.frame = NSMakeRect(x, 20, width, 32);
    [_sheet.contentView addSubview:button];
    return button;
}

- (void)createSheet {
    _sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 530, 326)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    _sheet.title = @"Electropaint Settings";
    _sheet.releasedWhenClosed = NO;
    NSTextField *title = [self label:@"Rotation limits" frame:NSMakeRect(24, 282, 482, 22)];
    title.font = [NSFont boldSystemFontOfSize:15];
    [self label:@"Set each rotation limit. Zero stops that rotation."
          frame:NSMakeRect(24, 254, 482, 20)];
    [self label:@"Maximum spin" frame:NSMakeRect(24, 216, 180, 20)];
    _spinField = [self field:@"maximumSpin" y:212];
    [self label:@"degrees per second" frame:NSMakeRect(342, 216, 170, 20)];
    [self label:[self rangeForMaximum:EPMaximumMotionLimits.maxSpinDegreesPerSecond]
          frame:NSMakeRect(24, 192, 482, 18)].textColor = [NSColor secondaryLabelColor];
    _spinError = [self label:@"" frame:NSMakeRect(24, 172, 482, 18)];
    _spinError.textColor = [NSColor systemRedColor];
    _spinError.identifier = @"spinError";
    [self label:@"Maximum flip" frame:NSMakeRect(24, 142, 180, 20)];
    _flipField = [self field:@"maximumFlip" y:138];
    [self label:@"degrees per second" frame:NSMakeRect(342, 142, 170, 20)];
    [self label:[self rangeForMaximum:EPMaximumMotionLimits.maxFlipDegreesPerSecond]
          frame:NSMakeRect(24, 118, 482, 18)].textColor = [NSColor secondaryLabelColor];
    _flipError = [self label:@"" frame:NSMakeRect(24, 98, 482, 18)];
    _flipError.textColor = [NSColor systemRedColor];
    _flipError.identifier = @"flipError";
    [self button:@"Restore Original" x:20 width:150 action:@selector(restoreOriginal:)];
    NSButton *cancel = [self button:@"Cancel" x:322 width:88 action:@selector(cancel:)];
    cancel.keyEquivalent = @"\e";
    NSButton *save = [self button:@"Save" x:418 width:88 action:@selector(save:)];
    save.keyEquivalent = @"\r";
    _spinField.nextKeyView = _flipField;
    _flipField.nextKeyView = save;
    _sheet.initialFirstResponder = _spinField;
}

- (void)fillLimits:(EPMotionLimits)limits {
    _spinField.stringValue = [_formatter stringFromNumber:@(limits.maxSpinDegreesPerSecond)];
    _flipField.stringValue = [_formatter stringFromNumber:@(limits.maxFlipDegreesPerSecond)];
    _spinError.stringValue = @"";
    _flipError.stringValue = @"";
}

- (NSWindow *)sheet {
    if (!_sheet) [self createSheet];
    if (!_sheet.sheetParent) [self fillLimits:[self loadLimits]];
    return _sheet;
}

- (BOOL)readField:(NSTextField *)field maximum:(double)maximum
           error:(NSTextField *)error value:(double *)value {
    NSString *text = [field.stringValue stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSRange range = NSMakeRange(0, text.length);
    NSNumber *number = nil;
    BOOL valid = text.length && [_formatter getObjectValue:&number forString:text range:&range error:NULL]
        && range.location == 0 && range.length == text.length;
    double parsed = valid ? number.doubleValue : NAN;
    valid = valid && isfinite(parsed) && parsed >= 0 && parsed <= maximum;
    error.stringValue = valid ? @"" : [NSString stringWithFormat:@"Enter a number from 0 to %@.",
        [_formatter stringFromNumber:@(maximum)]];
    if (valid) *value = parsed;
    return valid;
}

- (void)closeWithResponse:(NSModalResponse)response {
    [_sheet.sheetParent endSheet:_sheet returnCode:response];
    [_sheet orderOut:nil];
}

- (void)save:(id)sender {
    (void)sender;
    EPMotionLimits limits;
    BOOL spinValid = [self readField:_spinField maximum:EPMaximumMotionLimits.maxSpinDegreesPerSecond
                               error:_spinError value:&limits.maxSpinDegreesPerSecond];
    BOOL flipValid = [self readField:_flipField maximum:EPMaximumMotionLimits.maxFlipDegreesPerSecond
                               error:_flipError value:&limits.maxFlipDegreesPerSecond];
    if (!spinValid || !flipValid) {
        [_sheet makeFirstResponder:spinValid ? _flipField : _spinField];
        return;
    }
    [_defaults setDouble:limits.maxSpinDegreesPerSecond forKey:SpinKey];
    [_defaults setDouble:limits.maxFlipDegreesPerSecond forKey:FlipKey];
    [_defaults synchronize];
    if (_apply) _apply(limits);
    [self closeWithResponse:NSModalResponseOK];
}

- (void)cancel:(id)sender {
    (void)sender;
    [self fillLimits:[self loadLimits]];
    [self closeWithResponse:NSModalResponseCancel];
}

- (void)restoreOriginal:(id)sender {
    (void)sender;
    [self fillLimits:EPMaximumMotionLimits];
}
@end
