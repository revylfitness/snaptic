import Darwin
import Foundation
import SnapticKit

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
enum SelfTest {
    static let tokenVariable = "SNAPTIC_SELFTEST_TOKEN"

    static func run(_ arguments: [String]) -> Never {
        switch arguments.dropFirst().first {
        case "--selftest-child": runChild(arguments)
        case "--selftest-helpers": runParent(arguments)
        default: exit(KitArgs.exitUsage)
        }
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
    private static func tokenMatches(file path: String) -> Bool {
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

/// Main-thread-only tallies for the self-test parent.
private final class ReadyCounter {
    var count = 0
    var exits: [Int32] = []
}
