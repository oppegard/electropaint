#import <Cocoa/Cocoa.h>
#import "EPAdapter.h"

@interface EPMotionSettings : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults
                          apply:(void (^)(EPMotionLimits limits))apply;
- (EPMotionLimits)loadLimits;
- (NSWindow *)sheet;
@end
