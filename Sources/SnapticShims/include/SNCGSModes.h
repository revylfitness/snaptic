#import <Foundation/Foundation.h>

// The private CGS mode list behind `hiddenModes` (owner: B). Swift resolves the function
// pointers through PrivateDisplayAPI (so kill switches apply) and passes them in; this shim
// only does the C buffer handling. Records are parsed and sanity-checked in Kit
// (CGSModeRecord), which disables the path on any bad record.

NS_ASSUME_NONNULL_BEGIN

@interface SNCGSModes : NSObject

/// Length of one CGS mode description record.
+ (NSInteger)recordLength;

/// Raw records for `display` (at most 4096), each `recordLength` bytes; nil on any failure.
/// `countFunction`: void CGSGetNumberOfDisplayModes(uint32_t, int *);
/// `describeFunction`: void CGSGetDisplayModeDescriptionOfLength(uint32_t, int, void *, int).
+ (nullable NSArray<NSData *> *)recordsForDisplay:(uint32_t)display
                                    countFunction:(const void *)countFunction
                                 describeFunction:(const void *)describeFunction
    NS_SWIFT_NAME(records(display:countFunction:describeFunction:));

/// The current CGS mode number, or -1. `currentFunction`: void CGSGetCurrentDisplayMode(uint32_t, int *).
+ (int32_t)currentModeForDisplay:(uint32_t)display currentFunction:(const void *)currentFunction
    NS_SWIFT_NAME(currentMode(display:currentFunction:));

@end

NS_ASSUME_NONNULL_END
