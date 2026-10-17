#import "SNCGSModes.h"

#if !__has_feature(objc_arc)
#error "SnapticShims requires ARC"
#endif

typedef void (*SNCGSCountFn)(uint32_t display, int *count);
typedef void (*SNCGSDescribeFn)(uint32_t display, int index, void *out, int length);
typedef void (*SNCGSCurrentFn)(uint32_t display, int *mode);

#define kSNCGSRecordLength 0xD4
#define kSNCGSMaxModes 4096

@implementation SNCGSModes

+ (NSInteger)recordLength { return kSNCGSRecordLength; }

+ (nullable NSArray<NSData *> *)recordsForDisplay:(uint32_t)display
                                    countFunction:(const void *)countFunction
                                 describeFunction:(const void *)describeFunction {
    if (countFunction == NULL || describeFunction == NULL) { return nil; }
    SNCGSCountFn count = (SNCGSCountFn)countFunction;
    SNCGSDescribeFn describe = (SNCGSDescribeFn)describeFunction;
    int n = -1;
    count(display, &n);
    if (n < 0 || n > kSNCGSMaxModes) { return nil; }
    NSMutableArray<NSData *> *records = [NSMutableArray arrayWithCapacity:(NSUInteger)n];
    // Twice the record length of zeroed slack, so a callee that writes more than it was
    // told can't run past our buffer.
    uint8_t buffer[kSNCGSRecordLength * 2];
    for (int i = 0; i < n; i++) {
        memset(buffer, 0, sizeof(buffer));
        describe(display, i, buffer, kSNCGSRecordLength);
        [records addObject:[NSData dataWithBytes:buffer length:kSNCGSRecordLength]];
    }
    return records;
}

+ (int32_t)currentModeForDisplay:(uint32_t)display currentFunction:(const void *)currentFunction {
    if (currentFunction == NULL) { return -1; }
    int mode = -1;
    ((SNCGSCurrentFn)currentFunction)(display, &mode);
    return mode < 0 ? -1 : (int32_t)mode;
}

@end
