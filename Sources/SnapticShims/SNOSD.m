#import "SNOSD.h"
#import "SNEncoding.h"

#import <dlfcn.h>

#if !__has_feature(objc_arc)
#error "SnapticShims requires ARC"
#endif

// System OSD on 14/15 (owner: C).

@protocol SNOSDManagerClassAPI <NSObject>
- (id)sharedManager;
@end

@protocol SNOSDManagerAPI <NSObject>
- (void)showImage:(long long)image
      onDisplayID:(unsigned int)displayID
         priority:(unsigned int)priority
    msecUntilFade:(unsigned int)msec
   filledChiclets:(unsigned int)filled
    totalChiclets:(unsigned int)total
           locked:(BOOL)locked;
@end

static id<SNOSDManagerAPI> SNOSDManager(void) {
    static id<SNOSDManagerAPI> manager = nil;
    static BOOL resolved = NO;
    if (resolved) { return manager; }
    resolved = YES;
    if ([NSProcessInfo processInfo].operatingSystemVersion.majorVersion >= 26) { return nil; }
    @try {
        dlopen("/System/Library/PrivateFrameworks/OSD.framework/OSD", RTLD_LAZY | RTLD_LOCAL);
        if (![SNEncoding verifyClass:@"OSDManager" selector:@"sharedManager" expected:@"@@:" classMethod:YES]) { return nil; }
        if (![SNEncoding verifyClass:@"OSDManager"
                            selector:@"showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:"
                            expected:@"v@:qIIIIIB"
                         classMethod:NO]) {
            return nil;
        }
        Class cls = NSClassFromString(@"OSDManager");
        if (cls == Nil) { return nil; }
        id shared = [(id<SNOSDManagerClassAPI>)(id)cls sharedManager];
        if (shared == nil) { return nil; }
        manager = (id<SNOSDManagerAPI>)shared;
    } @catch (NSException *exception) {
        manager = nil;
    }
    return manager;
}

@implementation SNOSD

+ (BOOL)isAvailable { return SNOSDManager() != nil; }

+ (BOOL)showImage:(SNOSDImage)image onDisplay:(uint32_t)displayID filled:(uint32_t)filled total:(uint32_t)total locked:(BOOL)locked {
    id<SNOSDManagerAPI> manager = SNOSDManager();
    if (manager == nil) { return NO; }
    uint32_t t = total == 0 ? 16 : (total > 64 ? 64 : total);
    uint32_t f = filled > t ? t : filled;
    @try {
        [manager showImage:(long long)image onDisplayID:displayID priority:0x1F4 msecUntilFade:1000
            filledChiclets:f totalChiclets:t locked:locked];
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

@end
