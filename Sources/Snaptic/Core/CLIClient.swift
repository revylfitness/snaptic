import Darwin
import Foundation
import SnapticKit

/// `snaptic …` (a symlink named snaptic) or `Snaptic cli …` (PLAN §11). Sends one request
/// to the running Snaptic over its per-user socket and prints the reply. Never starts
/// AppKit and never touches TCC-guarded APIs. Exit codes: 0 ok, 2 usage, 3 not found,
/// 4 refused, 5 unavailable, 6 cancelled or timed out.
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
        guard let home = AccountPaths.home else { fail(ControlExit.unavailable, L("Your home folder couldn't be found.")) }
        let path = KitControl.socketPath(home: home)
        guard KitControl.isUsableSocketPath(path), let line = KitControl.encode(request) else {
            fail(ControlExit.usage, L("The command is too long."))
        }

        let fd = connectSocket(path)
        guard fd >= 0 else {
            fail(ControlExit.unavailable,
                 L("Snaptic isn't running, or command-line control is off (Settings → General → Command-Line Control)."))
        }
        guard sendAll(fd, line) else { fail(ControlExit.unavailable, L("Snaptic closed the connection.")) }
        guard let reply = readReply(fd, timeout: KitControl.clientTimeoutSeconds) else {
            fail(ControlExit.cancelled, L("Snaptic didn't answer in time."))
        }
        close(fd)
        guard let response = KitControl.decodeResponse(reply) else { fail(ControlExit.unavailable, L("Unreadable reply.")) }

        if command.json && response.exitCode != ControlExit.ok {
            let message = response.output.isEmpty ? ControlExit.describe(response.exitCode) : response.output
            print(KitControl.errorJSON(response.exitCode, message))
        } else if response.exitCode == ControlExit.ok {
            if !response.output.isEmpty { print(response.output) }
        } else {
            printError(response.output.isEmpty ? ControlExit.describe(response.exitCode) : response.output)
        }
        exit(response.exitCode)
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

    /// One reply line, waiting with poll() so a stuck Snaptic can't hang the caller.
    private static func readReply(_ fd: Int32, timeout: Double) -> Data? {
        var buffer = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var chunk = [UInt8](repeating: 0, count: 8_192)
        while buffer.count <= KitControl.maxMessageBytes {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&poller, 1, Int32(min(remaining, 3600) * 1000))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { return nil }
            let n = chunk.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress, raw.count) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { break }
            buffer.append(contentsOf: chunk[0..<n])
            if let newline = buffer.firstIndex(of: 0x0A) { return Data(buffer[buffer.startIndex..<newline]) }
        }
        return buffer.isEmpty ? nil : buffer
    }
}
