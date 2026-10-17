#import <Foundation/Foundation.h>

// MonitorPanel (System Settings' display model) through runtime lookup only (owner: B).
// The MPDisplay class is found with NSClassFromString after Swift's PrivateDisplayAPI has
// loaded the framework. Swift reads raw selector encodings, checks them with Kit
// KitEncoding, and marks the verified selectors; every call here refuses selectors that
// weren't verified. Exceptions are caught and poison the shim for the rest of the process.

NS_ASSUME_NONNULL_BEGIN

@interface SNMonitorPanel : NSObject

/// MPDisplay exists, its initializer is verified, and the shim isn't poisoned.
+ (BOOL)isAvailable;
+ (BOOL)isPoisoned;

/// Raw type encoding of an MPDisplay instance method, nil if missing.
+ (nullable NSString *)rawEncodingForSelector:(NSString *)selector NS_SWIFT_NAME(rawEncoding(selector:));

/// Records selectors whose encodings Swift verified.
+ (void)markVerified:(NSArray<NSString *> *)selectors NS_SWIFT_NAME(markVerified(_:));
+ (BOOL)isVerified:(NSString *)selector NS_SWIFT_NAME(isVerified(_:));

+ (nullable NSNumber *)canChangeOrientation:(uint32_t)display NS_SWIFT_NAME(canChangeOrientation(display:));
/// Degrees (0, 90, 180, 270).
+ (nullable NSNumber *)orientationOfDisplay:(uint32_t)display NS_SWIFT_NAME(orientation(display:));
/// Asynchronous on the WindowServer side: poll CGDisplayRotation afterwards.
+ (BOOL)setOrientation:(int32_t)degrees ofDisplay:(uint32_t)display NS_SWIFT_NAME(setOrientation(_:display:));

+ (nullable NSNumber *)hasHDRModes:(uint32_t)display NS_SWIFT_NAME(hasHDRModes(display:));
+ (nullable NSNumber *)prefersHDROfDisplay:(uint32_t)display NS_SWIFT_NAME(prefersHDR(display:));
/// Re-modesets the display (1–3 s black).
+ (BOOL)setPrefersHDR:(BOOL)prefer ofDisplay:(uint32_t)display NS_SWIFT_NAME(setPrefersHDR(_:display:));

/// 0…1.
+ (nullable NSNumber *)underscanOfDisplay:(uint32_t)display NS_SWIFT_NAME(underscan(display:));
+ (BOOL)setUnderscan:(float)value ofDisplay:(uint32_t)display NS_SWIFT_NAME(setUnderscan(_:display:));

/// Apple display presets (Pro Display XDR, Studio Display, XDR built-ins).
+ (nullable NSArray<NSString *> *)presetNamesOfDisplay:(uint32_t)display NS_SWIFT_NAME(presetNames(display:));
+ (nullable NSString *)activePresetNameOfDisplay:(uint32_t)display NS_SWIFT_NAME(activePresetName(display:));
+ (BOOL)setActivePresetNamed:(NSString *)name ofDisplay:(uint32_t)display NS_SWIFT_NAME(setActivePreset(named:display:));

@end

NS_ASSUME_NONNULL_END
