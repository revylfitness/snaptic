#import "SNProcess.h"

#if !__has_feature(objc_arc)
#error "SnapticShims requires ARC"
#endif

#import <Security/Security.h>
#import <libproc.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <stdlib.h>
#import <string.h>
#import <sys/proc_info.h>
#import <sys/sysctl.h>

@implementation SNProcess

+ (BOOL)isAvailable { return YES; }

+ (nullable NSString *)pathForPID:(pid_t)pid {
    if (pid <= 0) { return nil; }
    char buffer[PROC_PIDPATHINFO_MAXSIZE];
    memset(buffer, 0, sizeof(buffer));
    int n = proc_pidpath(pid, buffer, (uint32_t)sizeof(buffer));
    if (n <= 0) { return nil; }
    return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:buffer length:(NSUInteger)n];
}

+ (uint64_t)startTimeForPID:(pid_t)pid {
    if (pid <= 0) { return 0; }
    struct proc_bsdinfo info;
    memset(&info, 0, sizeof(info));
    int n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, (int)sizeof(info));
    if (n != (int)sizeof(info)) { return 0; }
    return (uint64_t)info.pbi_start_tvsec * 1000000ULL + (uint64_t)info.pbi_start_tvusec;
}

+ (uint64_t)instanceIDForPID:(pid_t)pid {
    if (pid <= 0) { return 0; }
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    struct kinfo_proc info;
    memset(&info, 0, sizeof(info));
    size_t size = sizeof(info);
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0 || size != sizeof(info)) { return 0; }
    if (info.kp_proc.p_pid != pid) { return 0; }
    struct timeval start = info.kp_proc.p_starttime;
    return (uint64_t)start.tv_sec * 1000000ULL + (uint64_t)start.tv_usec;
}

+ (nullable NSArray<NSNumber *> *)openFileDescriptors {
    pid_t pid = getpid();
    int size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (size <= 0) { return nil; }
    // Room for descriptors opened between the two calls.
    size_t capacity = (size_t)size + 32 * sizeof(struct proc_fdinfo);
    struct proc_fdinfo *fds = malloc(capacity);
    if (fds == NULL) { return nil; }
    int used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, (int)capacity);
    if (used <= 0) { free(fds); return nil; }
    int count = used / (int)sizeof(struct proc_fdinfo);
    NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (int i = 0; i < count; i++) { [result addObject:@(fds[i].proc_fd)]; }
    free(fds);
    return result;
}

static NSError *SNProcessError(OSStatus status, NSString *what) {
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:status
                           userInfo:@{NSLocalizedDescriptionKey: what}];
}

+ (nullable NSData *)designatedRequirementOfSelfWithError:(NSError **)error {
    SecCodeRef me = NULL;
    OSStatus status = SecCodeCopySelf(kSecCSDefaultFlags, &me);
    if (status != errSecSuccess || me == NULL) {
        if (error) { *error = SNProcessError(status, @"SecCodeCopySelf failed"); }
        return nil;
    }
    SecStaticCodeRef staticCode = NULL;
    status = SecCodeCopyStaticCode(me, kSecCSDefaultFlags, &staticCode);
    CFRelease(me);
    if (status != errSecSuccess || staticCode == NULL) {
        if (error) { *error = SNProcessError(status, @"SecCodeCopyStaticCode failed"); }
        return nil;
    }
    SecRequirementRef requirement = NULL;
    status = SecCodeCopyDesignatedRequirement(staticCode, kSecCSDefaultFlags, &requirement);
    CFRelease(staticCode);
    if (status != errSecSuccess || requirement == NULL) {
        if (error) { *error = SNProcessError(status, @"No designated requirement"); }
        return nil;
    }
    CFDataRef data = NULL;
    status = SecRequirementCopyData(requirement, kSecCSDefaultFlags, &data);
    CFRelease(requirement);
    if (status != errSecSuccess || data == NULL) {
        if (error) { *error = SNProcessError(status, @"SecRequirementCopyData failed"); }
        return nil;
    }
    return (NSData *)CFBridgingRelease(data);
}

+ (BOOL)processWithPID:(pid_t)pid satisfiesRequirement:(NSData *)requirementData {
    if (pid <= 0 || requirementData.length == 0) { return NO; }
    SecRequirementRef requirement = NULL;
    if (SecRequirementCreateWithData((__bridge CFDataRef)requirementData, kSecCSDefaultFlags, &requirement) != errSecSuccess
        || requirement == NULL) {
        return NO;
    }
    NSDictionary *attributes = @{(__bridge NSString *)kSecGuestAttributePid: @(pid)};
    SecCodeRef guest = NULL;
    OSStatus status = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)attributes, kSecCSDefaultFlags, &guest);
    BOOL ok = NO;
    if (status == errSecSuccess && guest != NULL) {
        ok = SecCodeCheckValidity(guest, kSecCSDefaultFlags, requirement) == errSecSuccess;
    }
    if (guest != NULL) { CFRelease(guest); }
    CFRelease(requirement);
    return ok;
}

+ (NSString *)signerDescriptionOfSelf {
    SecCodeRef me = NULL;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &me) != errSecSuccess || me == NULL) { return @"unsigned"; }
    SecStaticCodeRef staticCode = NULL;
    OSStatus status = SecCodeCopyStaticCode(me, kSecCSDefaultFlags, &staticCode);
    CFRelease(me);
    if (status != errSecSuccess || staticCode == NULL) { return @"unsigned"; }
    CFDictionaryRef infoRef = NULL;
    status = SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &infoRef);
    CFRelease(staticCode);
    if (status != errSecSuccess || infoRef == NULL) { return @"unsigned"; }
    NSDictionary *info = (NSDictionary *)CFBridgingRelease(infoRef);

    NSNumber *flags = info[(__bridge NSString *)kSecCodeInfoFlags];
    if ([flags isKindOfClass:[NSNumber class]] && (flags.unsignedIntValue & kSecCodeSignatureAdhoc) != 0) {
        return @"ad-hoc";
    }
    NSArray *certificates = info[(__bridge NSString *)kSecCodeInfoCertificates];
    if ([certificates isKindOfClass:[NSArray class]] && certificates.count > 0) {
        SecCertificateRef leaf = (__bridge SecCertificateRef)certificates[0];
        if (CFGetTypeID(leaf) == SecCertificateGetTypeID()) {
            CFStringRef summary = SecCertificateCopySubjectSummary(leaf);
            if (summary != NULL) { return (NSString *)CFBridgingRelease(summary); }
        }
    }
    if (info[(__bridge NSString *)kSecCodeInfoIdentifier] != nil) { return @"ad-hoc"; }
    return @"unsigned";
}

static NSString *SNIdentifierOfStaticCode(SecStaticCodeRef staticCode) {
    CFDictionaryRef infoRef = NULL;
    if (SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &infoRef) != errSecSuccess || infoRef == NULL) {
        return nil;
    }
    NSDictionary *info = (NSDictionary *)CFBridgingRelease(infoRef);
    id identifier = info[(__bridge NSString *)kSecCodeInfoIdentifier];
    return [identifier isKindOfClass:[NSString class]] ? identifier : nil;
}

+ (nullable NSString *)signingIdentifierForPath:(NSString *)path {
    if (path.length == 0) { return nil; }
    NSURL *url = [NSURL fileURLWithPath:path];
    SecStaticCodeRef staticCode = NULL;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &staticCode) != errSecSuccess
        || staticCode == NULL) {
        return nil;
    }
    NSString *identifier = SNIdentifierOfStaticCode(staticCode);
    CFRelease(staticCode);
    return identifier;
}

+ (nullable NSString *)signingIdentifierForPID:(pid_t)pid error:(NSError **)error {
    if (pid <= 0) {
        if (error) { *error = SNProcessError(errSecParam, @"Bad pid"); }
        return nil;
    }
    NSDictionary *attributes = @{(__bridge NSString *)kSecGuestAttributePid: @(pid)};
    SecCodeRef guest = NULL;
    OSStatus status = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)attributes, kSecCSDefaultFlags, &guest);
    if (status != errSecSuccess || guest == NULL) {
        if (guest != NULL) { CFRelease(guest); }
        if (error) { *error = SNProcessError(status, @"SecCodeCopyGuestWithAttributes failed"); }
        return nil;
    }
    CFDictionaryRef infoRef = NULL;
    status = SecCodeCopySigningInformation(guest, kSecCSSigningInformation, &infoRef);
    CFRelease(guest);
    if (status != errSecSuccess || infoRef == NULL) {
        if (error) { *error = SNProcessError(status, @"SecCodeCopySigningInformation failed"); }
        return nil;
    }
    NSDictionary *info = (NSDictionary *)CFBridgingRelease(infoRef);
    id identifier = info[(__bridge NSString *)kSecCodeInfoIdentifier];
    return [identifier isKindOfClass:[NSString class]] ? identifier : @"";
}

+ (nullable NSString *)signingIdentifierOfSelf {
    SecCodeRef me = NULL;
    if (SecCodeCopySelf(kSecCSDefaultFlags, &me) != errSecSuccess || me == NULL) { return nil; }
    SecStaticCodeRef staticCode = NULL;
    OSStatus status = SecCodeCopyStaticCode(me, kSecCSDefaultFlags, &staticCode);
    CFRelease(me);
    if (status != errSecSuccess || staticCode == NULL) { return nil; }
    NSString *identifier = SNIdentifierOfStaticCode(staticCode);
    CFRelease(staticCode);
    return identifier;
}

+ (nullable NSString *)executableUUID {
    const struct mach_header *header = _dyld_get_image_header(0);
    if (header == NULL || header->magic != MH_MAGIC_64) { return nil; }
    const uint8_t *cursor = (const uint8_t *)header + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        const struct load_command *command = (const struct load_command *)cursor;
        if (command->cmdsize < sizeof(struct load_command)) { return nil; }
        if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uuidCommand = (const struct uuid_command *)cursor;
            NSUUID *uuid = [[NSUUID alloc] initWithUUIDBytes:uuidCommand->uuid];
            return uuid.UUIDString;
        }
        cursor += command->cmdsize;
    }
    return nil;
}

@end
