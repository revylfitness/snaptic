#import "SNMenuBarVisibility.h"
#import <objc/runtime.h>
#import <dlfcn.h>

#if !__has_feature(objc_arc)
#error "SnapticShims requires ARC"
#endif

// Selectors of the private classes, declared on local protocols so ARC knows the ownership families; no @interface
// for a private class exists anywhere.
@protocol SNMBConfigurationAPI <NSObject>
- (instancetype)initWithAllowedSystemItems:(NSArray *)systemItems allowedBundleIdentifiers:(NSArray *)bundles;
@end

@protocol SNMBAssertionAPI <NSObject>
- (instancetype)init;
- (void)activateWithConfiguration:(id)configuration completionHandler:(void (^)(NSError *_Nullable error))handler;
- (void)invalidate;
@end

static NSString *const kFramework = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const kConfigurationClass = @"MBAssessmentModeConfiguration";
static NSString *const kAssertionClass = @"MBAssessmentModeAssertion";

static BOOL sLoadTried = NO;
static BOOL sLoaded = NO;
static BOOL sPoisoned = NO;
static NSUInteger sDuplicates = 0;
static SNMenuBarVisibilityResult sLastRefusal = SNMenuBarVisibilityResultRefused;
static NSMutableSet<NSString *> *sVerified = nil;
static NSMutableDictionary<NSNumber *, id> *sHeld = nil;

@implementation SNMenuBarVisibility

/// The five selectors (§4.2.2) as "Class selector".
+ (NSArray<NSString *> *)requiredKeys {
    return @[
        [kConfigurationClass stringByAppendingString:@" initWithAllowedSystemItems:allowedBundleIdentifiers:"],
        [kConfigurationClass stringByAppendingString:@" initWithUnrestrictedMenuBarItems"],
        [kAssertionClass stringByAppendingString:@" init"],
        [kAssertionClass stringByAppendingString:@" activateWithConfiguration:completionHandler:"],
        [kAssertionClass stringByAppendingString:@" invalidate"],
    ];
}

+ (BOOL)loadFramework {
    @synchronized(self) {
        if (!sLoadTried) {
            sLoadTried = YES;
            sLoaded = dlopen(kFramework.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL) != NULL;
        }
        return sLoaded;
    }
}

+ (BOOL)isPoisoned {
    @synchronized(self) { return sPoisoned; }
}

/// Poisons the shim and lets go of every assertion (fail safe: icons shown).
+ (void)poison {
    @synchronized(self) { sPoisoned = YES; }
    [self invalidateAll];
}

+ (nullable Class)classNamed:(NSString *)name {
    if ([self isPoisoned] || ![self loadFramework]) { return Nil; }
    if (![name isEqualToString:kConfigurationClass] && ![name isEqualToString:kAssertionClass]) { return Nil; }
    return NSClassFromString(name);
}

+ (BOOL)isPresent {
    @try {
        return [self classNamed:kConfigurationClass] != Nil && [self classNamed:kAssertionClass] != Nil;
    } @catch (NSException *e) {
        [self poison];
        return NO;
    }
}

+ (BOOL)allVerified {
    @synchronized(self) {
        for (NSString *key in [self requiredKeys]) {
            if (![sVerified containsObject:key]) { return NO; }
        }
        return YES;
    }
}

+ (BOOL)isAvailable {
    return ![self isPoisoned] && [self isPresent] && [self allVerified];
}

+ (nullable NSString *)rawEncodingForClass:(NSString *)className selector:(NSString *)selector {
    @try {
        Class cls = [self classNamed:className];
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

+ (void)markVerifiedClass:(NSString *)className selector:(NSString *)selector {
    NSString *key = [NSString stringWithFormat:@"%@ %@", className, selector];
    if (![[self requiredKeys] containsObject:key]) { return; }
    @synchronized(self) {
        if (sVerified == nil) { sVerified = [NSMutableSet set]; }
        [sVerified addObject:key];
    }
}

+ (SNMenuBarVisibilityResult)lastRefusal {
    @synchronized(self) { return sLastRefusal; }
}

+ (BOOL)refuse:(SNMenuBarVisibilityResult)why {
    @synchronized(self) { sLastRefusal = why; }
    return NO;
}

+ (BOOL)validBundles:(NSArray<NSString *> *)bundles {
    if (![bundles isKindOfClass:[NSArray class]] || bundles.count > 1024) { return NO; }
    for (id b in bundles) {
        if (![b isKindOfClass:[NSString class]]) { return NO; }
        NSUInteger n = [(NSString *)b length];
        if (n == 0 || n > 255) { return NO; }
    }
    return YES;
}

/// Whether `assertion` is still the one held for `token`.
+ (BOOL)isHeld:(id)assertion token:(uint64_t)token {
    @synchronized(self) { return sHeld[@(token)] == assertion; }
}

+ (void)invalidateAssertion:(id)assertion {
    if (assertion == nil) { return; }
    @try {
        [(id<SNMBAssertionAPI>)assertion invalidate];
    } @catch (NSException *e) {
        @synchronized(self) { sPoisoned = YES; }
    }
}

+ (BOOL)activateWithSystemItemsFrom:(NSInteger)lower
                                 to:(NSInteger)upper
                            bundles:(NSArray<NSString *> *)bundles
                              token:(uint64_t)token
                         completion:(void (^)(SNMenuBarVisibilityResult result))completion {
    if ([self isPoisoned]) { return [self refuse:SNMenuBarVisibilityResultPoisoned]; }
    if (![self isAvailable]) { return [self refuse:SNMenuBarVisibilityResultRefused]; }
    if (lower < 0 || upper > 256 || lower >= upper || token == 0 || ![self validBundles:bundles]) {
        return [self refuse:SNMenuBarVisibilityResultRefused];
    }
    @try {
        Class configurationClass = [self classNamed:kConfigurationClass];
        Class assertionClass = [self classNamed:kAssertionClass];
        if (configurationClass == Nil || assertionClass == Nil) { return [self refuse:SNMenuBarVisibilityResultRefused]; }

        NSMutableArray<NSNumber *> *system = [NSMutableArray arrayWithCapacity:(NSUInteger)(upper - lower)];
        for (NSInteger i = lower; i < upper; i++) { [system addObject:@(i)]; }
        NSArray *allowed = [[NSArray alloc] initWithArray:bundles copyItems:YES];
        id configuration = [(id<SNMBConfigurationAPI>)[configurationClass alloc] initWithAllowedSystemItems:system
                                                                                  allowedBundleIdentifiers:allowed];
        id assertion = [(id<SNMBAssertionAPI>)[assertionClass alloc] init];
        if (configuration == nil || assertion == nil) { return [self refuse:SNMenuBarVisibilityResultRefused]; }

        @synchronized(self) {
            if (sHeld == nil) { sHeld = [NSMutableDictionary dictionary]; }
            if (sHeld[@(token)] != nil) {
                sLastRefusal = SNMenuBarVisibilityResultRefused;
                return NO;
            }
            sHeld[@(token)] = assertion;
        }

        void (^deliver)(SNMenuBarVisibilityResult) = [completion copy];
        __block BOOL called = NO;
        Class shim = self;
        __weak id weakAssertion = assertion;
        // The system calls this on a background thread (R2-8), possibly more than once.
        void (^handler)(NSError *_Nullable) = ^(NSError *_Nullable error) {
            BOOL first;
            @synchronized(shim) {
                first = !called;
                called = YES;
                if (!first) { sDuplicates += 1; }
            }
            if (!first) { return; }
            BOOL failed = error != nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                id held = weakAssertion;
                if (held == nil || ![shim isHeld:held token:token]) {
                    // Released before the system answered: make sure it isn't left in effect.
                    [shim invalidateAssertion:held];
                    return;
                }
                if (failed) {
                    @synchronized(shim) { [sHeld removeObjectForKey:@(token)]; }
                    [shim invalidateAssertion:held];
                }
                if ([shim isPoisoned]) {
                    deliver(SNMenuBarVisibilityResultPoisoned);
                } else {
                    deliver(failed ? SNMenuBarVisibilityResultFailed : SNMenuBarVisibilityResultOK);
                }
            });
        };
        [(id<SNMBAssertionAPI>)assertion activateWithConfiguration:configuration completionHandler:handler];
        return YES;
    } @catch (NSException *e) {
        [self poison];
        return [self refuse:SNMenuBarVisibilityResultPoisoned];
    }
}

+ (void)invalidateToken:(uint64_t)token {
    id assertion;
    @synchronized(self) {
        assertion = sHeld[@(token)];
        [sHeld removeObjectForKey:@(token)];
    }
    [self invalidateAssertion:assertion];
}

+ (void)invalidateAll {
    NSArray *all;
    @synchronized(self) {
        all = sHeld.allValues ?: @[];
        [sHeld removeAllObjects];
    }
    for (id assertion in all) { [self invalidateAssertion:assertion]; }
}

+ (NSUInteger)heldCount {
    @synchronized(self) { return sHeld.count; }
}

+ (NSUInteger)takeDuplicateCompletions {
    @synchronized(self) {
        NSUInteger n = sDuplicates;
        sDuplicates = 0;
        return n;
    }
}

+ (void)simulateExceptionForSelfTest {
    @try {
        @throw [NSException exceptionWithName:@"SNMenuBarVisibilitySelfTest" reason:@"forced" userInfo:nil];
    } @catch (NSException *e) {
        [self poison];
    }
}

@end
