#import "SNWindowServer.h"
#import <dlfcn.h>

#if !__has_feature(objc_arc)
#error "SnapticShims requires ARC"
#endif

typedef CFArrayRef _Nullable (*SNCaptureFn)(int32_t connection, uint32_t *windowIDs, int32_t count, uint32_t options);

static SNCaptureFn sCapture = NULL;
static NSString *sImagePath = nil;

static void SNWindowServerLookUp(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *symbol = dlsym(RTLD_DEFAULT, "CGSHWCaptureWindowList");
        if (symbol == NULL) { return; }
        sCapture = (SNCaptureFn)symbol;
        Dl_info info;
        if (dladdr(symbol, &info) != 0 && info.dli_fname != NULL) {
            sImagePath = [NSString stringWithUTF8String:info.dli_fname];
        }
    });
}

@implementation SNWindowServer

+ (BOOL)isCapturePresent {
    SNWindowServerLookUp();
    return sCapture != NULL;
}

+ (nullable NSString *)captureImagePath {
    SNWindowServerLookUp();
    return sImagePath;
}

+ (nullable id)captureWithConnection:(int32_t)connection
                           windowIDs:(const uint32_t *)windowIDs
                               count:(NSInteger)count
                             options:(uint32_t)options {
    SNWindowServerLookUp();
    if (sCapture == NULL || windowIDs == NULL || count < 1 || count > SNWindowServerMaxCaptureIDs) { return nil; }
    uint32_t ids[SNWindowServerMaxCaptureIDs] = {0};
    memcpy(ids, windowIDs, (size_t)count * sizeof(uint32_t));
    CFArrayRef result = sCapture(connection, ids, (int32_t)count, options);
    if (result == NULL) { return nil; }
    return CFBridgingRelease(result);
}

@end
