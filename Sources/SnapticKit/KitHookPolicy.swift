import Foundation

/// What `lstat` said about one component of an executable's path.
package struct PathComponentInfo: Equatable, Sendable {
    package var path: String
    package var exists: Bool
    package var isDirectory: Bool
    package var isRegularFile: Bool
    package var isSymlink: Bool
    package var owner: UInt32
    /// Permission bits (`st_mode & 0o7777`).
    package var mode: UInt32

    package init(path: String, exists: Bool = true, isDirectory: Bool = false, isRegularFile: Bool = false,
                 isSymlink: Bool = false, owner: UInt32 = 0, mode: UInt32 = 0o755) {
        self.path = path
        self.exists = exists
        self.isDirectory = isDirectory
        self.isRegularFile = isRegularFile
        self.isSymlink = isSymlink
        self.owner = owner
        self.mode = mode
    }
}

/// Why a hook or custom action won't run (PLAN §4.10(1)).
package enum HookRefusal: Error, Equatable, Sendable {
    case notAbsolute
    case tooLong
    case badCharacters
    case dotComponent
    case missing(String)
    case symlink(String)
    case badOwner(String)
    case writableByOthers(String)
    case notDirectory(String)
    case notRegularFile
    case notExecutable
    case insideSnaptic
    case snapticIdentity
    /// The code signature (ours or the started program's) couldn't be read: fail closed.
    case identityUnreadable
    case tooManyArguments
    case argumentTooLong

    package var message: String {
        switch self {
        case .notAbsolute: return L("Use the full path, starting with /.")
        case .tooLong: return L("The path is too long.")
        case .badCharacters: return L("The path contains characters Snaptic doesn’t accept.")
        case .dotComponent: return L("The path may not contain . or .. parts.")
        case .missing(let p): return L("Doesn’t exist: ") + p
        case .symlink(let p): return L("Is a symbolic link (use the real path): ") + p
        case .badOwner(let p): return L("Must be owned by you or by the system: ") + p
        case .writableByOthers(let p): return L("Other users or groups can change it: ") + p
        case .notDirectory(let p): return L("Isn’t a folder: ") + p
        case .notRegularFile: return L("Isn’t a regular file.")
        case .notExecutable: return L("Isn’t executable (chmod +x).")
        case .insideSnaptic: return L("Snaptic’s own files can’t be run as hooks or actions.")
        case .snapticIdentity: return L("Programs signed as Snaptic can’t be run as hooks or actions.")
        case .identityUnreadable: return L("Snaptic couldn’t check the program’s code signature, so it didn’t run it.")
        case .tooManyArguments: return L("At most 8 arguments.")
        case .argumentTooLong: return L("An argument is too long.")
        }
    }
}

/// Rules for running user-chosen executables (PLAN §4.10(1), R3C §5.3).
package enum KitHookPolicy {
    package static let maxPathBytes = 1024
    package static let maxArguments = 8
    package static let maxArgumentScalars = 256
    package static let timeoutSeconds: Double = 30
    /// SIGTERM, then SIGKILL after this long.
    package static let killGraceSeconds: Double = 2
    /// One run per hook and event per this many seconds.
    package static let throttleSeconds: Double = 10
    package static let searchPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// Syntax only (no file system access).
    package static func checkSyntax(_ path: String) -> HookRefusal? {
        guard path.hasPrefix("/") else { return .notAbsolute }
        guard path.utf8.count <= maxPathBytes else { return .tooLong }
        guard !path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return .badCharacters }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return .notRegularFile }
        if parts.contains(where: { $0 == "." || $0 == ".." }) { return .dotComponent }
        return nil
    }

    /// "/", "/a", "/a/b", … "/a/b/tool": every path to lstat, root first.
    package static func components(of path: String) -> [String] {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var result = ["/"]
        var current = ""
        for part in parts {
            current += "/" + part
            result.append(current)
        }
        return result
    }

    /// Every component: exists, no symlink, owned by the user or root, not writable by
    /// group or others; directories all the way down and a regular executable at the end.
    package static func check(_ components: [PathComponentInfo], userID: UInt32) -> HookRefusal? {
        guard let last = components.last else { return .notRegularFile }
        for (index, info) in components.enumerated() {
            guard info.exists else { return .missing(info.path) }
            if info.isSymlink { return .symlink(info.path) }
            if info.owner != userID && info.owner != 0 { return .badOwner(info.path) }
            if info.mode & 0o022 != 0 { return .writableByOthers(info.path) }
            if index < components.count - 1 && !info.isDirectory { return .notDirectory(info.path) }
        }
        guard last.isRegularFile else { return .notRegularFile }
        guard last.mode & 0o111 != 0 else { return .notExecutable }
        return nil
    }

    package static func checkArguments(_ arguments: [String]) -> HookRefusal? {
        guard arguments.count <= maxArguments else { return .tooManyArguments }
        for argument in arguments where argument.unicodeScalars.count > maxArgumentScalars || argument.utf8.contains(0) {
            return .argumentTooLong
        }
        return nil
    }

    /// Inside Snaptic's bundle (or the bundle itself).
    package static func isInside(_ path: String, bundle: String) -> Bool {
        guard !bundle.isEmpty else { return false }
        let base = bundle.hasSuffix("/") ? String(bundle.dropLast()) : bundle
        return path == base || path.hasPrefix(base + "/")
    }

    /// `isInside` for paths that went through realpath, compared the way the default
    /// (case- and normalization-insensitive) APFS volume does: "/applications/SNAPTIC.app/…"
    /// is inside "/Applications/Snaptic.app". Repeated slashes are ignored.
    package static func isInsideFolded(_ path: String, bundle: String) -> Bool {
        let b = folded(bundle)
        guard !b.isEmpty, b != "/" else { return false }
        return isInside(folded(path), bundle: b)
    }

    /// Lowercased, NFC, with runs of "/" collapsed and no trailing "/".
    package static func folded(_ path: String) -> String {
        let lowered = path.precomposedStringWithCanonicalMapping.lowercased()
        var out = ""
        var lastSlash = false
        for ch in lowered {
            if ch == "/" {
                if lastSlash { continue }
                lastSlash = true
            } else {
                lastSlash = false
            }
            out.append(ch)
        }
        if out.count > 1 && out.hasSuffix("/") { out.removeLast() }
        return out
    }

    /// The whole environment a hook gets: a fixed PATH and the event facts. Nothing
    /// TCC-derived (titles, app names, pixels) is ever passed (PLAN §4.10(2)).
    package static func environment(event: HookEvent, displayName: String?, displayKey: DisplayKey?) -> [String: String] {
        var env = ["PATH": searchPath, "SNAPTIC_EVENT": event.rawValue]
        if let displayName {
            let cleaned = TextSanitizer.clean(displayName, maxScalars: 64)
            if !cleaned.isEmpty { env["SNAPTIC_DISPLAY_NAME"] = cleaned }
        }
        if let displayKey { env["SNAPTIC_DISPLAY_KEY"] = displayKey.rawValue }
        return env
    }

    /// `NAME=value` strings in a stable order (the spawned process's environment).
    package static func environmentList(_ env: [String: String]) -> [String] {
        env.keys.sorted().map { $0 + "=" + (env[$0] ?? "") }
    }
}

/// One run per key (hook + event) per `KitHookPolicy.throttleSeconds`.
package struct HookThrottle: Sendable {
    private var lastRun: [String: Double] = [:]
    package let interval: Double

    package init(interval: Double = KitHookPolicy.throttleSeconds) { self.interval = interval }

    package mutating func allow(_ key: String, now: Double) -> Bool {
        if let last = lastRun[key], now >= last, now - last < interval { return false }
        lastRun[key] = now
        if lastRun.count > 256 { lastRun = lastRun.filter { now - $0.value < interval } }
        return true
    }
}
