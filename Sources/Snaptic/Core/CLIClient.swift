import Darwin
import Foundation
import SnapticKit

/// `snaptic …` (a symlink named snaptic) or `Snaptic cli …` (PLAN §11). Sends one request
/// to the running Snaptic over its per-user socket and prints the reply. Never starts
/// AppKit and never touches TCC-guarded APIs. Exit codes: 0 ok, 2 usage, 3 not found,
/// 4 refused, 5 unavailable, 6 cancelled or timed out.
///
/// 0.3 §2.10 holding mode (`snaptic awake hold`): a reply with `holding` is printed and flushed, then the client keeps
/// reading with no timeout, drops ping lines, and exits with the final line's code (5 on EOF without one). It never
/// writes after the request and never half-closes, so its own exit (or Control-C, or a closed terminal) is the EOF
/// that ends the hold; it resets SIGINT and SIGQUIT to default first, since a background job may inherit them ignored. `--pid N` gets an ordinary reply and exits at once.
enum CLIClient {
    static func run(_ arguments: [String]) -> Never {
        let rest = arguments.count > 1 && arguments[1] == "cli" ? Array(arguments.dropFirst(2)) : Array(arguments.dropFirst())
        // FIXES-R3 10: with --json the client's own errors are JSON too, even a usage error.
        json = KitControl.wantsJSON(rest)
        let command: KitControl.ParsedCommand
        switch KitControl.parseCommandLine(rest) {
        case .success(let parsed): command = parsed
        case .failure(let error): fail(ControlExit.usage, error.message)
        }
        json = command.json
        var words = command.help ? ["help"] + command.words : command.words
        if command.help && words.count > 1 && words[1] == "help" { words.removeFirst() }
        guard let first = words.first, KitControl.isVerbWord(first.lowercased()) else {
            fail(ControlExit.usage, L("Unknown command. Run “snaptic help” for the list."))
        }
        let request = ControlRequest(verb: first.lowercased(), arguments: Array(words.dropFirst()), json: command.json,
                                     skipConfirmation: command.yes)
        let path: String
        if let selftest = selftestSocketPath() {
            path = selftest
        } else {
            guard let home = AccountPaths.home else { fail(ControlExit.unavailable, L("Your home folder couldn’t be found.")) }
            path = KitControl.socketPath(home: home)
        }
        guard KitControl.isUsableSocketPath(path), let line = KitControl.encode(request) else {
            fail(ControlExit.usage, L("The command is too long."))
        }

        let fd = connectSocket(path)
        guard fd >= 0 else {
            fail(ControlExit.unavailable,
                 L("Snaptic isn’t running, or command-line control is off (Settings › General › Command-line control)."))
        }
        guard sendAll(fd, line) else { fail(ControlExit.unavailable, L("Snaptic closed the connection.")) }
        var reader = ControlLineReader()
        let reply: Data
        switch nextLine(fd, &reader, timeout: KitControl.clientTimeoutSeconds) {
        case .line(let data): reply = data
        case .timedOut: fail(ControlExit.cancelled, L("Snaptic didn’t answer in time."))
        case .closed: fail(ControlExit.unavailable, L("Snaptic closed the connection."))
        }
        guard let response = KitControl.decodeResponse(reply) else { fail(ControlExit.unavailable, L("Unreadable reply.")) }
        guard response.holding && response.exitCode == ControlExit.ok else {
            close(fd)
            show(response)
            exit(response.exitCode)
        }

        // Holding: the connection is the hold. Print, flush, and wait for the final line however long it takes.
        // A background job in a shell without job control (`snaptic awake hold &` in a script or make recipe) starts
        // with SIGINT and SIGQUIT ignored, and that survives exec. Put them back to default so Control-C, which
        // reaches the whole foreground process group, ends the hold with the work instead of leaving it for 12 h.
        // With job control the job has its own process group, so this changes nothing there.
        signal(SIGINT, SIG_DFL)
        signal(SIGQUIT, SIG_DFL)
        show(response)
        fflush(stdout)
        while true {
            switch nextLine(fd, &reader, timeout: nil) {
            case .line(let data):
                if KitControl.isPing(data) { continue }
                guard let final = KitControl.decodeResponse(data) else { continue }
                close(fd)
                show(final)
                fflush(stdout)
                exit(final.exitCode)
            case .timedOut, .closed:
                close(fd)
                fail(ControlExit.unavailable, L("Snaptic ended the hold without saying why (it may have quit)."))
            }
        }
    }

    /// Prints a reply: output on stdout for success, the message on stderr (or an error object with --json).
    private static func show(_ response: ControlResponse) {
        if json && response.exitCode != ControlExit.ok {
            let message = response.output.isEmpty ? ControlExit.describe(response.exitCode) : response.output
            print(KitControl.errorJSON(response.exitCode, message))
        } else if response.exitCode == ControlExit.ok {
            if !response.output.isEmpty { print(response.output) }
        } else {
            printError(response.output.isEmpty ? ControlExit.describe(response.exitCode) : response.output)
        }
    }

    /// R5-5 token mode: the self-test's socket, only when SNAPTIC_SELFTEST_TOKEN is set and equals the contents of
    /// SNAPTIC_SELFTEST_TOKEN_FILE. This grants nothing (a client choosing a socket has no capability); the gate
    /// keeps the override out of normal use.
    private static func selftestSocketPath() -> String? {
        let environment = ProcessInfo.processInfo.environment
        guard environment[SelfTest.tokenVariable] != nil, let file = environment[SelfTest.tokenFileVariable],
              let socket = environment[SelfTest.socketVariable], SelfTest.tokenMatches(file: file) else { return nil }
        return socket
    }

    /// `--json` was given: errors go to stdout as `{"exitCode":…,"error":…}`.
    private static var json = false

    private static func fail(_ code: Int32, _ message: String) -> Never {
        if json {
            print(KitControl.errorJSON(code, message))
        } else {
            printError(message)
        }
        exit(code)
    }

    private static func printError(_ message: String) {
        fputs("snaptic: " + message + "\n", stderr)
    }

    private static func connectSocket(_ path: String) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return -1 }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0 else { close(fd); return -1 }
        return fd
    }

    private static func sendAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var offset = 0
            while offset < raw.count {
                let n = write(fd, base + offset, raw.count - offset)
                if n > 0 { offset += n } else if n < 0 && errno == EINTR { continue } else { return false }
            }
            return true
        }
    }

    private enum LineResult {
        case line(Data)
        case timedOut
        case closed
    }

    /// The next line, waiting with poll() so a stuck Snaptic can't hang the caller (nil timeout: wait forever, for
    /// a held connection). Bytes after a newline are kept for the next call, never dropped. A last line without a
    /// newline before EOF still counts.
    private static func nextLine(_ fd: Int32, _ reader: inout ControlLineReader, timeout: Double?) -> LineResult {
        if !pendingLines.isEmpty { return .line(pendingLines.removeFirst()) }
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        var chunk = [UInt8](repeating: 0, count: 8_192)
        while true {
            var wait: Int32 = -1
            if let deadline {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { return .timedOut }
                wait = Int32(min(remaining, 3600) * 1000)
            }
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, wait)
            if ready < 0 && errno == EINTR { continue }
            if ready == 0 { continue }
            guard ready > 0 else { return .closed }
            let n = chunk.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress, raw.count) }
            if n < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            guard n > 0 else {
                if let rest = reader.remainder {
                    reader = ControlLineReader()
                    return .line(rest)
                }
                return .closed
            }
            var lines = reader.append(chunk[0..<n])
            if !lines.isEmpty {
                let first = lines.removeFirst()
                pendingLines = lines
                return .line(first)
            }
        }
    }

    /// Lines a read completed beyond the one returned (several can arrive in one chunk).
    private static var pendingLines: [Data] = []
}
