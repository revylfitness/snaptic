#import "SNColorSync.h"

#import <ColorSync/ColorSync.h>
#import <CoreGraphics/CoreGraphics.h>

#if !__has_feature(objc_arc)
#error "SnapticShims requires ARC"
#endif

// ColorSync profiles (owner: C). Ownership: Create/Copy results are released here;
// Get results are not.

@interface SNColorProfile ()
- (instancetype)initWithName:(NSString *)name url:(NSURL *)url NS_DESIGNATED_INITIALIZER;
@end

@implementation SNColorProfile
- (instancetype)initWithName:(NSString *)name url:(NSURL *)url {
    self = [super init];
    if (self) {
        _name = [name copy];
        _url = [url copy];
    }
    return self;
}
@end

static const NSUInteger SNColorSyncMaxProfiles = 512;

static bool SNColorSyncCollect(CFDictionaryRef info, void *userInfo) {
    NSMutableArray<SNColorProfile *> *list = (__bridge NSMutableArray<SNColorProfile *> *)userInfo;
    if (list.count >= SNColorSyncMaxProfiles) { return false; }
    if (info == NULL || CFGetTypeID(info) != CFDictionaryGetTypeID()) { return true; }
    CFTypeRef cls = CFDictionaryGetValue(info, kColorSyncProfileClass);
    if (cls == NULL || CFGetTypeID(cls) != CFStringGetTypeID()
        || ![(__bridge NSString *)cls isEqualToString:(__bridge NSString *)kColorSyncSigDisplayClass]) {
        return true;
    }
    CFTypeRef url = CFDictionaryGetValue(info, kColorSyncProfileURL);
    CFTypeRef desc = CFDictionaryGetValue(info, kColorSyncProfileDescription);
    if (url == NULL || CFGetTypeID(url) != CFURLGetTypeID()) { return true; }
    NSString *name = (desc != NULL && CFGetTypeID(desc) == CFStringGetTypeID()) ? (__bridge NSString *)desc : nil;
    NSURL *u = (__bridge NSURL *)url;
    if (name.length == 0) { name = u.lastPathComponent.stringByDeletingPathExtension ?: @"Profile"; }
    if (name.length > 128) { name = [name substringToIndex:128]; }
    [list addObject:[[SNColorProfile alloc] initWithName:name url:u]];
    return true;
}

static CFUUIDRef SNColorSyncCopyUUID(uint32_t displayID) {
    return CGDisplayCreateUUIDFromDisplayID(displayID);   // +1 or NULL
}

@implementation SNColorSync

+ (BOOL)isAvailable { return YES; }

+ (NSArray<SNColorProfile *> *)installedDisplayProfiles {
    NSMutableArray<SNColorProfile *> *list = [NSMutableArray array];
    ColorSyncIterateInstalledProfiles(SNColorSyncCollect, NULL, (__bridge void *)list, NULL);
    [list sortUsingComparator:^NSComparisonResult(SNColorProfile *a, SNColorProfile *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    return list;
}

+ (nullable SNColorProfile *)currentProfileForDisplay:(uint32_t)displayID {
    ColorSyncProfileRef profile = ColorSyncProfileCreateWithDisplayID(displayID);   // +1
    if (profile == NULL) { return nil; }
    SNColorProfile *result = nil;
    CFURLRef url = ColorSyncProfileGetURL(profile, NULL);   // +0
    CFStringRef desc = ColorSyncProfileCopyDescriptionString(profile);   // +1
    if (url != NULL) {
        NSString *name = desc != NULL ? (__bridge NSString *)desc : ((__bridge NSURL *)url).lastPathComponent;
        result = [[SNColorProfile alloc] initWithName:(name ?: @"Profile") url:(__bridge NSURL *)url];
    }
    if (desc != NULL) { CFRelease(desc); }
    CFRelease(profile);
    return result;
}

+ (BOOL)hasCustomProfileForDisplay:(uint32_t)displayID {
    CFUUIDRef uuid = SNColorSyncCopyUUID(displayID);
    if (uuid == NULL) { return NO; }
    CFDictionaryRef info = ColorSyncDeviceCopyDeviceInfo(kColorSyncDisplayDeviceClass, uuid);   // +1
    CFRelease(uuid);
    if (info == NULL) { return NO; }
    BOOL custom = NO;
    if (CFGetTypeID(info) == CFDictionaryGetTypeID()) {
        CFTypeRef profiles = CFDictionaryGetValue(info, kColorSyncCustomProfiles);
        if (profiles != NULL && CFGetTypeID(profiles) == CFDictionaryGetTypeID()) {
            NSDictionary *map = (__bridge NSDictionary *)profiles;
            for (id value in map.allValues) {
                if ([value isKindOfClass:[NSURL class]]) { custom = YES; break; }
            }
        }
    }
    CFRelease(info);
    return custom;
}

+ (BOOL)setProfileURL:(nullable NSURL *)url forDisplay:(uint32_t)displayID error:(NSError **)error {
    CFUUIDRef uuid = SNColorSyncCopyUUID(displayID);
    if (uuid == NULL) {
        if (error) { *error = [NSError errorWithDomain:@"SNColorSync" code:1 userInfo:nil]; }
        return NO;
    }
    id value = url != nil ? (id)url : (__bridge id)kCFNull;
    NSDictionary *profileInfo = @{
        (__bridge NSString *)kColorSyncDeviceDefaultProfileID: value,
        (__bridge NSString *)kColorSyncProfileUserScope: (__bridge NSString *)kCFPreferencesCurrentUser,
    };
    bool ok = ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass, uuid, (__bridge CFDictionaryRef)profileInfo);
    CFRelease(uuid);
    if (!ok && error) { *error = [NSError errorWithDomain:@"SNColorSync" code:2 userInfo:nil]; }
    return ok;
}

+ (NSString *)displayProfilesNotificationName {
    return (__bridge NSString *)kColorSyncDisplayDeviceProfilesNotification;
}

@end
