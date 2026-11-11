#import <Foundation/Foundation.h>

// Hidden Icons' Native engine (owner: lead; PLAN 0.4 §4.2.2, B1): MenuBarClientCore's MBAssessmentModeAssertion,
// the restriction behind exam mode, through runtime lookup only. The framework is dlopen'd and the two classes are
// found with NSClassFromString inside the .m. Swift's PrivateMenuBarAPI reads the raw encodings, checks them with
// Kit's IconsShimContract and marks them verified; the shim refuses to act until all five are. Any caught exception
// poisons the shim for the life of the process and invalidates every assertion it holds (icons shown).
//
// Tokens are the caller's (Kit IconsVisibilityPort). The shim keeps at most one assertion per token. A completion is
// delivered at most once, on the main queue, and only while its token is still held; a completion for a token that
// was released is dropped and its assertion invalidated at once; any further calls of the system's handler are
// counted as duplicates. Only a result code crosses into Swift, never NSError text (§4.15).

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SNMenuBarVisibilityResult) {
    /// The restriction is in effect.
    SNMenuBarVisibilityResultOK = 0,
    /// The system refused it (its handler reported an error).
    SNMenuBarVisibilityResultFailed = 1,
    /// The shim is poisoned.
    SNMenuBarVisibilityResultPoisoned = 2,
    /// Not loaded, not verified, a token already held, or an argument out of bounds.
    SNMenuBarVisibilityResultRefused = 3,
};

@interface SNMenuBarVisibility : NSObject

/// The framework loaded and both classes exist (whatever their encodings).
+ (BOOL)isPresent;
/// Present, all five selectors verified, and not poisoned.
+ (BOOL)isAvailable;
+ (BOOL)isPoisoned;

/// Raw type encoding of an instance method of `MBAssessmentModeConfiguration` or `MBAssessmentModeAssertion` (other
/// classes return nil), nil if missing. Loads the framework on first use.
+ (nullable NSString *)rawEncodingForClass:(NSString *)className
                                  selector:(NSString *)selector NS_SWIFT_NAME(rawEncoding(className:selector:));

/// Records a selector whose encoding Swift verified.
+ (void)markVerifiedClass:(NSString *)className selector:(NSString *)selector NS_SWIFT_NAME(markVerified(className:selector:));

/// Restricts the menu bar to system items `lower..<upper` and `bundles`. Returns NO, without calling `completion`,
/// when refused up front (the result is then `Refused` or `Poisoned` in `lastRefusal`). On YES, `completion` runs
/// at most once on the main queue. Bounds: 0 ≤ lower < upper ≤ 256, at most 1024 bundles of 1–255 UTF-16 units,
/// token ≠ 0 and not already held.
+ (BOOL)activateWithSystemItemsFrom:(NSInteger)lower
                                 to:(NSInteger)upper
                            bundles:(NSArray<NSString *> *)bundles
                              token:(uint64_t)token
                         completion:(void (^)(SNMenuBarVisibilityResult result))completion
    NS_SWIFT_NAME(activate(systemItemsFrom:to:bundles:token:completion:));

/// Why the last `activate` returned NO.
+ (SNMenuBarVisibilityResult)lastRefusal;

/// Invalidates and releases the token's assertion (no-op for an unknown token). Safe off the main thread.
+ (void)invalidateToken:(uint64_t)token NS_SWIFT_NAME(invalidate(token:));
/// Invalidates and releases every assertion. Safe off the main thread (S0-5), e.g. from the watchdog.
+ (void)invalidateAll;

/// Tokens currently held.
+ (NSUInteger)heldCount;
/// Duplicate handler calls since the last take (`icons.dupCompletion`), then resets to 0.
+ (NSUInteger)takeDuplicateCompletions;

/// Self-test only (`--selftest-launch`, debug builds): raises and catches an exception through the shim's own
/// handler, so the poison path is exercised without touching the system service.
+ (void)simulateExceptionForSelfTest;

@end

NS_ASSUME_NONNULL_END
