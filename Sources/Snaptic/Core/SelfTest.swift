import Darwin
import Foundation
import SnapticKit
import SnapticShims

/// The helper fd-inheritance self-test (PLAN §14.1, R5.5, R4C §4.3). Built in every
/// configuration and kept out of help texts; it grants nothing.
///
/// `--selftest-helpers <token-file>`: runs only when the environment variable
/// SNAPTIC_SELFTEST_TOKEN equals the contents of `<token-file>` (written by the CI step).
/// Spawns two `--selftest-child` helpers through HelperSpawner, prints
/// `child <pid> <startTime>` for each, then SIGKILLs itself. The CI script asserts that
/// both children exit within 3 s (they see EOF on stdin only if no pipe end leaked).
///
/// `--selftest-child`: a helper that goes through HelperPrologue (signal resets, fd
/// closing, parent identity check) and exits when its stdin reaches EOF.
///
/// `--selftest-controls <token-file>` (0.3 §4.8, token-gated): walks a Switcher `Config` with every optional set and
/// one shortcut, in process, and exits 1 unless every key has a control (a legacy path, a Switcher table key or an
/// internal key) and every legacy path still exists or was removed.
///
/// `--selftest-control-server <token-file>` (0.3 R5-5, token-gated): no modules, only a `ControlServer` with a test
/// registry on SNAPTIC_SELFTEST_SOCKET (under the token file's directory). Prints `held=<n> active=<n>` on every pool
/// change and `closed <reason>` per hold; exits on SIGTERM or after 120 s. Driven by scripts/selftest-control-server.sh.
enum SelfTest {
    static let tokenVariable = "SNAPTIC_SELFTEST_TOKEN"
    /// The CLI client's token-mode override (R5-5): the token file to compare with, and the socket to use.
    static let tokenFileVariable = "SNAPTIC_SELFTEST_TOKEN_FILE"
    static let socketVariable = "SNAPTIC_SELFTEST_SOCKET"

    static func run(_ arguments: [String]) -> Never {
        switch arguments.dropFirst().first {
        case "--selftest-child": runChild(arguments)
        case "--selftest-helpers": runParent(arguments)
        case "--selftest-controls": runControls(arguments)
        case "--selftest-control-server": runControlServer(arguments)
        default: exit(KitArgs.exitUsage)
        }
    }

    // MARK: --selftest-controls

    /// The Switcher's control tables (settings page, sheets and its menu section).
    private static func isSwitcherSurface(_ surface: String) -> Bool {
        surface == "switcher" || surface.hasPrefix("switcher.") || surface == "menu.switcher"
    }

    private static func runControls(_ arguments: [String]) -> Never {
        guard arguments.count == 3, tokenMatches(file: arguments[2]) else { exit(KitArgs.exitUsage) }
        var config = Config()
        // Every optional set, one element in every list (R5-13), so each key path shows up.
        config.shortcuts = [Shortcut()]
        config.gatherShortcut = HotkeyCombo(keyCode: 5, carbonModifiers: 0x0800)
        config.excludedBundleIDs = ["com.example.excluded"]
        config.passthroughBundleIDs = ["com.example.passthrough"]
        config.privateBundleIDs = ["com.example.private"]
        let walked = KitKeyPaths.paths(config)
        let tables = ControlRegistry.tables.filter { isSwitcherSurface($0.surface) }
        let declared = Set(tables.flatMap { $0.controls.flatMap(\.keys) })
        let problems = KitKeyPaths.coverageProblems(walked: walked, legacy: ControlLegacy.switcherKeyPaths,
                                                    declared: declared, internalKeys: ControlLegacy.internalKeys,
                                                    removed: Set(ControlRemovals.removed.keys))
        say("selftest-controls: \(walked.count) paths, \(KitKeyPaths.leaves(walked).count) keys, "
            + "\(tables.count) Switcher tables\n")
        for problem in problems { say("selftest: controls: " + problem + "\n") }
        exit(problems.isEmpty ? 0 : 1)
    }

    // MARK: --selftest-control-server

    /// How long the server lives without a SIGTERM.
    static let controlServerSeconds: Double = 120
    /// A watched pid's exit finishes its hold this much later, so a client's own EOF (kill -9 closes the socket at
    /// the same moment) is reported as `eof`, and only a hold whose fd outlived the process says `pid`.
    static let pidGraceSeconds: Double = 0.2

    private static func runControlServer(_ arguments: [String]) -> Never {
        guard arguments.count == 3, tokenMatches(file: arguments[2]) else { exit(KitArgs.exitUsage) }
        guard let socket = ProcessInfo.processInfo.environment[socketVariable],
              isUnder(directoryOf: arguments[2], socket) else {
            say("selftest: \(socketVariable) must name a socket in the token file's directory\n")
            exit(KitArgs.exitUsage)
        }
        MainActor.assumeIsolated {
            let lifetime = Lifetime()
            let registry = ControlCommandRegistry()
            let watches = HoldWatches()
            registerTestVerbs(registry, watches: watches, lifetime: lifetime)
            let server = ControlServer(registry: registry)
            server.holdPingInterval = 1
            server.onPoolChange = { held, active in say("held=\(held) active=\(active)\n") }
            server.start(socketPath: socket)
            guard case .listening = server.status else {
                say("selftest: control server didn't start: \(server.status)\n")
                exit(1)
            }
            say("listening\n")
            signal(SIGTERM, SIG_IGN)
            let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
            term.setEventHandler {
                MainActor.assumeIsolated {
                    server.stop()
                    exit(0)
                }
            }
            term.resume()
            DispatchQueue.main.asyncAfter(deadline: .now() + controlServerSeconds) {
                MainActor.assumeIsolated {
                    say("selftest: control server timed out after \(Int(controlServerSeconds)) s\n")
                    server.stop()
                    exit(0)
                }
            }
            withExtendedLifetime((lifetime, registry, watches, server, term)) {
                CFRunLoopRun()
            }
        }
        exit(0)
    }

    /// `selftest hold` (a connection hold that also ends when the peer pid exits), `selftest slow` (3 s) and
    /// `selftest echo`.
    @MainActor private static func registerTestVerbs(_ registry: ControlCommandRegistry, watches: HoldWatches,
                                                     lifetime: Lifetime) {
        registry.register("selftest hold", policy: .low, offOnly: false, cliAllowed: true, holds: true,
                          summary: "Self-test hold", lifetime: lifetime) { _, context in
            guard let hold = context.hold else { return .failure(ControlExit.usage, "not a hold") }
            let pid = context.peer.pid
            guard pid > 1, let started = context.peer.startTime else {
                return .failure(ControlExit.refused, L("Snaptic couldn't identify the caller."))
            }
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
            source.setEventHandler { [weak hold] in
                MainActor.assumeIsolated {
                    source.cancel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + pidGraceSeconds) {
                        hold?.finish(.ok("Awake hold ended: the process exited."))
                    }
                }
            }
            source.resume()
            let id = watches.add(source)
            // Armed first, then re-verified (security M4): the same process, still there, and the client still on.
            guard !hold.isClosed, SNProcess.startTime(for: pid) == started else {
                watches.remove(id)
                return .failure(ControlExit.refused, L("Snaptic couldn't identify the caller."))
            }
            // Strong on purpose: the connection may be gone when this runs, and the hold drops its handlers once
            // they ran, so there is no lasting cycle.
            hold.onClose {
                watches.remove(id)
                let reason = hold.closeReason ?? .eof
                say("closed " + (reason == .finished ? "pid" : reason.rawValue) + "\n")
            }
            return .holding("Holding until this command ends. Press Control-C to stop.")
        }
        registry.register("selftest slow", policy: .read, offOnly: false, cliAllowed: true,
                          summary: "Self-test slow request", lifetime: lifetime) { _ in
            try? await Task.sleep(for: .seconds(3))
            return .ok("slow")
        }
        registry.register("selftest echo", policy: .read, offOnly: false, cliAllowed: true,
                          summary: "Self-test echo", lifetime: lifetime) { request in
            .ok(request.arguments.isEmpty ? "echo" : request.arguments.joined(separator: " "))
        }
    }

    /// Whether `path`'s directory is the token file's directory or below it (both resolved, no symlink games).
    private static func isUnder(directoryOf tokenFile: String, _ path: String) -> Bool {
        guard KitControl.isUsableSocketPath(path), !path.split(separator: "/").contains(".."),
              let base = resolved((tokenFile as NSString).deletingLastPathComponent),
              let directory = resolved((path as NSString).deletingLastPathComponent) else { return false }
        return directory == base || directory.hasPrefix(base + "/")
    }

    private static func resolved(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    /// What a child writes once its prologue (fd closing, parent identity check) passed.
    static let readyLine = "ready"
    /// How long the parent waits for both children to report ready.
    static let readySeconds: Double = 5

    private static func runChild(_ arguments: [String]) -> Never {
        _ = HelperPrologue.run(arguments, kind: .selftestChild, onLine: { _ in }, onEOF: { exit(0) })
        // The parent waits for this before it kills itself, so the test proves that a child
        // which passed the real prologue still sees EOF (not that it never started).
        say(readyLine + "\n")
        CFRunLoopRun()
        exit(0)
    }

    private static func runParent(_ arguments: [String]) -> Never {
        guard arguments.count == 3, tokenMatches(file: arguments[2]) else { exit(KitArgs.exitUsage) }
        MainActor.assumeIsolated {
            let spawner = HelperSpawner()
            // Identity and canary run off main, as in the app; the run loop delivers the result.
            spawner.prepare()
            let prepared = Date().addingTimeInterval(readySeconds)
            while !spawner.isReady && spawner.unavailable == nil && Date() < prepared {
                _ = CFRunLoopRunInMode(.defaultMode, 0.05, false)
            }
            guard spawner.isReady else {
                say("helpers unavailable: \(spawner.unavailable ?? "preparation timed out")\n")
                exit(1)
            }
            let ready = ReadyCounter()
            var lines: [String] = []
            for _ in 0..<2 {
                // The spawner verifies each suspended child off main; the run loop delivers
                // the result, as it does in the app.
                let attempt = SpawnAttempt()
                Task { @MainActor in
                    do {
                        attempt.handle = try await spawner.spawn(.selftestChild, arguments: [], onLine: { line in
                            if String(decoding: line, as: UTF8.self) == readyLine { ready.count += 1 }
                        }, onExit: { status in ready.exits.append(status) })
                    } catch {
                        attempt.failure = "\(error)"
                    }
                    attempt.done = true
                }
                let spawned = Date().addingTimeInterval(readySeconds)
                while !attempt.done && Date() < spawned {
                    _ = CFRunLoopRunInMode(.defaultMode, 0.05, false)
                }
                guard let handle = attempt.handle else {
                    say("spawn failed: \(attempt.failure ?? "timed out")\n")
                    exit(1)
                }
                lines.append("child \(handle.pid) \(handle.startTime)\n")
            }
            // Lines arrive on the main queue; the run loop services it.
            let deadline = Date().addingTimeInterval(readySeconds)
            while ready.count < 2 && ready.exits.isEmpty && Date() < deadline {
                _ = CFRunLoopRunInMode(.defaultMode, 0.05, false)
            }
            guard ready.count == 2 else {
                say("children not ready: \(ready.count) ready, exits \(ready.exits)\n")
                exit(1)
            }
            for line in lines { say(line) }
            // No cleanup on purpose: the children must notice our death by themselves.
            kill(getpid(), SIGKILL)
        }
        exit(1)
    }

    /// Constant-time compare of the environment token with the file's contents.
    static func tokenMatches(file path: String) -> Bool {
        guard let expected = ProcessInfo.processInfo.environment[tokenVariable], expected.utf8.count >= 16 else {
            return false
        }
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid(), info.st_size <= 256 else {
            return false
        }
        var buffer = [UInt8](repeating: 0, count: 256)
        let n = buffer.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress, raw.count) }
        guard n > 0 else { return false }
        var stored = Array(buffer[0..<n])
        while let last = stored.last, last == 0x0A || last == 0x0D || last == 0x20 { stored.removeLast() }
        let wanted = Array(expected.utf8)
        guard stored.count == wanted.count else { return false }
        var difference: UInt8 = 0
        for i in 0..<wanted.count { difference |= stored[i] ^ wanted[i] }
        return difference == 0
    }

    /// Unbuffered stdout (print is reserved for the CLI client).
    private static func say(_ text: String) {
        text.withCString { pointer in _ = write(STDOUT_FILENO, pointer, strlen(pointer)) }
    }
}

/// One spawn's result for the self-test parent (main thread only).
private final class SpawnAttempt {
    var handle: HelperHandle?
    var failure: String?
    var done = false
}

/// The control-server self-test's process watches, by hold (main thread only).
@MainActor private final class HoldWatches {
    private var sources: [UInt64: DispatchSourceProcess] = [:]
    private var next: UInt64 = 0

    func add(_ source: DispatchSourceProcess) -> UInt64 {
        next &+= 1
        sources[next] = source
        return next
    }

    func remove(_ id: UInt64) {
        sources.removeValue(forKey: id)?.cancel()
    }
}

/// Main-thread-only tallies for the self-test parent.
private final class ReadyCounter {
    var count = 0
    var exits: [Int32] = []
}
