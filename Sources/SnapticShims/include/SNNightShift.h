#import <Foundation/Foundation.h>

// Night Shift through CoreBrightness's CBBlueLightClient (owner: C). Private: the class is
// looked up at runtime and every selector's type encoding is checked before use. Call
// from the main thread only.

NS_ASSUME_NONNULL_BEGIN

@interface SNNightShift : NSObject

/// True when CBBlueLightClient exists with the expected selectors and reports Night Shift
/// as supported on this Mac.
+ (BOOL)isAvailable;

/// Whether Night Shift is on now; nil if it can't be read.
+ (nullable NSNumber *)isEnabled NS_SWIFT_NAME(enabledState());

+ (BOOL)setEnabled:(BOOL)enabled NS_SWIFT_NAME(setEnabled(_:));

/// Strength 0…1; nil if it can't be read.
+ (nullable NSNumber *)strength NS_SWIFT_NAME(currentStrength());

+ (BOOL)setStrength:(float)strength NS_SWIFT_NAME(setStrength(_:));

@end

NS_ASSUME_NONNULL_END
