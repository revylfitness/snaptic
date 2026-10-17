import Foundation

/// How the process was started (PLAN §3.2). Decided from argv[1] and argv[0] only, before
/// any app self-check runs.
package enum LaunchMode: Equatable, Sendable {
    case displayGuard
    case virtualHost
    case cli
    case selftestHelpers
    case selftestChild
    case app
}

/// What app mode accepts on its command line (R5.7).
package struct AppLaunchOptions: Equatable, Sendable {
    /// `--safe-mode`.
    package var safeMode: Bool
    /// `--relaunch-from <pid>`: only lengthens the instance-lock wait; grants nothing.
    package var relaunchFrom: Int32?

    package init(safeMode: Bool = false, relaunchFrom: Int32? = nil) {
        self.safeMode = safeMode
        self.relaunchFrom = relaunchFrom
    }
}

package enum AppArgumentError: Error, Equatable, Sendable {
    case unknownArgument(String)
    case missingValue(String)
    case invalidPID(String)
    case duplicate(String)

    /// A one-line explanation. Echoed input is cleaned and shortened.
    package var message: String {
        switch self {
        case .unknownArgument(let a): return L("Unknown argument: ") + KitArgs.echo(a)
        case .missingValue(let a): return L("Missing value after ") + KitArgs.echo(a)
        case .invalidPID(let a): return L("Not a process id: ") + KitArgs.echo(a)
        case .duplicate(let a): return L("Argument given twice: ") + KitArgs.echo(a)
        }
    }
}

/// App-mode argument and environment validation (PLAN §3.2, R5.7).
package enum KitArgs {
    /// Exit status for a refused command line or environment (EX_USAGE).
    package static let exitUsage: Int32 = 64

    package static let safeModeFlag = "--safe-mode"
    package static let relaunchFlag = "--relaunch-from"

    /// Environment variables with these prefixes change how Foundation, the Objective-C
    /// runtime, malloc, libdispatch, Swift or dyld behave, so app mode refuses them.
    package static let deniedEnvironmentPrefixes = [
        "CF", "NS", "OS_ACTIVITY", "OBJC_", "Malloc", "LIBDISPATCH", "SWIFT_", "DYLD",
    ]
    package static let deniedEnvironmentNames: Set<String> = ["CFFIXED_USER_HOME"]

    /// The mode for a full argv (argv[0] included).
    package static func mode(arguments: [String]) -> LaunchMode {
        if arguments.count > 1 {
            switch arguments[1] {
            case "--display-guard": return .displayGuard
            case "--virtual-host": return .virtualHost
            case "--selftest-helpers": return .selftestHelpers
            case "--selftest-child": return .selftestChild
            case "cli": return .cli
            default: break
            }
        }
        if let argv0 = arguments.first, lastPathComponent(argv0) == "snaptic" { return .cli }
        return .app
    }

    /// Parses app-mode arguments (argv without argv[0]). Allowed: exactly `--safe-mode`,
    /// `--relaunch-from <pid>` and LaunchServices' `-psn_*`. Everything else is refused,
    /// including `-NS*` / `-Apple*` defaults overrides.
    package static func parseApp(_ arguments: [String]) -> Result<AppLaunchOptions, AppArgumentError> {
        var options = AppLaunchOptions()
        var sawSafeMode = false
        var sawPSN = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case safeModeFlag:
                if sawSafeMode { return .failure(.duplicate(argument)) }
                sawSafeMode = true
                options.safeMode = true
            case relaunchFlag:
                if options.relaunchFrom != nil { return .failure(.duplicate(argument)) }
                guard index + 1 < arguments.count else { return .failure(.missingValue(argument)) }
                let value = arguments[index + 1]
                guard let pid = parsePID(value) else { return .failure(.invalidPID(value)) }
                options.relaunchFrom = pid
                index += 1
            default:
                guard isProcessSerialNumber(argument) else { return .failure(.unknownArgument(argument)) }
                if sawPSN { return .failure(.duplicate(argument)) }
                sawPSN = true
            }
            index += 1
        }
        return .success(options)
    }

    /// A positive decimal process id that fits pid_t; no sign, no spaces.
    package static func parsePID(_ text: String) -> Int32? {
        guard !text.isEmpty, text.utf8.count <= 10, text.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
              let value = Int32(text), value > 0 else { return nil }
        return value
    }

    /// LaunchServices' process serial number argument: `-psn_<digits>_<digits>`.
    package static func isProcessSerialNumber(_ argument: String) -> Bool {
        guard argument.hasPrefix("-psn_"), argument.utf8.count <= 64 else { return false }
        let rest = argument.utf8.dropFirst(5)
        guard !rest.isEmpty else { return false }
        return rest.allSatisfy { (0x30...0x39).contains($0) || $0 == 0x5F }
    }

    /// Names of refused environment variables, sorted (empty when the environment is fine).
    package static func deniedEnvironmentVariables(_ environment: [String: String]) -> [String] {
        environment.keys.filter { name in
            deniedEnvironmentNames.contains(name) || deniedEnvironmentPrefixes.contains { name.hasPrefix($0) }
        }.sorted()
    }

    /// HOME must name the account's home directory (from getpwuid_r). An unset HOME is
    /// fine: Foundation then falls back to the account database itself.
    package static func homeMatches(environmentHome: String?, accountHome: String) -> Bool {
        guard let home = environmentHome else { return true }
        guard !accountHome.isEmpty else { return false }
        return trimmingTrailingSlashes(home) == trimmingTrailingSlashes(accountHome)
    }

    /// App Translocation runs a quarantined app from a random read-only path; grants
    /// given there don't stick, so the user is told to move the app first (PLAN §1.1).
    package static func isTranslocated(_ path: String) -> Bool {
        path.hasPrefix("/private/var/folders/") && path.contains("/AppTranslocation/")
    }

    // MARK: Helpers

    package static func lastPathComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }

    static func trimmingTrailingSlashes(_ path: String) -> String {
        var result = path
        while result.count > 1 && result.hasSuffix("/") { result.removeLast() }
        return result
    }

    static func echo(_ text: String) -> String {
        let cleaned = TextSanitizer.clean(text, maxScalars: 64)
        return cleaned.isEmpty ? "\"\"" : cleaned
    }
}
