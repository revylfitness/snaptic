#import <Foundation/Foundation.h>

// The system OSD on macOS 14/15 through OSD.framework's OSDManager (owner: C). Private:
// looked up at runtime with encoding checks. On 26+ the system HUD ignores it, so
// isAvailable is NO there and Snaptic draws its own HUD. Main thread only.

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(int64_t, SNOSDImage) {
    SNOSDImageBrightness = 1,
    SNOSDImageVolume = 3,
    SNOSDImageMuted = 4,
};

@interface SNOSD : NSObject

+ (BOOL)isAvailable;

/// Shows the system HUD with `filled` of `total` chiclets. Returns NO if unavailable.
+ (BOOL)showImage:(SNOSDImage)image
        onDisplay:(uint32_t)displayID
           filled:(uint32_t)filled
            total:(uint32_t)total
           locked:(BOOL)locked
    NS_SWIFT_NAME(show(image:display:filled:total:locked:));

@end

NS_ASSUME_NONNULL_END
