#import "SNNightShift.h"

#import <dlfcn.h>
#import <objc/runtime.h>
#import <string.h>

#if !__has_feature(objc_arc)
#error "SnapticShims requires ARC"
#endif

// Night Shift (owner: C). The status struct is read into a 256-byte zeroed buffer
// (PLAN §6.5): byte 0 = active, byte 1 = enabled, byte 7 (after the int mode) onwards is
// the schedule. Only bytes 0–1 are used.

@protocol SNBlueLightClientAPI <NSObject>
- (BOOL)getBlueLightStatus:(void *)status;
- (BOOL)setEnabled:(BOOL)enabled;
- (BOOL)setStrength:(float)strength commit:(BOOL)commit;
- (BOOL)getStrength:(float *)strength;
@end

/// Class-object messages, declared as instance methods so they type-check on a Class cast to id.
@protocol SNBlueLightClientClassAPI <NSObject>
- (BOOL)supportsBlueLightReduction;
@end

static BOOL SNIsBoolType(const char *t) { return t != NULL && (t[0] == 'B' || t[0] == 'c'); }

/// Checks return and argument type characters (ignoring qualifiers and struct details).
static BOOL SNNightShiftCheck(Class cls, SEL sel, BOOL classMethod, const char *argTypes) {
    Method m = classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (m == NULL) { return NO; }
    char ret[16];
    method_getReturnType(m, ret, sizeof(ret));
    if (!SNIsBoolType(ret)) { return NO; }
    size_t count = strlen(argTypes);
    if (method_getNumberOfArguments(m) != count + 2) { return NO; }
    for (size_t i = 0; i < count; i++) {
        char arg[16];
        method_getArgumentType(m, (unsigned int)(i + 2), arg, sizeof(arg));
        char expected = argTypes[i];
        if (expected == 'B') {
            if (!SNIsBoolType(arg)) { return NO; }
        } else if (arg[0] != expected) {
            return NO;
        }
    }
    return YES;
}

static id<SNBlueLightClientAPI> SNNightShiftClient(void) {
    static id<SNBlueLightClientAPI> client = nil;
    static BOOL resolved = NO;
    if (resolved) { return client; }
    resolved = YES;
    @try {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY | RTLD_LOCAL);
        Class cls = NSClassFromString(@"CBBlueLightClient");
        if (cls == Nil) { return nil; }
        if (!SNNightShiftCheck(cls, @selector(getBlueLightStatus:), NO, "^")) { return nil; }
        if (!SNNightShiftCheck(cls, @selector(setEnabled:), NO, "B")) { return nil; }
        if (!SNNightShiftCheck(cls, @selector(setStrength:commit:), NO, "fB")) { return nil; }
        if (!SNNightShiftCheck(cls, @selector(getStrength:), NO, "^")) { return nil; }
        if (SNNightShiftCheck(cls, @selector(supportsBlueLightReduction), YES, "")) {
            if (![(id<SNBlueLightClientClassAPI>)(id)cls supportsBlueLightReduction]) { return nil; }
        }
        client = (id<SNBlueLightClientAPI>)[[cls alloc] init];
    } @catch (NSException *exception) {
        client = nil;
    }
    return client;
}

@implementation SNNightShift

+ (BOOL)isAvailable { return SNNightShiftClient() != nil; }

+ (nullable NSNumber *)isEnabled {
    id<SNBlueLightClientAPI> client = SNNightShiftClient();
    if (client == nil) { return nil; }
    @try {
        uint8_t status[256];
        memset(status, 0, sizeof(status));
        if (![client getBlueLightStatus:status]) { return nil; }
        return @(status[1] != 0);
    } @catch (NSException *exception) {
        return nil;
    }
}

+ (BOOL)setEnabled:(BOOL)enabled {
    id<SNBlueLightClientAPI> client = SNNightShiftClient();
    if (client == nil) { return NO; }
    @try {
        return [client setEnabled:enabled];
    } @catch (NSException *exception) {
        return NO;
    }
}

+ (nullable NSNumber *)strength {
    id<SNBlueLightClientAPI> client = SNNightShiftClient();
    if (client == nil) { return nil; }
    @try {
        float value = 0;
        if (![client getStrength:&value]) { return nil; }
        if (!(value >= 0 && value <= 1)) { return nil; }
        return @(value);
    } @catch (NSException *exception) {
        return nil;
    }
}

+ (BOOL)setStrength:(float)strength {
    id<SNBlueLightClientAPI> client = SNNightShiftClient();
    if (client == nil) { return NO; }
    float s = strength < 0 ? 0 : (strength > 1 ? 1 : strength);
    @try {
        return [client setStrength:s commit:YES];
    } @catch (NSException *exception) {
        return NO;
    }
}

@end
