#if !__has_feature(objc_arc)
#error "SnapticShims must be compiled with ARC"
#endif

#import "SNEncoding.h"
#import <objc/runtime.h>

@implementation SNEncoding

+ (NSString *)normalizedEncoding:(NSString *)encoding {
    NSMutableString *result = [NSMutableString stringWithCapacity:encoding.length];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    for (NSUInteger i = 0; i < encoding.length; i++) {
        unichar c = [encoding characterAtIndex:i];
        if (![digits characterIsMember:c]) {
            [result appendFormat:@"%C", c];
        }
    }
    return result;
}

+ (BOOL)encoding:(NSString *)actual matches:(NSString *)expected boolAware:(BOOL)boolAware {
    NSString *a = [self normalizedEncoding:actual];
    NSString *e = [self normalizedEncoding:expected];
    if (boolAware) {
        a = [a stringByReplacingOccurrencesOfString:@"B" withString:@"c"];
        e = [e stringByReplacingOccurrencesOfString:@"B" withString:@"c"];
    }
    return [a isEqualToString:e];
}

+ (nullable NSString *)rawEncodingForClass:(NSString *)className
                                  selector:(NSString *)selectorName
                               classMethod:(BOOL)classMethod {
    @try {
        Class cls = NSClassFromString(className);
        if (cls == Nil) { return nil; }
        SEL sel = NSSelectorFromString(selectorName);
        Method method = classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
        if (method == NULL) { return nil; }
        const char *types = method_getTypeEncoding(method);
        if (types == NULL) { return nil; }
        return [NSString stringWithUTF8String:types];
    } @catch (NSException *exception) {
        return nil;
    }
}

+ (BOOL)verifyClass:(NSString *)className
           selector:(NSString *)selectorName
           expected:(NSString *)expectedEncoding
        classMethod:(BOOL)classMethod {
    @try {
        Class cls = NSClassFromString(className);
        if (cls == Nil) { return NO; }
        SEL sel = NSSelectorFromString(selectorName);
        Method method = classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
        if (method == NULL) { return NO; }
        const char *types = method_getTypeEncoding(method);
        if (types == NULL) { return NO; }
        NSString *actual = [NSString stringWithUTF8String:types];
        if (actual == nil) { return NO; }
        return [self encoding:actual matches:expectedEncoding boolAware:YES];
    } @catch (NSException *exception) {
        return NO;
    }
}

@end
