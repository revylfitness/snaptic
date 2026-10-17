import AppKit
import SnapticKit
import SnapticShims

/// Process entry point (PLAN §3.2). Helper modes (display guard, virtual display host,
/// self-test, command-line client) are dispatched before AppKit starts and skip the app
/// self-checks; app mode validates its arguments and environment first.
enum SnapticEntry {
    static func run(_ arguments: [String]) {
        // Startup step 1: a reader that went away must never kill Snaptic.
        signal(SIGPIPE, SIG_IGN)

        switch KitArgs.mode(arguments: arguments) {
        case .displayGuard: DisplayGuardMain.run(arguments)
        case .virtualHost: VirtualHostMain.run(arguments)
        case .selftestHelpers, .selftestChild: SelfTest.run(arguments)
        case .cli: CLIClient.run(arguments)
        case .app: break
        }

        // Toolchain self-check: exercises cross-module `package` access and the
        // Objective-C shim in every build configuration and architecture.
        _ = KitProbe.selfCheck()
        _ = SNEncoding.normalizedEncoding("c24@0:8@16")

        // Startup step 2: argument and environment validation (R5.7).
        let options: AppLaunchOptions
        switch KitArgs.parseApp(Array(arguments.dropFirst())) {
        case .success(let parsed): options = parsed
        case .failure(let error): refuse(error.message)
        }
        let environment = ProcessInfo.processInfo.environment
        let denied = KitArgs.deniedEnvironmentVariables(environment)
        if !denied.isEmpty {
            let names = denied.prefix(8).map { TextSanitizer.clean($0, maxScalars: 64) }.joined(separator: ", ")
            refuse(L("Snaptic doesn't start with these environment variables set: ") + names)
        }
        guard let home = AccountPaths.home else { refuse(L("Snaptic couldn't look up your account's home folder.")) }
        guard KitArgs.homeMatches(environmentHome: environment["HOME"], accountHome: home) else {
            refuse(L("HOME doesn't match your account's home folder, so Snaptic won't start."))
        }
        redirectStandardStreams()

        // Snaptic runs as a menu-bar ("accessory") app: no Dock icon, no main window.
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate(launch: options)
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
            withExtendedLifetime(delegate) {}
        }
    }

    /// Explains on stderr (before it is redirected) and exits 64.
    static func refuse(_ message: String) -> Never {
        let line = "Snaptic: " + message + "\n"
        line.withCString { pointer in _ = Darwin.write(2, pointer, strlen(pointer)) }
        exit(KitArgs.exitUsage)
    }

    /// stdout and stderr go to /dev/null in app mode (R5.7): nothing Snaptic or a
    /// framework prints can leak to whoever launched it.
    private static func redirectStandardStreams() {
        let fd = open("/dev/null", O_WRONLY | O_CLOEXEC)
        guard fd >= 0 else { return }
        _ = dup2(fd, STDOUT_FILENO)
        _ = dup2(fd, STDERR_FILENO)
        if fd > STDERR_FILENO { close(fd) }
    }
}

/// Paths derived from the account database, never from HOME (PLAN §3.2).
enum AccountPaths {
    /// The account's home folder from getpwuid_r, or nil.
    static var home: String? {
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var size = sysconf(Int32(_SC_GETPW_R_SIZE_MAX))
        if size <= 0 || size > 1 << 20 { size = 16_384 }
        var buffer = [CChar](repeating: 0, count: size)
        let capacity = buffer.count
        let status = getpwuid_r(getuid(), &record, &buffer, capacity, &result)
        guard status == 0, result != nil, let directory = record.pw_dir else { return nil }
        let path = String(cString: directory)
        return path.hasPrefix("/") ? path : nil
    }

    /// ~/Library/Application Support/Snaptic, created 0700 if missing.
    static func supportDirectory() -> String? {
        guard let home else { return nil }
        let path = home + "/Library/Application Support/Snaptic"
        var info = stat()
        if lstat(path, &info) != 0 {
            guard mkdir(path, 0o700) == 0 || errno == EEXIST else { return nil }
            guard lstat(path, &info) == 0 else { return nil }
        }
        // Never a symlink planted by someone else; only our own directory.
        guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { return nil }
        return path
    }
}
