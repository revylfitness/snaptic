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

    private static func runChild(_ arguments: [String]) -> Never {
        _ = HelperPrologue.run(arguments, kind: .selftestChild, onLine: { _ in }, onEOF: { exit(0) })
        CFRunLoopRun()
        exit(0)
    }

    private static func runParent(_ arguments: [String]) -> Never {
        guard arguments.count == 3, tokenMatches(file: arguments[2]) else { exit(KitArgs.exitUsage) }
        MainActor.assumeIsolated {
            let spawner = HelperSpawner()
            var lines: [String] = []
            for _ in 0..<2 {
                guard let handle = try? spawner.spawn(.selftestChild, arguments: [], onLine: { _ in }, onExit: { _ in }) else {
                    say("spawn failed\n")
                    exit(1)
                }
                lines.append("child \(handle.pid) \(handle.startTime)\n")
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
