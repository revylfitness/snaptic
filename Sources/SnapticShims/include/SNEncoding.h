#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Checks Objective-C method type encodings before a private selector is used.
@interface SNEncoding : NSObject

/// Removes frame offsets (digits) from a type encoding, so encodings compare
/// across architectures: "c24@0:8@16" becomes "c@:@".
+ (NSString *)normalizedEncoding:(NSString *)encoding;

/// Compares two encodings after normalization. BOOL is encoded as `B` on
/// arm64 and `c` on x86_64; when `boolAware` is YES those are treated as equal.
+ (BOOL)encoding:(NSString *)actual matches:(NSString *)expected boolAware:(BOOL)boolAware;

/// True when `className` exists and responds to `selectorName` with the
/// expected type encoding. Never raises.
+ (BOOL)verifyClass:(NSString *)className
           selector:(NSString *)selectorName
           expected:(NSString *)expectedEncoding
        classMethod:(BOOL)classMethod;

@end

NS_ASSUME_NONNULL_END
