#import "SNMonitorPanel.h"
#import <objc/runtime.h>

#if !__has_feature(objc_arc)
#error "SnapticShims requires ARC"
#endif

// Selectors of the private MPDisplay class, declared on a local protocol so ARC knows the
// ownership families; no @interface for the private class exists anywhere.
@protocol SNMPDisplayAPI <NSObject>
- (instancetype)initWithCGSDisplayID:(int)displayID;
- (BOOL)canChangeOrientation;
- (int)orientation;
- (void)setOrientation:(int)degrees;
- (BOOL)hasHDRModes;
- (BOOL)preferHDRModes;
- (void)setPreferHDRModes:(BOOL)prefer;
- (float)underscan;
- (void)setUnderscan:(float)value;
- (NSArray *)presets;
- (id)activePreset;
- (void)setActivePreset:(id)preset;
@end

@protocol SNMPPresetAPI <NSObject>
- (NSString *)presetName;
- (NSString *)name;
@end

static BOOL sPoisoned = NO;
static NSMutableSet<NSString *> *sVerified = nil;

@implementation SNMonitorPanel

+ (NSMutableSet<NSString *> *)verifiedSet {
    @synchronized(self) {
        if (sVerified == nil) { sVerified = [NSMutableSet set]; }
        return sVerified;
    }
}

+ (BOOL)isPoisoned {
    @synchronized(self) { return sPoisoned; }
}

+ (void)poison {
    @synchronized(self) { sPoisoned = YES; }
}

+ (nullable Class)displayClass {
    if ([self isPoisoned]) { return Nil; }
    return NSClassFromString(@"MPDisplay");
}

+ (BOOL)isAvailable {
    return [self displayClass] != Nil && [self isVerified:@"initWithCGSDisplayID:"];
}

+ (nullable NSString *)rawEncodingForSelector:(NSString *)selector {
    @try {
        Class cls = [self displayClass];
        if (cls == Nil) { return nil; }
        Method m = class_getInstanceMethod(cls, NSSelectorFromString(selector));
        if (m == NULL) { return nil; }
        const char *types = method_getTypeEncoding(m);
        return types ? [NSString stringWithUTF8String:types] : nil;
    } @catch (NSException *e) {
        [self poison];
        return nil;
    }
}

+ (void)markVerified:(NSArray<NSString *> *)selectors {
    NSMutableSet *set = [self verifiedSet];
    @synchronized(self) { [set addObjectsFromArray:selectors]; }
}

+ (BOOL)isVerified:(NSString *)selector {
    NSMutableSet *set = [self verifiedSet];
    @synchronized(self) { return [set containsObject:selector]; }
}

/// A fresh MPDisplay for `display`, or nil when unavailable or a selector isn't verified.
+ (nullable id<SNMPDisplayAPI>)display:(uint32_t)display requiring:(NSArray<NSString *> *)selectors {
    if (![self isAvailable]) { return nil; }
    for (NSString *s in selectors) {
        if (![self isVerified:s]) { return nil; }
    }
    Class cls = [self displayClass];
    if (cls == Nil) { return nil; }
    id<SNMPDisplayAPI> d = [(id<SNMPDisplayAPI>)[cls alloc] initWithCGSDisplayID:(int)display];
    return d;
}

+ (nullable NSNumber *)canChangeOrientation:(uint32_t)display {
    @try {
        id<SNMPDisplayAPI> d = [self display:display requiring:@[@"canChangeOrientation"]];
        return d ? @([d canChangeOrientation]) : nil;
    } @catch (NSException *e) { [self poison]; return nil; }
}

+ (nullable NSNumber *)orientationOfDisplay:(uint32_t)display {
    @try {
        id<SNMPDisplayAPI> d = [self display:display requiring:@[@"orientation"]];
        return d ? @([d orientation]) : nil;
    } @catch (NSException *e) { [self poison]; return nil; }
}

+ (BOOL)setOrientation:(int32_t)degrees ofDisplay:(uint32_t)display {
    if (degrees != 0 && degrees != 90 && degrees != 180 && degrees != 270) { return NO; }
    @try {
        id<SNMPDisplayAPI> d = [self display:display requiring:@[@"canChangeOrientation", @"setOrientation:"]];
        if (d == nil || ![d canChangeOrientation]) { return NO; }
        [d setOrientation:(int)degrees];
        return YES;
    } @catch (NSException *e) { [self poison]; return NO; }
}

+ (nullable NSNumber *)hasHDRModes:(uint32_t)display {
    @try {
        id<SNMPDisplayAPI> d = [self display:display requiring:@[@"hasHDRModes"]];
        return d ? @([d hasHDRModes]) : nil;
    } @catch (NSException *e) { [self poison]; return nil; }
}

+ (nullable NSNumber *)prefersHDROfDisplay:(uint32_t)display {
    @try {
        id<SNMPDisplayAPI> d = [self display:display requiring:@[@"preferHDRModes"]];
        return d ? @([d preferHDRModes]) : nil;
    } @catch (NSException *e) { [self poison]; return nil; }
}

+ (BOOL)setPrefersHDR:(BOOL)prefer ofDisplay:(uint32_t)display {
    @try {
        id<SNMPDisplayAPI> d = [self display:display requiring:@[@"hasHDRModes", @"setPreferHDRModes:"]];
        if (d == nil || ![d hasHDRModes]) { return NO; }
        [d setPreferHDRModes:prefer];
        return YES;
    } @catch (NSException *e) { [self poison]; return NO; }
}

+ (nullable NSNumber *)underscanOfDisplay:(uint32_t)display {
    @try {
        id<SNMPDisplayAPI> d = [self display:display requiring:@[@"underscan"]];
        if (d == nil) { return nil; }
        float v = [d underscan];
        if (!isfinite(v) || v < 0 || v > 1) { return nil; }
        return @(v);
    } @catch (NSException *e) { [self poison]; return nil; }
}

+ (BOOL)setUnderscan:(float)value ofDisplay:(uint32_t)display {
    if (!isfinite(value) || value < 0 || value > 1) { return NO; }
    @try {
        id<SNMPDisplayAPI> d = [self display:display requiring:@[@"setUnderscan:"]];
        if (d == nil) { return NO; }
        [d setUnderscan:value];
        return YES;
    } @catch (NSException *e) { [self poison]; return NO; }
}

/// The name of a preset object: `presetName`, else `name`, when either returns a string.
+ (nullable NSString *)nameOfPreset:(id)preset {
    for (NSString *selName in @[@"presetName", @"name"]) {
        SEL sel = NSSelectorFromString(selName);
        Method m = class_getInstanceMethod(object_getClass(preset), sel);
        if (m == NULL) { continue; }
        const char *types = method_getTypeEncoding(m);
        if (types == NULL || types[0] != '@') { continue; }
        id value = [selName isEqualToString:@"presetName"] ? [(id<SNMPPresetAPI>)preset presetName]
                                                          : [(id<SNMPPresetAPI>)preset name];
        if ([value isKindOfClass:[NSString class]]) { return [(NSString *)value copy]; }
    }
    return nil;
}

+ (nullable NSArray<NSString *> *)presetNamesOfDisplay:(uint32_t)display {
    @try {
        id<SNMPDisplayAPI> d = [self display:display requiring:@[@"presets"]];
        if (d == nil) { return nil; }
        id list = [d presets];
        if (![list isKindOfClass:[NSArray class]]) { return nil; }
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (id p in (NSArray *)list) {
            if (names.count >= 64) { break; }
            NSString *n = [self nameOfPreset:p];
            if (n != nil && n.length <= 128) { [names addObject:n]; }
        }
        return names;
    } @catch (NSException *e) { [self poison]; return nil; }
}

+ (nullable NSString *)activePresetNameOfDisplay:(uint32_t)display {
    @try {
        id<SNMPDisplayAPI> d = [self display:display requiring:@[@"activePreset"]];
        if (d == nil) { return nil; }
        id p = [d activePreset];
        return p ? [self nameOfPreset:p] : nil;
    } @catch (NSException *e) { [self poison]; return nil; }
}

+ (BOOL)setActivePresetNamed:(NSString *)name ofDisplay:(uint32_t)display {
    @try {
        id<SNMPDisplayAPI> d = [self display:display requiring:@[@"presets", @"setActivePreset:"]];
        if (d == nil) { return NO; }
        id list = [d presets];
        if (![list isKindOfClass:[NSArray class]]) { return NO; }
        for (id p in (NSArray *)list) {
            if ([[self nameOfPreset:p] isEqualToString:name]) {
                [d setActivePreset:p];
                return YES;
            }
        }
        return NO;
    } @catch (NSException *e) { [self poison]; return NO; }
}

@end
