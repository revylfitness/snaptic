#import <Foundation/Foundation.h>

// CGVirtualDisplay family (private CoreGraphics classes), owner: D.
// Used only by the `--virtual-host` helper (VirtualHostMain): one process, one display.
// The classes are looked up with NSClassFromString and every selector's type encoding is
// checked before use; a missing class, a changed encoding or an exception makes the whole
// area unavailable for the life of the process (sticky poison).

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const SNVirtualDisplayErrorDomain;

typedef NS_ERROR_ENUM(SNVirtualDisplayErrorDomain, SNVirtualDisplayErrorCode) {
    /// Classes or selectors missing, or an encoding didn't match.
    SNVirtualDisplayErrorUnavailable = 1,
    /// WindowServer refused the descriptor or the settings.
    SNVirtualDisplayErrorRefused = 2,
    /// Arguments out of range.
    SNVirtualDisplayErrorInvalid = 3,
};

/// One mode, in points (the display is HiDPI when the settings say so).
@interface SNVirtualDisplayMode : NSObject
@property (nonatomic, readonly) uint32_t width;
@property (nonatomic, readonly) uint32_t height;
@property (nonatomic, readonly) double refreshRate;
/// PQ transfer function (needs +supportsHDRModes).
@property (nonatomic, readonly) BOOL hdr;
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate hdr:(BOOL)hdr;
- (instancetype)init NS_UNAVAILABLE;
@end

/// Everything the descriptor needs. Primaries are CIE xy; zero values leave the defaults.
@interface SNVirtualDisplayConfiguration : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) uint32_t vendorID;
@property (nonatomic) uint32_t productID;
@property (nonatomic) uint32_t serial;
@property (nonatomic) double widthMillimeters;
@property (nonatomic) double heightMillimeters;
@property (nonatomic) uint32_t maxPixelsWide;
@property (nonatomic) uint32_t maxPixelsHigh;
@property (nonatomic) BOOL hiDPI;
@property (nonatomic) double redX, redY, greenX, greenY, blueX, blueY, whiteX, whiteY;
@end

/// A live virtual display. It exists while this object (or -invalidate) hasn't released it.
@interface SNVirtualDisplayHandle : NSObject
@property (nonatomic, readonly) uint32_t displayID;
/// Releases the display (removal is asynchronous in WindowServer). Idempotent.
- (void)invalidate;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface SNVirtualDisplay : NSObject

/// The classes exist and every selector we call has the expected encoding.
+ (BOOL)isAvailable;

/// The HDR mode initializer exists with an integer transfer-function argument.
+ (BOOL)supportsHDRModes;

/// Creates the display with a single mode (R5.6). Nil + error on failure.
+ (nullable SNVirtualDisplayHandle *)createWithConfiguration:(SNVirtualDisplayConfiguration *)configuration
                                                 initialMode:(SNVirtualDisplayMode *)mode
                                                       error:(NSError **)error;

/// Replaces the display's mode list (Beta). The parent selects one afterwards.
+ (BOOL)applyModes:(NSArray<SNVirtualDisplayMode *> *)modes
             hiDPI:(BOOL)hiDPI
          toHandle:(SNVirtualDisplayHandle *)handle
             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
