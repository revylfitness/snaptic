#import <Foundation/Foundation.h>

// ColorSync profiles per display (owner: C). Public ColorSync API only.

NS_ASSUME_NONNULL_BEGIN

@interface SNColorProfile : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSURL *url;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface SNColorSync : NSObject

+ (BOOL)isAvailable;

/// Installed display-class (`mntr`) profiles, sorted by name, at most 512.
+ (NSArray<SNColorProfile *> *)installedDisplayProfiles NS_SWIFT_NAME(installedDisplayProfiles());

/// The profile in use for a display, or nil.
+ (nullable SNColorProfile *)currentProfileForDisplay:(uint32_t)displayID NS_SWIFT_NAME(currentProfile(forDisplay:));

/// True when a user-set (custom) profile is assigned to the display.
+ (BOOL)hasCustomProfileForDisplay:(uint32_t)displayID NS_SWIFT_NAME(hasCustomProfile(forDisplay:));

/// Assigns `url` as the display's profile for the current user; nil restores the factory
/// profile (kCFNull).
+ (BOOL)setProfileURL:(nullable NSURL *)url forDisplay:(uint32_t)displayID error:(NSError **)error
    NS_SWIFT_NAME(setProfile(_:forDisplay:));

/// Name of the distributed notification ColorSync posts when display profiles change.
+ (NSString *)displayProfilesNotificationName NS_SWIFT_NAME(displayProfilesNotificationName());

@end

NS_ASSUME_NONNULL_END
