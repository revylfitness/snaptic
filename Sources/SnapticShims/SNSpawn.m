#import "SNSpawn.h"

#if !__has_feature(objc_arc)
#error "SnapticShims requires ARC"
#endif

#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <libproc.h>
#import <mach/machine.h>
#import <signal.h>
#import <spawn.h>
#import <stdlib.h>
#import <string.h>
#import <sys/proc.h>
#import <sys/proc_info.h>

NSErrorDomain const SNSpawnErrorDomain = @"app.snaptic.spawn";

// Private but stable libsystem SPI (used by Chromium, LLDB and others). Looked up at
// runtime so a missing symbol degrades to "unavailable" instead of failing to launch.
typedef int (*SNDisclaimFn)(posix_spawnattr_t *attrs, int disclaim);
typedef pid_t (*SNResponsibleFn)(pid_t pid);

static SNDisclaimFn SNDisclaim(void) {
    static SNDisclaimFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (SNDisclaimFn)dlsym(RTLD_DEFAULT, "responsibility_spawnattrs_setdisclaim");
    });
    return fn;
}

static SNResponsibleFn SNResponsible(void) {
    static SNResponsibleFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (SNResponsibleFn)dlsym(RTLD_DEFAULT, "responsibility_get_pid_responsible_for_pid");
    });
    return fn;
}

static NSError *SNSpawnMakeError(SNSpawnErrorCode code, int posixError, NSString *what) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[NSLocalizedDescriptionKey] = what;
    if (posixError != 0) {
        info[NSUnderlyingErrorKey] = [NSError errorWithDomain:NSPOSIXErrorDomain code:posixError userInfo:nil];
    }
    return [NSError errorWithDomain:SNSpawnErrorDomain code:code userInfo:info];
}

@implementation SNSpawn

+ (BOOL)isAvailable { return YES; }

+ (BOOL)disclaimAvailable { return SNDisclaim() != NULL; }

+ (BOOL)spawnSuspended:(NSString *)path
             arguments:(NSArray<NSString *> *)arguments
               stdinFD:(int)stdinFD
              stdoutFD:(int)stdoutFD
               options:(SNSpawnOptions)options
                   pid:(pid_t *)outPID
                 error:(NSError **)error {
    if (outPID != NULL) { *outPID = 0; }
    const char *exe = path.length > 0 ? path.fileSystemRepresentation : NULL;
    if (exe == NULL || exe[0] != '/' || arguments.count > 64 || outPID == NULL) {
        if (error) { *error = SNSpawnMakeError(SNSpawnErrorBadArguments, 0, @"Bad spawn arguments"); }
        return NO;
    }

    // argv: [path] + arguments + NULL. The strings live until posix_spawn returns.
    NSMutableArray<NSData *> *storage = [NSMutableArray arrayWithCapacity:arguments.count + 1];
    char **argv = calloc(arguments.count + 2, sizeof(char *));
    if (argv == NULL) {
        if (error) { *error = SNSpawnMakeError(SNSpawnErrorBadArguments, ENOMEM, @"Out of memory"); }
        return NO;
    }
    NSMutableArray<NSString *> *all = [NSMutableArray arrayWithObject:path];
    [all addObjectsFromArray:arguments];
    for (NSUInteger i = 0; i < all.count; i++) {
        const char *s = all[i].UTF8String;
        if (s == NULL) {
            free(argv);
            if (error) { *error = SNSpawnMakeError(SNSpawnErrorBadArguments, 0, @"Argument is not UTF-8"); }
            return NO;
        }
        NSData *copy = [NSData dataWithBytes:s length:strlen(s) + 1];
        [storage addObject:copy];
        argv[i] = (char *)copy.bytes;
    }
    argv[all.count] = NULL;
    char *envp[] = { NULL };

    posix_spawnattr_t attr;
    int rc = posix_spawnattr_init(&attr);
    if (rc != 0) {
        free(argv);
        if (error) { *error = SNSpawnMakeError(SNSpawnErrorAttributes, rc, @"posix_spawnattr_init failed"); }
        return NO;
    }
    posix_spawn_file_actions_t actions;
    rc = posix_spawn_file_actions_init(&actions);
    if (rc != 0) {
        posix_spawnattr_destroy(&attr);
        free(argv);
        if (error) { *error = SNSpawnMakeError(SNSpawnErrorFileActions, rc, @"file actions init failed"); }
        return NO;
    }

    BOOL ok = YES;
    SNSpawnErrorCode failCode = SNSpawnErrorAttributes;
    NSString *failWhat = @"";
    int failErrno = 0;

    short flags = POSIX_SPAWN_START_SUSPENDED | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK;
    if (options & SNSpawnOwnProcessGroup) { flags |= POSIX_SPAWN_SETPGROUP; }
    sigset_t all_signals;
    sigfillset(&all_signals);
    sigset_t no_signals;
    sigemptyset(&no_signals);
    if ((rc = posix_spawnattr_setflags(&attr, flags)) != 0 ||
        (rc = posix_spawnattr_setsigdefault(&attr, &all_signals)) != 0 ||
        (rc = posix_spawnattr_setsigmask(&attr, &no_signals)) != 0) {
        ok = NO; failErrno = rc; failWhat = @"spawn attributes failed";
    }
    if (ok && (options & SNSpawnOwnProcessGroup)) {
        if ((rc = posix_spawnattr_setpgroup(&attr, 0)) != 0) { ok = NO; failErrno = rc; failWhat = @"setpgroup failed"; }
    }
    if (ok) {
        // Prefer the architecture this process runs as, so a universal helper matches our
        // code identity (and runs under Rosetta when we do).
#if defined(__arm64__)
        cpu_type_t preferred = CPU_TYPE_ARM64;
#else
        cpu_type_t preferred = CPU_TYPE_X86_64;
#endif
        size_t copied = 0;
        rc = posix_spawnattr_setbinpref_np(&attr, 1, &preferred, &copied);
        if (rc != 0 || copied != 1) { ok = NO; failErrno = rc; failWhat = @"setbinpref failed"; }
    }
    if (ok && (options & SNSpawnDisclaim)) {
        SNDisclaimFn disclaim = SNDisclaim();
        if (disclaim == NULL) {
            ok = NO; failCode = SNSpawnErrorDisclaimUnavailable; failWhat = @"Responsibility disclaim is unavailable";
        } else if ((rc = disclaim(&attr, 1)) != 0) {
            ok = NO; failErrno = rc; failWhat = @"Responsibility disclaim failed";
        }
    }
    if (ok) {
        failCode = SNSpawnErrorFileActions;
        if (stdinFD >= 0) {
            rc = posix_spawn_file_actions_adddup2(&actions, stdinFD, 0);
        } else {
            rc = posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0);
        }
        if (rc == 0) {
            if (stdoutFD >= 0) {
                rc = posix_spawn_file_actions_adddup2(&actions, stdoutFD, 1);
            } else {
                rc = posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0);
            }
        }
        if (rc == 0) { rc = posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0); }
        if (rc != 0) { ok = NO; failErrno = rc; failWhat = @"file actions failed"; }
    }

    pid_t pid = 0;
    if (ok) {
        rc = posix_spawn(&pid, exe, &actions, &attr, argv, envp);
        if (rc != 0) {
            ok = NO; failCode = SNSpawnErrorSpawnFailed; failErrno = rc; failWhat = @"posix_spawn failed";
        }
    }

    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attr);
    free(argv);
    (void)storage;

    if (!ok) {
        if (error) { *error = SNSpawnMakeError(failCode, failErrno, failWhat); }
        return NO;
    }
    *outPID = pid;
    return YES;
}

+ (BOOL)isStopped:(pid_t)pid {
    if (pid <= 0) { return NO; }
    struct proc_bsdinfo info;
    memset(&info, 0, sizeof(info));
    int n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, (int)sizeof(info));
    return n == (int)sizeof(info) && info.pbi_status == SSTOP;
}

+ (pid_t)responsiblePIDForPID:(pid_t)pid {
    SNResponsibleFn fn = SNResponsible();
    if (fn == NULL || pid <= 0) { return -1; }
    return fn(pid);
}

@end
