#import <Foundation/Foundation.h>

// The window server's still capture (owner: lead; PLAN 0.5 §4.12, H3, X-1; B1b): `CGSHWCaptureWindowList`, the one
// window symbol looked up outside `Windows/PrivateWindowAPI.swift`. The symbol is found once with `dlsym`, and each
// call copies the caller's ids into a bounded local buffer first. The result follows the Create rule (STEP0-NOTES):
// it's handed to ARC, and Swift checks its shape with Kit's `WindowResults.capture` before using any of it. Swift's
// `PrivateWindowAPI` owns the gate, the image check, the probe, the crash marker and the kill switch; the shim only
// makes the call.

NS_ASSUME_NONNULL_BEGIN

/// The most window ids one call takes.
enum { SNWindowServerMaxCaptureIDs = 16 };

@interface SNWindowServer : NSObject

/// The capture symbol was found.
+ (BOOL)isCapturePresent;

/// `dladdr`'s `dli_fname` for the capture symbol (the image check), nil when it's missing or `dladdr` says nothing.
+ (nullable NSString *)captureImagePath;

/// Calls the capture for 1 to `SNWindowServerMaxCaptureIDs` ids and returns its result as given (nil for NULL, a
/// missing symbol or a count out of bounds). Whatever comes back is the caller's to check; it's usually a `CFArray`
/// of `CGImage`.
+ (nullable id)captureWithConnection:(int32_t)connection
                           windowIDs:(const uint32_t *)windowIDs
                               count:(NSInteger)count
                             options:(uint32_t)options
    NS_SWIFT_NAME(capture(connection:windowIDs:count:options:));

@end

NS_ASSUME_NONNULL_END
