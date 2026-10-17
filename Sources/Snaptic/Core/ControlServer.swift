import Darwin
import Foundation
import SnapticKit

/// The command-line control server (PLAN §11, §4.10(3)): a Unix socket at
/// ~/Library/Application Support/Snaptic/control/snaptic.sock (directory 0700, socket 0600,
/// path from getpwuid_r, < 104 bytes). Per connection: CLOEXEC, SO_NOSIGPIPE, peer uid
/// must be ours, one request of at most 64 KB read within 2 s, one reply. At most 4
/// connections at once and 20 requests per second. Off by default.
@MainActor final class ControlServer {
    enum Status: Equatable {
        case off
        case listening(String)
        case failed(String)
    }

    private let registry: ControlCommandRegistry
    private var listener: ControlListener?
    /// "Let commands skip the confirmation panel" (read per request).
    var skipConfirmationAllowed: @MainActor () -> Bool = { false }
    var onStatusChange: (@MainActor () -> Void)?

    private(set) var status: Status = .off {
        didSet { if status != oldValue { onStatusChange?() } }
    }

    init(registry: ControlCommandRegistry) {
        self.registry = registry
    }

    var isRunning: Bool { listener != nil }

    /// Idempotent.
    func start() {
        guard listener == nil else { return }
        guard let home = AccountPaths.home else {
            status = .failed(L("Your account's home folder couldn't be found."))
            return
        }
        let directory = KitControl.socketDirectory(home: home)
        let path = KitControl.socketPath(home: home)
        guard KitControl.isUsableSocketPath(path) else {
            status = .failed(L("The path to Snaptic's socket is too long for macOS."))
            return
        }
        guard Self.prepareDirectory(directory) else {
            status = .failed(L("Snaptic couldn't create a private folder for its socket."))
            return
        }
        let listener = ControlListener(path: path) { [weak self] request, reply in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else {
                        reply(.failure(ControlExit.unavailable, L("Snaptic is quitting.")))
                        return
                    }
                    let allowed = self.skipConfirmationAllowed()
                    let registry = self.registry
                    Task { @MainActor in
                        reply(await registry.dispatch(request, skipConfirmationAllowed: allowed))
                    }
                }
            }
        }
        if let problem = listener.start() {
            status = .failed(problem)
            EventLog.shared.record(.control, "Control server failed to start")
            return
        }
        self.listener = listener
        status = .listening(path)
        EventLog.shared.record(.control, "Control server listening")
    }

    /// Idempotent; removes the socket.
    func stop() {
        guard let listener else { return }
        listener.stop()
        self.listener = nil
        status = .off
        EventLog.shared.record(.control, "Control server stopped")
    }

    /// Creates the directory 0700 (or fixes its mode) and checks it is ours and real.
    private static func prepareDirectory(_ path: String) -> Bool {
        guard AccountPaths.supportDirectory() != nil else { return false }
        var info = stat()
        if lstat(path, &info) != 0 {
            guard mkdir(path, 0o700) == 0 || errno == EEXIST, lstat(path, &info) == 0 else { return false }
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { return false }
        if info.st_mode & 0o077 != 0 { guard chmod(path, 0o700) == 0 else { return false } }
        return true
    }
}

/// The listening socket and its connections; everything here runs on one serial queue.
private final class ControlListener: @unchecked Sendable {
    typealias Reply = @Sendable (ControlResponse) -> Void

    private let path: String
    private let handle: @Sendable (ControlRequest, @escaping Reply) -> Void
    private let queue = DispatchQueue(label: "app.snaptic.control")
    private var source: DispatchSourceRead?
    private var listenFD: Int32 = -1
    private var active = 0
    private var rate = ControlRateWindow(limit: KitControl.maxRequestsPerSecond, window: 1)
    private var connections: [ObjectIdentifier: ControlConnection] = [:]

    init(path: String, handle: @escaping @Sendable (ControlRequest, @escaping Reply) -> Void) {
        self.path = path
        self.handle = handle
    }

    /// Nil on success, otherwise why not.
    func start() -> String? {
        var info = stat()
        if lstat(path, &info) == 0 {
            // A stale socket of ours from a crash is replaced; anything else stays put.
            guard (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == getuid() else {
                return L("Something else is in the way at ") + path
            }
            unlink(path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return L("Snaptic couldn't create its socket.") }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else {
            close(fd)
            return L("The path to Snaptic's socket is too long for macOS.")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        // The 0700 directory already keeps others out; the socket itself is 0600 too.
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            close(fd)
            unlink(path)
            return L("Snaptic couldn't listen on its socket.")
        }
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptAll() }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
        return nil
    }

    /// The socket file goes away now; the descriptors close on the queue.
    func stop() {
        unlink(path)
        queue.async { [self] in
            source?.cancel()
            source = nil
            for connection in connections.values { connection.finish() }
            connections = [:]
        }
    }

    // Queue only.
    private func acceptAll() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }   // EAGAIN: nothing more waiting
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)
            var one: Int32 = 1
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                close(client)
                continue
            }
            guard active < KitControl.maxConcurrentConnections else {
                ControlConnection.sendOnce(client, .failure(ControlExit.unavailable, L("Snaptic is busy; try again.")))
                close(client)
                continue
            }
            guard rate.allow(now: ProcessInfo.processInfo.systemUptime) else {
                ControlConnection.sendOnce(client, .failure(ControlExit.unavailable, L("Too many requests; slow down.")))
                close(client)
                continue
            }
            active += 1
            let connection = ControlConnection(fd: client, queue: queue, handle: handle)
            let key = ObjectIdentifier(connection)
            connections[key] = connection
            connection.start { [weak self] in
                self?.connections[key] = nil
                self?.active -= 1
            }
        }
    }
}

/// One client: read one line (≤ 64 KB, within 2 s), answer once, close. Queue only.
private final class ControlConnection: @unchecked Sendable {
    private let fd: Int32
    private let queue: DispatchQueue
    private let handle: @Sendable (ControlRequest, @escaping @Sendable (ControlResponse) -> Void) -> Void
    private var source: DispatchSourceRead?
    private var buffer = Data()
    private var gotRequest = false
    private var finished = false
    private var onFinish: (() -> Void)?

    init(fd: Int32, queue: DispatchQueue,
         handle: @escaping @Sendable (ControlRequest, @escaping @Sendable (ControlResponse) -> Void) -> Void) {
        self.fd = fd
        self.queue = queue
        self.handle = handle
    }

    func start(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        // The source owns the descriptor: it closes only after the source is cancelled.
        source.setCancelHandler { [fd] in close(fd) }
        self.source = source
        source.resume()
        queue.asyncAfter(deadline: .now() + KitControl.readTimeoutSeconds) { [weak self] in
            guard let self, !self.gotRequest else { return }
            self.finish()
        }
    }

    private func readAvailable() {
        var chunk = [UInt8](repeating: 0, count: 8_192)
        let n = chunk.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress, raw.count) }
        if n < 0 && (errno == EAGAIN || errno == EINTR) { return }
        guard n > 0 else { finish(); return }   // EOF or error: the client is gone
        guard !gotRequest else { return }       // one request per connection; extra bytes are ignored
        buffer.append(contentsOf: chunk[0..<n])
        if let newline = buffer.firstIndex(of: 0x0A) {
            gotRequest = true
            let line = buffer[buffer.startIndex..<newline]
            switch KitControl.decodeRequest(Data(line)) {
            case .failure(let response):
                reply(response)
            case .success(let request):
                handle(request) { [weak self] response in
                    guard let self else { return }
                    self.queue.async { self.reply(response) }
                }
            }
        } else if buffer.count > KitControl.maxMessageBytes {
            gotRequest = true
            reply(.failure(ControlExit.usage, L("Request too large.")))
        }
    }

    private func reply(_ response: ControlResponse) {
        guard !finished else { return }
        Self.sendOnce(fd, response)
        finish()
    }

    /// Writes one reply line, waiting at most 2 s for the client to take it.
    static func sendOnce(_ fd: Int32, _ response: ControlResponse) {
        let data = KitControl.encode(response)
            ?? KitControl.encode(ControlResponse.failure(response.exitCode, L("Reply too large.")))
            ?? Data()
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let n = write(fd, base + offset, raw.count - offset)
                if n > 0 { offset += n; continue }
                if n < 0 && errno == EINTR { continue }
                guard n < 0 && errno == EAGAIN else { return }
                var poller = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                guard poll(&poller, 1, 2_000) > 0 else { return }
            }
        }
    }

    /// Idempotent: closes the socket and frees the slot.
    func finish() {
        guard !finished else { return }
        finished = true
        if let source {
            source.cancel()
        } else {
            close(fd)
        }
        source = nil
        let done = onFinish
        onFinish = nil
        done?()
    }
}
