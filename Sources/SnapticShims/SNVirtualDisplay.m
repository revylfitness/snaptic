#import "SNVirtualDisplay.h"
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

#if !__has_feature(objc_arc)
#error "SnapticShims requires ARC"
#endif

// CGVirtualDisplay family (owner: D). See SNVirtualDisplay.h.
//
// The private classes are described by local protocols only (no @interface for a private
// class, so nothing is linked by name). Each selector is checked with
// method_getTypeEncoding before the first use; anything unexpected poisons the area.

NSErrorDomain const SNVirtualDisplayErrorDomain = @"app.snaptic.virtual-display";

@protocol SNCGVirtualDisplayDescriptor <NSObject>
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic) unsigned int serialNumber;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGPoint redPrimary;
@property (nonatomic) CGPoint greenPrimary;
@property (nonatomic) CGPoint bluePrimary;
@property (nonatomic) CGPoint whitePoint;
@property (nonatomic, strong) dispatch_queue_t queue;
@end

@protocol SNCGVirtualDisplayMode <NSObject>
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate
             transferFunction:(unsigned int)transferFunction;
@end

@protocol SNCGVirtualDisplaySettings <NSObject>
@property (nonatomic, strong) NSArray *modes;
@property (nonatomic) unsigned int hiDPI;
@end

@protocol SNCGVirtualDisplay <NSObject>
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property (nonatomic, readonly) unsigned int displayID;
@end

#pragma mark - Encoding checks

static BOOL gPoisoned = NO;

/// Strips frame offsets and treats BOOL as `c` on both architectures ("c24@0:8@16" → "c@:@").
static NSString *SNVDNormalize(const char *types) {
    if (types == NULL) { return @""; }
    NSMutableString *out = [NSMutableString string];
    for (const char *p = types; *p != '\0'; p++) {
        char c = *p;
        if (c >= '0' && c <= '9') { continue; }
        if (c == 'B') { c = 'c'; }
        [out appendFormat:@"%c", c];
    }
    return out;
}

static NSString *SNVDEncoding(Class cls, NSString *selectorName) {
    if (cls == Nil) { return nil; }
    Method m = class_getInstanceMethod(cls, NSSelectorFromString(selectorName));
    if (m == NULL) { return nil; }
    return SNVDNormalize(method_getTypeEncoding(m));
}

static BOOL SNVDMatches(Class cls, NSString *selectorName, NSString *expected) {
    NSString *actual = SNVDEncoding(cls, selectorName);
    return actual != nil && [actual isEqualToString:SNVDNormalize(expected.UTF8String)];
}

typedef struct {
    BOOL checked;
    BOOL available;
    BOOL hasSerialNumber;
    BOOL hdr;
} SNVDProbe;

static SNVDProbe gProbe;

static Class SNVDClass(NSString *name) { return NSClassFromString(name); }

static SNVDProbe SNVDRunProbe(void) {
    if (gProbe.checked) { return gProbe; }
    SNVDProbe probe = { .checked = YES, .available = NO, .hasSerialNumber = NO, .hdr = NO };
    @try {
        Class desc = SNVDClass(@"CGVirtualDisplayDescriptor");
        Class mode = SNVDClass(@"CGVirtualDisplayMode");
        Class settings = SNVDClass(@"CGVirtualDisplaySettings");
        Class display = SNVDClass(@"CGVirtualDisplay");
        if (desc && mode && settings && display) {
            NSString *uintSetter = @"v@:I";
            NSString *pointSetter = @"v@:{CGPoint=dd}";
            BOOL ok = SNVDMatches(desc, @"init", @"@@:")
                && SNVDMatches(desc, @"setVendorID:", uintSetter)
                && SNVDMatches(desc, @"setProductID:", uintSetter)
                && SNVDMatches(desc, @"setSerialNum:", uintSetter)
                && SNVDMatches(desc, @"setName:", @"v@:@")
                && SNVDMatches(desc, @"setSizeInMillimeters:", @"v@:{CGSize=dd}")
                && SNVDMatches(desc, @"setMaxPixelsWide:", uintSetter)
                && SNVDMatches(desc, @"setMaxPixelsHigh:", uintSetter)
                && SNVDMatches(desc, @"setRedPrimary:", pointSetter)
                && SNVDMatches(desc, @"setGreenPrimary:", pointSetter)
                && SNVDMatches(desc, @"setBluePrimary:", pointSetter)
                && SNVDMatches(desc, @"setWhitePoint:", pointSetter)
                && SNVDMatches(desc, @"setQueue:", @"v@:@")
                && SNVDMatches(mode, @"initWithWidth:height:refreshRate:", @"@@:IId")
                && SNVDMatches(settings, @"init", @"@@:")
                && SNVDMatches(settings, @"setModes:", @"v@:@")
                && SNVDMatches(settings, @"setHiDPI:", uintSetter)
                && SNVDMatches(display, @"initWithDescriptor:", @"@@:@")
                && SNVDMatches(display, @"applySettings:", @"c@:@")
                && SNVDMatches(display, @"displayID", @"I@:");
            probe.available = ok;
            probe.hasSerialNumber = SNVDMatches(desc, @"setSerialNumber:", uintSetter);
            // force-hidpi passes an unsigned int; Chromium declares an object. Only an
            // integer argument is accepted (macos-display-apis §4).
            NSString *hdr = SNVDEncoding(mode, @"initWithWidth:height:refreshRate:transferFunction:");
            probe.hdr = ok && ([hdr isEqualToString:@"@@:IIdI"] || [hdr isEqualToString:@"@@:IIdi"]
                               || [hdr isEqualToString:@"@@:IIdQ"] || [hdr isEqualToString:@"@@:IIdq"]);
        }
    } @catch (NSException *exception) {
        gPoisoned = YES;
        probe.available = NO;
        probe.hdr = NO;
    }
    gProbe = probe;
    return probe;
}

static NSError *SNVDError(SNVirtualDisplayErrorCode code) {
    return [NSError errorWithDomain:SNVirtualDisplayErrorDomain code:code userInfo:nil];
}

#pragma mark - Value types

@implementation SNVirtualDisplayMode
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate hdr:(BOOL)hdr {
    if ((self = [super init])) {
        _width = width;
        _height = height;
        _refreshRate = refreshRate;
        _hdr = hdr;
    }
    return self;
}
@end

@implementation SNVirtualDisplayConfiguration
- (instancetype)init {
    if ((self = [super init])) {
        _name = @"Snaptic Virtual";
    }
    return self;
}
@end

@interface SNVirtualDisplayHandle ()
@property (nonatomic, strong, nullable) id display;
@property (nonatomic, readwrite) uint32_t displayID;
@end

@implementation SNVirtualDisplayHandle
- (instancetype)initWithDisplay:(id)display displayID:(uint32_t)displayID {
    if ((self = [super init])) {
        _display = display;
        _displayID = displayID;
    }
    return self;
}

- (void)invalidate {
    @try {
        self.display = nil;
    } @catch (NSException *exception) {
        gPoisoned = YES;
    }
}
@end

#pragma mark - SNVirtualDisplay

@implementation SNVirtualDisplay

+ (BOOL)isAvailable {
    if (gPoisoned) { return NO; }
    return SNVDRunProbe().available;
}

+ (BOOL)supportsHDRModes {
    if (gPoisoned) { return NO; }
    return SNVDRunProbe().hdr;
}

static BOOL SNVDValidMode(SNVirtualDisplayMode *m) {
    return m.width >= 160 && m.height >= 160 && m.width <= 16384 && m.height <= 16384 && m.refreshRate >= 24
        && m.refreshRate <= 240 && isfinite(m.refreshRate);
}

static BOOL SNVDPlausible(double v) { return isfinite(v) && v > 0 && v < 1; }

/// Builds a CGVirtualDisplayMode; nil if HDR was asked for but isn't supported.
static id SNVDMakeMode(SNVirtualDisplayMode *m, SNVDProbe probe) {
    Class cls = SNVDClass(@"CGVirtualDisplayMode");
    if (cls == Nil) { return nil; }
    if (m.hdr) {
        if (!probe.hdr) { return nil; }
        id<SNCGVirtualDisplayMode> alloc = (id<SNCGVirtualDisplayMode>)[cls alloc];
        return [alloc initWithWidth:m.width height:m.height refreshRate:m.refreshRate transferFunction:1];
    }
    id<SNCGVirtualDisplayMode> alloc = (id<SNCGVirtualDisplayMode>)[cls alloc];
    return [alloc initWithWidth:m.width height:m.height refreshRate:m.refreshRate];
}

static id SNVDMakeSettings(NSArray<SNVirtualDisplayMode *> *modes, BOOL hiDPI, SNVDProbe probe) {
    Class cls = SNVDClass(@"CGVirtualDisplaySettings");
    if (cls == Nil) { return nil; }
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:modes.count];
    for (SNVirtualDisplayMode *m in modes) {
        if (!SNVDValidMode(m)) { return nil; }
        id mode = SNVDMakeMode(m, probe);
        if (mode == nil) { return nil; }
        [list addObject:mode];
    }
    id<SNCGVirtualDisplaySettings> settings = (id<SNCGVirtualDisplaySettings>)[[cls alloc] init];
    if (settings == nil) { return nil; }
    settings.modes = list;
    settings.hiDPI = hiDPI ? 1 : 0;
    return settings;
}

+ (nullable SNVirtualDisplayHandle *)createWithConfiguration:(SNVirtualDisplayConfiguration *)c
                                                 initialMode:(SNVirtualDisplayMode *)mode
                                                       error:(NSError **)error {
    SNVDProbe probe = SNVDRunProbe();
    if (gPoisoned || !probe.available) {
        if (error) { *error = SNVDError(SNVirtualDisplayErrorUnavailable); }
        return nil;
    }
    uint32_t scale = c.hiDPI ? 2 : 1;
    if (c.vendorID == 0 || c.serial == 0 || !SNVDValidMode(mode) || c.maxPixelsWide == 0 || c.maxPixelsHigh == 0
        || c.maxPixelsWide > 16384 || c.maxPixelsHigh > 16384 || (uint64_t)mode.width * scale > c.maxPixelsWide
        || (uint64_t)mode.height * scale > c.maxPixelsHigh || !isfinite(c.widthMillimeters) || !isfinite(c.heightMillimeters)
        || c.widthMillimeters <= 0 || c.heightMillimeters <= 0) {
        if (error) { *error = SNVDError(SNVirtualDisplayErrorInvalid); }
        return nil;
    }
    @try {
        Class descCls = SNVDClass(@"CGVirtualDisplayDescriptor");
        Class displayCls = SNVDClass(@"CGVirtualDisplay");
        id<SNCGVirtualDisplayDescriptor> desc = (id<SNCGVirtualDisplayDescriptor>)[[descCls alloc] init];
        if (desc == nil) {
            if (error) { *error = SNVDError(SNVirtualDisplayErrorRefused); }
            return nil;
        }
        // A dedicated serial queue, not main: the helper's main thread runs CFRunLoopRun,
        // but WindowServer callbacks shouldn't depend on it.
        desc.queue = dispatch_queue_create("app.snaptic.virtual-display", DISPATCH_QUEUE_SERIAL);
        desc.name = c.name.length > 0 ? c.name : @"Snaptic Virtual";
        desc.vendorID = c.vendorID;
        desc.productID = c.productID;
        desc.serialNum = c.serial;
        if (probe.hasSerialNumber) { desc.serialNumber = c.serial; }
        desc.sizeInMillimeters = CGSizeMake(c.widthMillimeters, c.heightMillimeters);
        desc.maxPixelsWide = c.maxPixelsWide;
        desc.maxPixelsHigh = c.maxPixelsHigh;
        if (SNVDPlausible(c.redX) && SNVDPlausible(c.redY) && SNVDPlausible(c.greenX) && SNVDPlausible(c.greenY)
            && SNVDPlausible(c.blueX) && SNVDPlausible(c.blueY) && SNVDPlausible(c.whiteX) && SNVDPlausible(c.whiteY)) {
            desc.redPrimary = CGPointMake(c.redX, c.redY);
            desc.greenPrimary = CGPointMake(c.greenX, c.greenY);
            desc.bluePrimary = CGPointMake(c.blueX, c.blueY);
            desc.whitePoint = CGPointMake(c.whiteX, c.whiteY);
        } else {
            // sRGB / D65.
            desc.redPrimary = CGPointMake(0.64, 0.33);
            desc.greenPrimary = CGPointMake(0.30, 0.60);
            desc.bluePrimary = CGPointMake(0.15, 0.06);
            desc.whitePoint = CGPointMake(0.3127, 0.3290);
        }
        // terminationHandler stays nil (crashes seen when it fires during process exit).

        id<SNCGVirtualDisplay> display = (id<SNCGVirtualDisplay>)[(id<SNCGVirtualDisplay>)[displayCls alloc] initWithDescriptor:desc];
        if (display == nil) {
            if (error) { *error = SNVDError(SNVirtualDisplayErrorRefused); }
            return nil;
        }
        id settings = SNVDMakeSettings(@[ mode ], c.hiDPI, probe);
        if (settings == nil) {
            if (error) { *error = SNVDError(SNVirtualDisplayErrorInvalid); }
            return nil;   // `display` is released here, which removes it.
        }
        if (![display applySettings:settings]) {
            if (error) { *error = SNVDError(SNVirtualDisplayErrorRefused); }
            return nil;
        }
        uint32_t displayID = display.displayID;
        if (displayID == 0 || displayID == kCGNullDirectDisplay) {
            if (error) { *error = SNVDError(SNVirtualDisplayErrorRefused); }
            return nil;
        }
        return [[SNVirtualDisplayHandle alloc] initWithDisplay:display displayID:displayID];
    } @catch (NSException *exception) {
        gPoisoned = YES;
        if (error) { *error = SNVDError(SNVirtualDisplayErrorUnavailable); }
        return nil;
    }
}

+ (BOOL)applyModes:(NSArray<SNVirtualDisplayMode *> *)modes
             hiDPI:(BOOL)hiDPI
          toHandle:(SNVirtualDisplayHandle *)handle
             error:(NSError **)error {
    SNVDProbe probe = SNVDRunProbe();
    if (gPoisoned || !probe.available) {
        if (error) { *error = SNVDError(SNVirtualDisplayErrorUnavailable); }
        return NO;
    }
    if (modes.count == 0 || modes.count > 200 || handle.display == nil) {
        if (error) { *error = SNVDError(SNVirtualDisplayErrorInvalid); }
        return NO;
    }
    @try {
        id settings = SNVDMakeSettings(modes, hiDPI, probe);
        if (settings == nil) {
            if (error) { *error = SNVDError(SNVirtualDisplayErrorInvalid); }
            return NO;
        }
        id<SNCGVirtualDisplay> display = (id<SNCGVirtualDisplay>)handle.display;
        if (![display applySettings:settings]) {
            if (error) { *error = SNVDError(SNVirtualDisplayErrorRefused); }
            return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        gPoisoned = YES;
        if (error) { *error = SNVDError(SNVirtualDisplayErrorUnavailable); }
        return NO;
    }
}

@end
