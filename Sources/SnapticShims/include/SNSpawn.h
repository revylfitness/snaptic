#import <Foundation/Foundation.h>
#import <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

/// Options for +spawnSuspended:… (R4C §4.1).
typedef NS_OPTIONS(uint32_t, SNSpawnOptions) {
    /// The child leads its own process group (hooks, so a timeout can killpg it).
    SNSpawnOwnProcessGroup = 1 << 0,
    /// The child is responsible for itself for TCC (it never inherits Snaptic's grants).
    SNSpawnDisclaim = 1 << 1,
};

FOUNDATION_EXPORT NSErrorDomain const SNSpawnErrorDomain;

typedef NS_ENUM(NSInteger, SNSpawnErrorCode) {
    SNSpawnErrorDisclaimUnavailable = 1,
    SNSpawnErrorBadArguments = 2,
    SNSpawnErrorAttributes = 3,
    SNSpawnErrorFileActions = 4,
    /// posix_spawn itself failed; the underlying errno is in NSUnderlyingErrorKey.
    SNSpawnErrorSpawnFailed = 5,
};

/// The only place Snaptic starts processes (PLAN §3.2, R5.5).
@interface SNSpawn : NSObject

+ (BOOL)isAvailable;

/// Whether the responsibility SPI used for SNSpawnDisclaim resolves on this system.
+ (BOOL)disclaimAvailable;

/// Spawns `path` suspended (POSIX_SPAWN_START_SUSPENDED) with argv = [path] + arguments,
/// an empty environment, CLOEXEC_DEFAULT, every signal at its default disposition, an
/// empty signal mask and the running architecture preferred. stdinFD and stdoutFD are
/// dup2'd to 0 and 1 (-1 → /dev/null); 2 is always /dev/null. The caller resumes the
/// child with SIGCONT after verifying it.
+ (BOOL)spawnSuspended:(NSString *)path
             arguments:(NSArray<NSString *> *)arguments
               stdinFD:(int)stdinFD
              stdoutFD:(int)stdoutFD
               options:(SNSpawnOptions)options
                   pid:(pid_t *)outPID
                 error:(NSError **)error NS_SWIFT_NAME(spawnSuspended(path:arguments:stdinFD:stdoutFD:options:pid:));

/// As above, with `environment` ("NAME=value" strings) as the child's whole environment.
+ (BOOL)spawnSuspended:(NSString *)path
             arguments:(NSArray<NSString *> *)arguments
           environment:(NSArray<NSString *> *)environment
               stdinFD:(int)stdinFD
              stdoutFD:(int)stdoutFD
               options:(SNSpawnOptions)options
                   pid:(pid_t *)outPID
                 error:(NSError **)error
    NS_SWIFT_NAME(spawnSuspended(path:arguments:environment:stdinFD:stdoutFD:options:pid:));

/// True when `pid` exists and is stopped (PROC_PIDTBSDINFO status SSTOP).
+ (BOOL)isStopped:(pid_t)pid NS_SWIFT_NAME(isStopped(_:));

/// The process responsible for `pid` for TCC, or -1 when unavailable.
+ (pid_t)responsiblePIDForPID:(pid_t)pid NS_SWIFT_NAME(responsiblePID(for:));

@end

NS_ASSUME_NONNULL_END
