#import "SNDDC.h"

#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/i2c/IOI2CInterface.h>
#import <dlfcn.h>
#import <string.h>
#import <unistd.h>

#if !__has_feature(objc_arc)
#error "SnapticShims requires ARC"
#endif

// DDC/CI transport (owner: C). Every private symbol is resolved at runtime; the display ↔
// DCPAVServiceProxy match follows the IORegistry walk m1ddc documents (MIT; credited in
// THIRD_PARTY_NOTICES), re-implemented here.

static NSString *const SNDDCErrorDomain = @"SNDDC";
static const size_t SNDDCMaxBuffer = 64;

typedef CFTypeRef (*SNAVCreateWithServiceFn)(CFAllocatorRef, io_service_t);
typedef IOReturn (*SNAVI2CFn)(CFTypeRef, uint32_t, uint32_t, void *, uint32_t);
typedef CFDictionaryRef (*SNCoreDisplayInfoFn)(CGDirectDisplayID);
typedef void (*SNServiceForDisplayFn)(CGDirectDisplayID, io_service_t *);
typedef IOReturn (*SNFBI2CCountFn)(io_service_t, IOItemCount *);
typedef IOReturn (*SNFBCopyI2CFn)(io_service_t, IOOptionBits, io_service_t *);
typedef IOReturn (*SNI2COpenFn)(io_service_t, IOOptionBits, IOI2CConnectRef *);
typedef IOReturn (*SNI2CCloseFn)(IOI2CConnectRef, IOOptionBits);
typedef IOReturn (*SNI2CSendFn)(IOI2CConnectRef, IOOptionBits, IOI2CRequest *);

typedef struct {
    SNAVCreateWithServiceFn avCreate;
    SNAVI2CFn avRead;
    SNAVI2CFn avWrite;
    SNCoreDisplayInfoFn displayInfo;
    SNServiceForDisplayFn serviceForDisplay;
    SNFBI2CCountFn i2cCount;
    SNFBCopyI2CFn i2cCopy;
    SNI2COpenFn i2cOpen;
    SNI2CCloseFn i2cClose;
    SNI2CSendFn i2cSend;
} SNDDCSymbols;

static SNDDCSymbols SNDDCLoad(void) {
    static SNDDCSymbols symbols;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        memset(&symbols, 0, sizeof(symbols));
        symbols.avCreate = (SNAVCreateWithServiceFn)dlsym(RTLD_DEFAULT, "IOAVServiceCreateWithService");
        symbols.avRead = (SNAVI2CFn)dlsym(RTLD_DEFAULT, "IOAVServiceReadI2C");
        symbols.avWrite = (SNAVI2CFn)dlsym(RTLD_DEFAULT, "IOAVServiceWriteI2C");
        void *coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY | RTLD_LOCAL);
        if (coreDisplay != NULL) {
            symbols.displayInfo = (SNCoreDisplayInfoFn)dlsym(coreDisplay, "CoreDisplay_DisplayCreateInfoDictionary");
        }
        symbols.serviceForDisplay = (SNServiceForDisplayFn)dlsym(RTLD_DEFAULT, "CGSServiceForDisplayNumber");
        symbols.i2cCount = (SNFBI2CCountFn)dlsym(RTLD_DEFAULT, "IOFBGetI2CInterfaceCount");
        symbols.i2cCopy = (SNFBCopyI2CFn)dlsym(RTLD_DEFAULT, "IOFBCopyI2CInterfaceForBus");
        symbols.i2cOpen = (SNI2COpenFn)dlsym(RTLD_DEFAULT, "IOI2CInterfaceOpen");
        symbols.i2cClose = (SNI2CCloseFn)dlsym(RTLD_DEFAULT, "IOI2CInterfaceClose");
        symbols.i2cSend = (SNI2CSendFn)dlsym(RTLD_DEFAULT, "IOI2CSendRequest");
    });
    return symbols;
}

static BOOL SNDDCHasAppleSiliconSymbols(SNDDCSymbols s) {
    return s.avCreate != NULL && s.avRead != NULL && s.avWrite != NULL;
}

static BOOL SNDDCHasIntelSymbols(SNDDCSymbols s) {
    return s.serviceForDisplay != NULL && s.i2cCount != NULL && s.i2cCopy != NULL && s.i2cOpen != NULL
        && s.i2cClose != NULL && s.i2cSend != NULL;
}

static NSError *SNDDCError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:SNDDCErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

// MARK: Policy (mirrors Kit VCPPolicy; the shim refuses denied requests itself)

static BOOL SNDDCSetAllowed(uint8_t code, uint16_t value) {
    switch (code) {
        case 0x01: case 0x04: case 0x05: case 0x06: case 0x08: case 0x0A: case 0xB0: case 0xCA: case 0xCC:
            return NO;
        case 0xD6:
            return value >= 1 && value <= 4;
        case 0x10: case 0x12: case 0x13: case 0x14: case 0x16: case 0x18: case 0x1A: case 0x60: case 0x62:
        case 0x6B: case 0x6C: case 0x6E: case 0x70: case 0x87: case 0x8A: case 0x8D: case 0xDC:
            return YES;
        default:
            return code >= 0xE0;
    }
}

/// Checks framing, exact length and opcode. `offset` is 1 when the buffer starts with the
/// source byte (Intel), else 0.
static BOOL SNDDCRequestAllowed(const uint8_t *bytes, size_t length, size_t offset) {
    if (length > SNDDCMaxBuffer || length < offset + 3) { return NO; }
    if (offset == 1 && bytes[0] != 0x51 && bytes[0] != 0x50) { return NO; }
    uint8_t lengthByte = bytes[offset];
    if ((lengthByte & 0x80) == 0) { return NO; }
    size_t n = lengthByte & 0x7F;
    if (length != offset + 1 + n + 1) { return NO; }
    uint8_t opcode = bytes[offset + 1];
    switch (opcode) {
        case 0x01:
            return n == 2;
        case 0xF3:
            return n == 3;
        case 0x03: {
            if (n != 4) { return NO; }
            uint8_t code = bytes[offset + 2];
            uint16_t value = (uint16_t)((bytes[offset + 3] << 8) | bytes[offset + 4]);
            return SNDDCSetAllowed(code, value);
        }
        default:
            return NO;
    }
}

static BOOL SNDDCChipAllowed(uint8_t chip) { return chip == 0x37 || chip == 0xB7; }

// MARK: Endpoint

@interface SNDDCEndpoint ()
- (instancetype)initWithKind:(SNDDCTransportKind)kind
                     service:(CFTypeRef _Nullable)service
                 framebuffer:(io_service_t)framebuffer NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly, nullable) CFTypeRef avService;
@property (nonatomic, readonly) io_service_t framebuffer;
@property (nonatomic) NSInteger preferredBus;
@end

@implementation SNDDCEndpoint

- (instancetype)initWithKind:(SNDDCTransportKind)kind service:(CFTypeRef)service framebuffer:(io_service_t)framebuffer {
    self = [super init];
    if (self) {
        _kind = kind;
        _chipAddress = kind == SNDDCTransportKindAppleSiliconMCDP ? 0xB7 : 0x37;
        _avService = service;          // owned (+1), released in dealloc
        _framebuffer = framebuffer;    // owned (+1), released in dealloc
        _preferredBus = -1;
    }
    return self;
}

- (void)dealloc {
    if (_avService != NULL) { CFRelease(_avService); }
    if (_framebuffer != IO_OBJECT_NULL) { IOObjectRelease(_framebuffer); }
}

@end

// MARK: Apple silicon matching

static BOOL SNDDCStringProperty(io_registry_entry_t entry, CFStringRef key, NSString *expected) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(entry, key, kCFAllocatorDefault, kNilOptions);
    if (value == NULL) { return NO; }
    BOOL match = CFGetTypeID(value) == CFStringGetTypeID() && [(__bridge NSString *)value isEqualToString:expected];
    CFRelease(value);
    return match;
}

static BOOL SNDDCIsExternalProxy(io_registry_entry_t entry) {
    io_name_t name;
    if (IOObjectGetClass(entry, name) != KERN_SUCCESS) { return NO; }
    if (strcmp(name, "DCPAVServiceProxy") != 0) { return NO; }
    return SNDDCStringProperty(entry, CFSTR("Location"), @"External");
}

static BOOL SNDDCIsMCDP(io_registry_entry_t proxy) {
    io_registry_entry_t parent = IO_OBJECT_NULL;
    if (IORegistryEntryGetParentEntry(proxy, kIOServicePlane, &parent) != KERN_SUCCESS) { return NO; }
    BOOL mcdp = SNDDCStringProperty(parent, CFSTR("EPICProviderClass"), @"AppleDCPMCDP29XX");
    IOObjectRelease(parent);
    return mcdp;
}

/// The display's IODisplayLocation from CoreDisplay, or nil.
static NSString *SNDDCDisplayLocation(SNDDCSymbols s, CGDirectDisplayID displayID) {
    if (s.displayInfo == NULL) { return nil; }
    CFDictionaryRef info = s.displayInfo(displayID);   // +1
    if (info == NULL) { return nil; }
    NSString *location = nil;
    if (CFGetTypeID(info) == CFDictionaryGetTypeID()) {
        CFTypeRef value = CFDictionaryGetValue(info, CFSTR("IODisplayLocation"));
        if (value != NULL && CFGetTypeID(value) == CFStringGetTypeID()) {
            location = [(__bridge NSString *)value copy];
        }
    }
    CFRelease(info);
    return location;
}

/// Walks the service plane: after the framebuffer whose registry id matches, the next
/// external DCPAVServiceProxy is this display's AV service. Returns a retained entry or 0.
static io_service_t SNDDCProxyForFramebufferID(uint64_t framebufferID, NSUInteger *externalCount) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, kIORegistryIterateRecursively, &iterator)
        != KERN_SUCCESS) {
        return IO_OBJECT_NULL;
    }
    io_service_t result = IO_OBJECT_NULL;
    io_service_t onlyExternal = IO_OBJECT_NULL;
    NSUInteger externals = 0;
    BOOL foundFramebuffer = NO;
    io_registry_entry_t entry;
    while ((entry = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        BOOL keep = NO;
        if (SNDDCIsExternalProxy(entry)) {
            externals += 1;
            if (foundFramebuffer && result == IO_OBJECT_NULL) {
                result = entry;
                keep = YES;
            } else if (externals == 1) {
                onlyExternal = entry;
                keep = YES;
            }
        } else if (result == IO_OBJECT_NULL && framebufferID != 0) {
            uint64_t entryID = 0;
            if (IORegistryEntryGetRegistryEntryID(entry, &entryID) == KERN_SUCCESS && entryID == framebufferID) {
                foundFramebuffer = YES;
            }
        }
        if (!keep) { IOObjectRelease(entry); }
    }
    IOObjectRelease(iterator);
    if (externalCount != NULL) { *externalCount = externals; }
    if (result != IO_OBJECT_NULL) {
        if (onlyExternal != IO_OBJECT_NULL && onlyExternal != result) { IOObjectRelease(onlyExternal); }
        return result;
    }
    if (externals == 1 && onlyExternal != IO_OBJECT_NULL && framebufferID == 0) {
        return onlyExternal;   // caller decides whether the single-proxy fallback applies
    }
    if (onlyExternal != IO_OBJECT_NULL) { IOObjectRelease(onlyExternal); }
    return IO_OBJECT_NULL;
}

static NSUInteger SNDDCExternalOnlineDisplays(void) {
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(0, NULL, &count) != kCGErrorSuccess || count == 0) { return 0; }
    if (count > 64) { count = 64; }
    CGDirectDisplayID ids[64];
    if (CGGetOnlineDisplayList(count, ids, &count) != kCGErrorSuccess) { return 0; }
    NSUInteger externals = 0;
    for (uint32_t i = 0; i < count; i++) {
        if (!CGDisplayIsBuiltin(ids[i]) && CGDisplayModelNumber(ids[i]) != 0x76697274) { externals += 1; }
    }
    return externals;
}

@implementation SNDDC

+ (BOOL)isAvailable {
    SNDDCSymbols s = SNDDCLoad();
    return SNDDCHasAppleSiliconSymbols(s) || SNDDCHasIntelSymbols(s);
}

+ (BOOL)isAppleSilicon {
    return SNDDCHasAppleSiliconSymbols(SNDDCLoad());
}

+ (nullable SNDDCEndpoint *)endpointForDisplay:(uint32_t)displayID error:(NSError **)error {
    if (CGDisplayIsBuiltin(displayID)) {
        if (error) { *error = SNDDCError(1, @"Built-in displays have no DDC"); }
        return nil;
    }
    SNDDCSymbols s = SNDDCLoad();
    if (SNDDCHasAppleSiliconSymbols(s)) {
        uint64_t framebufferID = 0;
        NSString *location = SNDDCDisplayLocation(s, displayID);
        if (location != nil) {
            io_registry_entry_t fb = IORegistryEntryCopyFromPath(kIOMainPortDefault, (__bridge CFStringRef)location);
            if (fb != IO_OBJECT_NULL) {
                IORegistryEntryGetRegistryEntryID(fb, &framebufferID);
                IOObjectRelease(fb);
            }
        }
        NSUInteger externals = 0;
        io_service_t proxy = SNDDCProxyForFramebufferID(framebufferID, &externals);
        if (proxy != IO_OBJECT_NULL && framebufferID == 0 && SNDDCExternalOnlineDisplays() != 1) {
            // Without a location match, the single-proxy fallback only applies to one external display.
            IOObjectRelease(proxy);
            proxy = IO_OBJECT_NULL;
        }
        if (proxy == IO_OBJECT_NULL) {
            if (error) { *error = SNDDCError(2, @"No DDC service for this display"); }
            return nil;
        }
        BOOL mcdp = SNDDCIsMCDP(proxy);
        CFTypeRef service = s.avCreate(kCFAllocatorDefault, proxy);   // +1
        IOObjectRelease(proxy);
        if (service == NULL) {
            if (error) { *error = SNDDCError(3, @"IOAVService unavailable"); }
            return nil;
        }
        return [[SNDDCEndpoint alloc] initWithKind:(mcdp ? SNDDCTransportKindAppleSiliconMCDP : SNDDCTransportKindAppleSilicon)
                                           service:service
                                       framebuffer:IO_OBJECT_NULL];
    }
    if (SNDDCHasIntelSymbols(s)) {
        io_service_t framebuffer = IO_OBJECT_NULL;
        s.serviceForDisplay(displayID, &framebuffer);
        if (framebuffer == IO_OBJECT_NULL) {
            if (error) { *error = SNDDCError(4, @"No framebuffer for this display"); }
            return nil;
        }
        // CGSServiceForDisplayNumber doesn't hand over a reference: take our own.
        IOObjectRetain(framebuffer);
        return [[SNDDCEndpoint alloc] initWithKind:SNDDCTransportKindIntel service:NULL framebuffer:framebuffer];
    }
    if (error) { *error = SNDDCError(5, @"DDC isn't available on this Mac"); }
    return nil;
}

+ (nullable NSData *)transact:(NSData *)request
                   onEndpoint:(SNDDCEndpoint *)endpoint
                  dataAddress:(uint8_t)dataAddress
                  replyLength:(NSUInteger)replyLength
       replyDelayMicroseconds:(uint32_t)replyDelayMicroseconds
                        error:(NSError **)error {
    if (!SNDDCChipAllowed(endpoint.chipAddress)) {
        if (error) { *error = SNDDCError(10, @"Chip address refused"); }
        return nil;
    }
    if (request.length > SNDDCMaxBuffer || replyLength > SNDDCMaxBuffer) {
        if (error) { *error = SNDDCError(11, @"Buffer too long"); }
        return nil;
    }
    if (dataAddress != 0x51 && dataAddress != 0x50) {
        if (error) { *error = SNDDCError(12, @"Data address refused"); }
        return nil;
    }
    uint32_t delay = replyDelayMicroseconds > 500000 ? 500000 : replyDelayMicroseconds;
    uint8_t buffer[64];
    memset(buffer, 0, sizeof(buffer));
    memcpy(buffer, request.bytes, request.length);
    SNDDCSymbols s = SNDDCLoad();

    if (endpoint.kind == SNDDCTransportKindIntel) {
        if (!SNDDCRequestAllowed(buffer, request.length, 1)) {
            if (error) { *error = SNDDCError(13, @"Request refused by the VCP policy"); }
            return nil;
        }
        if (!SNDDCHasIntelSymbols(s) || endpoint.framebuffer == IO_OBJECT_NULL) {
            if (error) { *error = SNDDCError(14, @"I2C unavailable"); }
            return nil;
        }
        IOItemCount busCount = 0;
        if (s.i2cCount(endpoint.framebuffer, &busCount) != KERN_SUCCESS || busCount == 0) {
            if (error) { *error = SNDDCError(15, @"No I2C bus"); }
            return nil;
        }
        if (busCount > 8) { busCount = 8; }
        uint8_t reply[64];
        IOItemCount order[8];
        IOItemCount orderCount = 0;
        NSInteger preferred = endpoint.preferredBus;
        if (preferred >= 0 && (IOItemCount)preferred < busCount) { order[orderCount++] = (IOItemCount)preferred; }
        for (IOItemCount b = 0; b < busCount; b++) {
            if (preferred >= 0 && b == (IOItemCount)preferred) { continue; }
            order[orderCount++] = b;
        }
        for (IOItemCount attempt = 0; attempt < orderCount; attempt++) {
            IOItemCount bus = order[attempt];
            io_service_t interface = IO_OBJECT_NULL;
            if (s.i2cCopy(endpoint.framebuffer, bus, &interface) != KERN_SUCCESS || interface == IO_OBJECT_NULL) { continue; }
            IOOptionBits replyType = kIOI2CSimpleTransactionType;
            CFTypeRef types = IORegistryEntryCreateCFProperty(interface, CFSTR(kIOI2CTransactionTypesKey), kCFAllocatorDefault, kNilOptions);
            if (types != NULL) {
                if (CFGetTypeID(types) == CFNumberGetTypeID()) {
                    uint64_t mask = 0;
                    CFNumberGetValue((CFNumberRef)types, kCFNumberSInt64Type, &mask);
                    if (mask & (1ULL << kIOI2CDDCciReplyTransactionType)) { replyType = kIOI2CDDCciReplyTransactionType; }
                }
                CFRelease(types);
            }
            IOI2CConnectRef connect = NULL;
            BOOL ok = NO;
            if (s.i2cOpen(interface, kNilOptions, &connect) == KERN_SUCCESS && connect != NULL) {
                IOI2CRequest r;
                memset(&r, 0, sizeof(r));
                memset(reply, 0, sizeof(reply));
                r.sendAddress = 0x6E;
                r.sendTransactionType = kIOI2CSimpleTransactionType;
                r.sendBuffer = (vm_address_t)buffer;
                r.sendBytes = (uint32_t)request.length;
                if (replyLength > 0) {
                    r.minReplyDelay = (uint64_t)delay * 1000ULL;
                    r.replyAddress = 0x6F;
                    r.replySubAddress = 0x51;
                    r.replyTransactionType = replyType;
                    r.replyBuffer = (vm_address_t)reply;
                    r.replyBytes = (uint32_t)replyLength;
                } else {
                    r.replyTransactionType = kIOI2CNoTransactionType;
                    r.replyBytes = 0;
                }
                ok = s.i2cSend(connect, kNilOptions, &r) == KERN_SUCCESS && r.result == KERN_SUCCESS;
                s.i2cClose(connect, kNilOptions);
            }
            IOObjectRelease(interface);
            if (ok) {
                endpoint.preferredBus = (NSInteger)bus;
                return replyLength > 0 ? [NSData dataWithBytes:reply length:replyLength] : [NSData data];
            }
        }
        if (error) { *error = SNDDCError(16, @"I2C request failed"); }
        return nil;
    }

    if (!SNDDCRequestAllowed(buffer, request.length, 0)) {
        if (error) { *error = SNDDCError(13, @"Request refused by the VCP policy"); }
        return nil;
    }
    if (!SNDDCHasAppleSiliconSymbols(s) || endpoint.avService == NULL) {
        if (error) { *error = SNDDCError(17, @"IOAVService unavailable"); }
        return nil;
    }
    IOReturn result = s.avWrite(endpoint.avService, endpoint.chipAddress, dataAddress, buffer, (uint32_t)request.length);
    if (result != kIOReturnSuccess) {
        if (error) { *error = SNDDCError(18, @"Write failed"); }
        return nil;
    }
    if (replyLength == 0) { return [NSData data]; }
    usleep(delay);
    uint8_t reply[64];
    memset(reply, 0, sizeof(reply));
    result = s.avRead(endpoint.avService, endpoint.chipAddress, 0, reply, (uint32_t)replyLength);
    if (result != kIOReturnSuccess) {
        if (error) { *error = SNDDCError(19, @"Read failed"); }
        return nil;
    }
    return [NSData dataWithBytes:reply length:replyLength];
}

@end
