#import <Foundation/Foundation.h>
#import <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

/// Process facts and code identity (R5.5, R4C §4.2). Safe to call from helper processes:
/// nothing here touches TCC-guarded APIs.
@interface SNProcess : NSObject

+ (BOOL)isAvailable;

/// The executable path of `pid` (proc_pidpath), or nil.
+ (nullable NSString *)pathForPID:(pid_t)pid NS_SWIFT_NAME(path(for:));

/// Start time in microseconds since 1970 (PROC_PIDTBSDINFO), or 0 if the process is gone.
/// Together with the pid it identifies one process (pids are reused).
+ (uint64_t)startTimeForPID:(pid_t)pid NS_SWIFT_NAME(startTime(for:));

/// Open file descriptors of this process (PROC_PIDLISTFDS), or nil if unavailable.
+ (nullable NSArray<NSNumber *> *)openFileDescriptors;

/// The designated requirement of the running code, as SecRequirement data. Captured once
/// at launch: ad-hoc and linker-signed builds get `cdhash H"…"`, so a replaced bundle no
/// longer satisfies it.
+ (nullable NSData *)designatedRequirementOfSelfWithError:(NSError **)error
    NS_SWIFT_NAME(designatedRequirementOfSelf());

/// True when the running process `pid` satisfies `requirement` (SecRequirement data).
/// For a suspended, unreaped child the pid can't be reused, so the answer is reliable.
+ (BOOL)processWithPID:(pid_t)pid satisfiesRequirement:(NSData *)requirement
    NS_SWIFT_NAME(process(_:satisfies:));

/// "Developer ID Application: Name (TEAM)", "ad-hoc", or "unsigned".
+ (NSString *)signerDescriptionOfSelf;

/// The code-signing identifier of the file at `path` (nil when unsigned or unreadable).
+ (nullable NSString *)signingIdentifierForPath:(NSString *)path NS_SWIFT_NAME(signingIdentifier(path:));

/// The code-signing identifier of the running process `pid` (dynamic code, so a script
/// reports its interpreter). An empty string when the code is unsigned; nil with an error
/// when the signature couldn't be read (callers fail closed).
+ (nullable NSString *)signingIdentifierForPID:(pid_t)pid error:(NSError **)error
    NS_SWIFT_NAME(signingIdentifier(pid:));

/// This process's code-signing identifier, or nil.
+ (nullable NSString *)signingIdentifierOfSelf;

/// The LC_UUID of the main executable's running slice, or nil.
+ (nullable NSString *)executableUUID;

@end

NS_ASSUME_NONNULL_END
