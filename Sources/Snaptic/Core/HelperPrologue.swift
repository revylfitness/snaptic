import Darwin
import Foundation
import SnapticKit
import SnapticShims

/// What a helper learns from its command line (passed by HelperSpawner, a trusted parent).
struct HelperArgs: Equatable {
    let parent: pid_t
    let build: String
    let protocolVersion: Int?
    let journalDir: String?
    /// Arguments after the standard ones, for the helper's own use.
    let extra: [String]
}

/// Helper-side entry hardening (R5.1, R4C §4.1), shared by the display guard, virtual
/// hosts and the self-test child. Never touches AppKit, UserDefaults or TCC.
enum HelperPrologue {
    static let exitBadParent: Int32 = 64
    static let exitProtocolMismatch: Int32 = 65

    /// 1. SIGPIPE ignored, TERM/INT/HUP back to default; 2. every fd ≥ 3 closed except
    /// `--keep-fd` ones; 3. arguments parsed; 4. the parent checked (pid and code
    /// identity); 5. stdin read through a read source, lines delivered on main. EOF on
    /// stdin means the parent died: `onEOF` runs on main (default: exit 0).
    /// Exits 64 on bad arguments or a parent that fails the check. Returns on success;
    /// the caller then runs `CFRunLoopRun()`.
    static func run(_ arguments: [String], kind: HelperKind, onLine: @escaping (Data) -> Void,
                    onEOF: @escaping () -> Void = { exit(0) }) -> HelperArgs {
        signal(SIGPIPE, SIG_IGN)
        for sig in [SIGTERM, SIGINT, SIGHUP] { signal(sig, SIG_DFL) }

        guard let parsed = parse(Array(arguments.dropFirst(2))) else { exit(exitBadParent) }
        closeInheritedDescriptors(keeping: parsed.keep)
        guard checkParent(parsed.args.parent, requirement: parsed.requirement) else { exit(exitBadParent) }
        startReading(onLine: onLine, onEOF: onEOF)
        return parsed.args
    }

    /// Exits 65 unless the parent speaks `version`.
    static func requireProtocol(_ args: HelperArgs, _ version: Int) {
        if args.protocolVersion != version { exit(exitProtocolMismatch) }
    }

    // MARK: Steps

    private struct Parsed {
        let args: HelperArgs
        let requirement: Data
        let keep: Set<Int32>
    }

    /// Standard options in any order; unknown `--x` options and values go to `extra`.
    private static func parse(_ argv: [String]) -> Parsed? {
        var parent: pid_t?
        var build: String?
        var requirement: Data?
        var protocolVersion: Int?
        var journalDir: String?
        var keep = Set<Int32>()
        var extra: [String] = []
        var i = 0
        func value() -> String? {
            guard i + 1 < argv.count else { return nil }
            i += 1
            return argv[i]
        }
        while i < argv.count {
            switch argv[i] {
            case "--parent":
                guard let v = value(), let pid = KitArgs.parsePID(v) else { return nil }
                parent = pid
            case "--build":
                guard let v = value(), !v.isEmpty, v.utf8.count <= 64 else { return nil }
                build = v
            case "--requirement":
                guard let v = value(), v.utf8.count <= 16_384, let data = Data(base64Encoded: v), !data.isEmpty else {
                    return nil
                }
                requirement = data
            case "--protocol":
                guard let v = value(), let n = Int(v), n >= 0, n < 1_000_000 else { return nil }
                protocolVersion = n
            case "--journal-dir":
                guard let v = value(), v.hasPrefix("/"), v.utf8.count <= 1024 else { return nil }
                journalDir = v
            case "--keep-fd":
                guard let v = value(), let n = Int32(v), n >= 3, n < 4096 else { return nil }
                keep.insert(n)
            default:
                extra.append(argv[i])
            }
            i += 1
        }
        guard let parent, let build, let requirement else { return nil }
        return Parsed(args: HelperArgs(parent: parent, build: build, protocolVersion: protocolVersion,
                                       journalDir: journalDir, extra: extra),
                      requirement: requirement, keep: keep)
    }

    /// Nothing a parent leaked (another helper's pipe end, a socket) may stay open, or
    /// parent death would never reach the sibling as EOF (R3C §5.1).
    private static func closeInheritedDescriptors(keeping keep: Set<Int32>) {
        var closed = 0
        if let open = SNProcess.openFileDescriptors() {
            for number in open {
                let fd = number.int32Value
                guard fd >= 3, !keep.contains(fd) else { continue }
                if close(fd) == 0 { closed += 1 }
            }
        } else {
            let limit = min(getdtablesize(), 4096)
            var fd: Int32 = 3
            while fd < limit {
                if !keep.contains(fd), fcntl(fd, F_GETFD) != -1, close(fd) == 0 { closed += 1 }
                fd += 1
            }
        }
        _ = closed
    }

    /// The parent must be our real parent and satisfy our own designated requirement as
    /// passed by it. Re-checked after the identity check: reparenting to launchd (the
    /// parent died and its pid got reused) closes the race.
    private static func checkParent(_ parent: pid_t, requirement: Data) -> Bool {
        guard getppid() == parent else { return false }
        guard SNProcess.process(parent, satisfies: requirement) else { return false }
        return getppid() == parent
    }

    private static func startReading(onLine: @escaping (Data) -> Void, onEOF: @escaping () -> Void) {
        let flags = fcntl(0, F_GETFL)
        if flags >= 0 { _ = fcntl(0, F_SETFL, flags | O_NONBLOCK) }
        let state = StdinState()
        let source = DispatchSource.makeReadSource(fileDescriptor: 0, queue: DispatchQueue(label: "app.snaptic.helper-stdin"))
        source.setEventHandler {
            switch state.drain() {
            case .lines(let lines):
                for line in lines { DispatchQueue.main.async { onLine(line) } }
            case .wouldBlock:
                break
            case .finished:
                source.cancel()
                DispatchQueue.main.async { onEOF() }
            }
        }
        state.source = source
        source.resume()
    }
}

/// Owns the stdin splitter and keeps the read source alive for the helper's lifetime.
private final class StdinState: @unchecked Sendable {
    enum Outcome { case lines([Data]), wouldBlock, finished }

    var source: DispatchSourceRead?
    private var splitter = LineSplitter()

    func drain() -> Outcome {
        var buffer = [UInt8](repeating: 0, count: 16_384)
        let n = buffer.withUnsafeMutableBytes { raw in read(0, raw.baseAddress, raw.count) }
        if n < 0 && (errno == EINTR || errno == EAGAIN) { return .wouldBlock }
        // EOF, an error or an oversized line all end the conversation with the parent.
        guard n > 0, let lines = splitter.feed(Data(buffer[0..<n])) else { return .finished }
        return .lines(lines)
    }
}
