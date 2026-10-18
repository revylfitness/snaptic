#import <Foundation/Foundation.h>

// DDC/CI transport (owner: C). PLAN §7.
//
// Address forms:
//  - Apple silicon: IOAVServiceWriteI2C(service, chip, dataAddress, buffer, length) with the
//    7-bit chip address 0x37 (0xB7 on MCDP29xx DP→HDMI ports: M1 / entry-M2 built-in HDMI)
//    and the host source address 0x51 as the I²C *data address* (0x50 for LG's alternate
//    input addressing). The buffer starts at the length byte: [0x80|n, body…, checksum].
//    Replies are read with IOAVServiceReadI2C(service, chip, 0, buffer, length).
//  - Intel: IOI2CSendRequest with 8-bit addresses: send to 0x6E, reply from 0x6F with
//    sub-address 0x51. The buffer includes the source byte: [0x51, 0x80|n, body…, checksum].
//
// Both paths refuse, in C, any chip address outside {0x37, 0xB7}, any buffer over 64 bytes,
// and any request the Snaptic VCP policy denies (reset/lock codes, power values outside
// 1–4, mute values outside 1–4, any opcode but Get VCP, Set VCP and Capabilities). Set VCP
// writes the policy only allows after confirmation (input 0x60, standby, screen-blank
// mute values, every manufacturer code 0xE0–0xFF) also need `confirmed`. The table mirrors
// Kit `VCPPolicy.backstopTier`. All calls block (they sleep between the
// request and the reply): call them from one serial queue, never the main thread.

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SNDDCTransportKind) {
    SNDDCTransportKindAppleSilicon = 0,
    SNDDCTransportKindAppleSiliconMCDP = 1,
    SNDDCTransportKindIntel = 2,
};

/// One display's DDC endpoint (a retained IOAVService, or an Intel framebuffer). Released
/// when the object is deallocated.
@interface SNDDCEndpoint : NSObject
@property (nonatomic, readonly) SNDDCTransportKind kind;
/// 0x37, or 0xB7 for MCDP29xx ports.
@property (nonatomic, readonly) uint8_t chipAddress;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

@interface SNDDC : NSObject

/// True when a DDC transport exists on this Mac (Apple silicon IOAVService symbols, or the
/// Intel I²C functions).
+ (BOOL)isAvailable;

/// True on Apple silicon (IOAVService path).
+ (BOOL)isAppleSilicon;

/// The DDC endpoint of an online display (CGDirectDisplayID), or nil (built-in panels,
/// docks without DDC, AirPlay, virtual displays).
+ (nullable SNDDCEndpoint *)endpointForDisplay:(uint32_t)displayID error:(NSError **)error
    NS_SWIFT_NAME(endpoint(forDisplay:));

/// Sends `request` and, when `replyLength` > 0, reads that many reply bytes after waiting
/// `replyDelayMicroseconds`. `dataAddress` is 0x51 (or 0x50 for LG alternate input).
/// `confirmed`: the caller holds a PreConfirm token for this write (and, for manufacturer
/// codes, the per-display unlock); without it only safe Set VCP values are sent.
/// Returns the reply (empty for writes) or nil on failure.
+ (nullable NSData *)transact:(NSData *)request
                   onEndpoint:(SNDDCEndpoint *)endpoint
                  dataAddress:(uint8_t)dataAddress
                  replyLength:(NSUInteger)replyLength
       replyDelayMicroseconds:(uint32_t)replyDelayMicroseconds
                    confirmed:(BOOL)confirmed
                        error:(NSError **)error
    NS_SWIFT_NAME(transact(_:endpoint:dataAddress:replyLength:replyDelayMicroseconds:confirmed:));

@end

NS_ASSUME_NONNULL_END
