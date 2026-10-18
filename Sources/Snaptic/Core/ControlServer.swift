import Darwin
import Foundation
import SnapticKit
import SnapticShims

/// The command-line control server (PLAN §11, §4.10(3)): a Unix socket at
/// ~/Library/Application Support/Snaptic/control/snaptic.sock (directory 0700, socket 0600,
/// path from getpwuid_r, < 104 bytes). Per connection: CLOEXEC, SO_NOSIGPIPE, peer uid
/// must be ours, one request of at most 64 KB read within 2 s, one reply. At most 4
/// connections at once and 20 requests per second. Off by default.
///
/// 0.3 §2.10 connection holds: a `holds: true` verb may answer `holding`, which moves the connection from the 4
/// request slots to a separate pool of 8 held connections. A held connection has no read timeout; it ends on EOF,
/// on any byte after the request, on a failed ping or final line, when its handler finishes it, or when the server
/// stops. Pings (`{"ping":true}`) go out every `holdPingInterval`.
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
    /// Seconds between pings on held connections; read when the server starts (SelfTest sets 1).
    var holdPingInterval: TimeInterval = TimeInterval(KitControl.holdPingSeconds)
    /// Called on the server's queue with (held, active) after every pool change (SelfTest prints it).
    var onPoolChange: (@Sendable (_ held: Int, _ active: Int) -> Void)?

    private(set) var status: Status = .off {
        didSet { if status != oldValue { onStatusChange?() } }
    }

    init(registry: ControlCommandRegistry) {
        self.registry = registry
    }

    var isRunning: Bool { listener != nil }

    /// Idempotent. `socketPath` is non-nil only from SelfTest in token mode (R5-5): the path must sit in an
    /// existing 0700 directory of ours; it is never created or repaired.
    func start(socketPath override: String? = nil) {
        guard listener == nil else { return }
        let directory: String
        let path: String
        if let override {
            path = override
            directory = (override as NSString).deletingLastPathComponent
        } else {
            guard let home = AccountPaths.home else {
                status = .failed(L("Your account's home folder couldn't be found."))
                return
            }
            directory = KitControl.socketDirectory(home: home)
            path = KitControl.socketPath(home: home)
        }
        guard KitControl.isUsableSocketPath(path) else {
            status = .failed(L("The path to Snaptic's socket is too long for macOS."))
            return
        }
        guard override == nil ? Self.prepareDirectory(directory) : Self.isPrivateDirectory(directory) else {
            status = .failed(L("Snaptic couldn't create a private folder for its socket."))
            return
        }
        let registry = self.registry
        let listener = ControlListener(path: path, pingInterval: max(0.05, holdPingInterval), onPoolChange: onPoolChange) {
            [weak self] request, peer, cancellation, hold, reply in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else {
                        reply(.failure(ControlExit.unavailable, L("Snaptic is quitting.")))
                        return
                    }
                    guard !cancellation.isCancelled else {
                        reply(.failure(ControlExit.cancelled, ""))
                        return
                    }
                    let allowed = self.skipConfirmationAllowed()
                    // The reply (which frees the connection's slot, or moves it to the held pool) is sent when the
                    // handler returns, also after the client went away and cancelled the task.
                    let task = Task { @MainActor in
                        let response = await registry.dispatch(request, peer: peer, hold: hold,
                                                               skipConfirmationAllowed: allowed)
                        reply(Task.isCancelled ? .failure(ControlExit.cancelled, L("Cancelled.")) : response)
                    }
                    cancellation.attach(task)
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

    /// Idempotent; removes the socket. Held connections close (their holds' `onClose` runs).
    func stop() {
        guard let listener else { return }
        listener.stop()
        self.listener = nil
        status = .off
        EventLog.shared.record(.control, "Control server stopped")
    }

    /// Held-connection writes (security L5): ONE non-blocking attempt (`send(…, MSG_DONTWAIT)`; EINTR retried
    /// once). False on EAGAIN, a short write or an error; the caller then closes that hold. Never polls, never
    /// blocks the listener queue. `sendOnce` stays for ordinary replies.
    nonisolated static func sendHeld(_ fd: Int32, _ response: ControlResponse) -> Bool {
        guard let data = KitControl.encode(response) else { return false }
        return sendHeld(fd, data: data)
    }

    /// `sendHeld` for a ready line (pings).
    nonisolated static func sendHeld(_ fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress, raw.count > 0 else { return true }
            var n = send(fd, base, raw.count, MSG_DONTWAIT)
            if n < 0 && errno == EINTR { n = send(fd, base, raw.count, MSG_DONTWAIT) }
            return n == raw.count
        }
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

    /// An existing real directory of ours that nobody else can enter (the self-test socket's).
    private static func isPrivateDirectory(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFDIR && info.st_uid == getuid() && info.st_mode & 0o077 == 0
    }
}

/// Who is on the other end of a connection (0.3 §2.10). Best effort, not identity (r3 security L1): LOCAL_PEERPID
/// reports the socket's last owner, which an inherited or SCM_RIGHTS-passed fd changes, and a client can write its
/// request and exit before accept. Read on the accepted fd right after getpeereid (uid from getpeereid), before the
/// request line is read; start time from SNProcess.startTime(for:) (same µs epoch as HoldBinding). Never from the
/// request; ControlRequest gains no field. A connection hold's authority is the connection itself: EOF ends it
/// whatever the pid does.
struct ControlPeer: Equatable, Sendable {
    let pid: pid_t
    let uid: uid_t
    let startTime: UInt64?
}

/// One connection's hold (0.3 §2.10). Created by the listener for EVERY connection (the listener can't know
/// `holds`: the registry lives on main); dispatch passes it to the handler only when the entry has `holds: true`.
/// Thread-safe: the listener queue closes it, main registers handlers and finishes it.
final class ControlHold: @unchecked Sendable {
    /// Why the hold ended (SelfTest prints it; `finished` is the handler's own `finish`).
    enum CloseReason: String, Sendable {
        case eof, extra, ping, limit, server, finished, error
    }

    private let lock = NSLock()
    private var closed = false
    private var reason: CloseReason?
    private var handlers: [@MainActor () -> Void] = []
    /// Set by the connection once it is held: writes the final line and closes (on the listener queue).
    private var writer: (@Sendable (ControlResponse) -> Void)?
    /// A `finish` that came before the connection was held; the connection sends it after the holding reply.
    private var pendingFinal: ControlResponse?

    init() {}

    /// The handler checks it after arming its process watch.
    var isClosed: Bool {
        lock.lock(); defer { lock.unlock() }
        return closed
    }

    var closeReason: CloseReason? {
        lock.lock(); defer { lock.unlock() }
        return reason
    }

    /// Runs once, on main, when the hold ends for any reason (EOF, a byte after the request, a read or write error,
    /// a failed ping, the held-pool limit, server stop, or `finish`). Registered after the close → runs on the next
    /// main-queue turn.
    func onClose(_ handler: @escaping @MainActor () -> Void) {
        lock.lock()
        if closed {
            lock.unlock()
            Self.runOnMain([handler])
            return
        }
        handlers.append(handler)
        lock.unlock()
    }

    /// Writes one more line and closes; idempotent (a no-op once closed).
    func finish(_ final: ControlResponse) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        reason = .finished
        let writer = self.writer
        self.writer = nil
        if writer == nil { pendingFinal = final }
        let run = handlers
        handlers = []
        lock.unlock()
        writer?(final)
        Self.runOnMain(run)
    }

    // MARK: Listener side

    /// Marks the hold closed (first reason wins) and runs the handlers on main.
    fileprivate func close(_ why: CloseReason) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        reason = why
        writer = nil
        let run = handlers
        handlers = []
        lock.unlock()
        Self.runOnMain(run)
    }

    /// The connection is held: later `finish` calls write through `writer`. Returns a final line that `finish`
    /// left before this point (the hold is then already closed), or nil.
    fileprivate func attach(_ writer: @escaping @Sendable (ControlResponse) -> Void) -> ControlResponse? {
        lock.lock(); defer { lock.unlock() }
        if closed {
            let final = pendingFinal
            pendingFinal = nil
            return final
        }
        self.writer = writer
        return nil
    }

    /// A final line `finish` left before the connection was held (taken once).
    fileprivate func takePendingFinal() -> ControlResponse? {
        lock.lock(); defer { lock.unlock() }
        let final = pendingFinal
        pendingFinal = nil
        return final
    }

    private static func runOnMain(_ handlers: [@MainActor () -> Void]) {
        guard !handlers.isEmpty else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for handler in handlers { handler() }
            }
        }
    }
}

/// What a handler gets besides its request (0.3 §2.10): the peer, and the connection's hold for `holds: true` verbs.
struct ControlContext {
    let peer: ControlPeer
    let hold: ControlHold?
}

/// Lets a connection cancel its request's handler task when the client goes away (the
/// task is created later, on main). Thread-safe.
final class ControlCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var task: Task<Void, Never>?

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func attach(_ task: Task<Void, Never>) {
        lock.lock()
        let already = cancelled
        if !already { self.task = task }
        lock.unlock()
        if already { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        self.task = nil
        lock.unlock()
        task?.cancel()
    }
}

/// The listening socket and its connections; everything here runs on one serial queue.
private final class ControlListener: @unchecked Sendable {
    typealias Reply = @Sendable (ControlResponse) -> Void
    typealias Handler = @Sendable (ControlRequest, ControlPeer, ControlCancellation, ControlHold, @escaping Reply) -> Void

    private let path: String
    private let handle: Handler
    private let pingInterval: TimeInterval
    private let onPoolChange: (@Sendable (_ held: Int, _ active: Int) -> Void)?
    private let queue = DispatchQueue(label: "app.snaptic.control")
    private var source: DispatchSourceRead?
    private var pingTimer: DispatchSourceTimer?
    private var listenFD: Int32 = -1
    private var pool = ControlSlotPool()
    private var rate = ControlRateWindow(limit: KitControl.maxRequestsPerSecond, window: 1)
    private var connections: [ObjectIdentifier: ControlConnection] = [:]

    init(path: String, pingInterval: TimeInterval, onPoolChange: (@Sendable (_ held: Int, _ active: Int) -> Void)?,
         handle: @escaping Handler) {
        self.path = path
        self.pingInterval = pingInterval
        self.onPoolChange = onPoolChange
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
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
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

        let timer = DispatchSource.makeTimerSource(queue: queue)
        let leeway = DispatchTimeInterval.milliseconds(max(10, Int(pingInterval * 100)))   // 10%
        timer.schedule(deadline: .now() + pingInterval, repeating: pingInterval, leeway: leeway)
        timer.setEventHandler { [weak self] in self?.pingHeld() }
        pingTimer = timer
        timer.resume()
        return nil
    }

    /// The socket file goes away now; the descriptors close on the queue, and every hold ends (`server`).
    func stop() {
        unlink(path)
        queue.async { [self] in
            source?.cancel()
            source = nil
            pingTimer?.cancel()
            pingTimer = nil
            for connection in connections.values { connection.abandon() }
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
            // Right after getpeereid, before anything is read (§2.10).
            let peer = Self.peer(of: client, uid: uid)
            // Held connections never count here: they left the request pool.
            guard pool.active < pool.maxActive else {
                ControlConnection.sendOnce(client, .failure(ControlExit.unavailable, L("Snaptic is busy; try again.")))
                close(client)
                continue
            }
            guard rate.allow(now: ProcessInfo.processInfo.systemUptime) else {
                ControlConnection.sendOnce(client, .failure(ControlExit.unavailable, L("Too many requests; slow down.")))
                close(client)
                continue
            }
            _ = pool.admit()
            poolChanged()
            let connection = ControlConnection(fd: client, queue: queue, peer: peer, handle: handle, listener: self)
            connections[ObjectIdentifier(connection)] = connection
            connection.start()
        }
    }

    /// The peer's pid (LOCAL_PEERPID) and start time; pid 0 when the kernel can't say (the client already left).
    private static func peer(of fd: Int32, uid: uid_t) -> ControlPeer {
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        if getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) != 0 || pid < 0 { pid = 0 }
        let started = pid > 0 ? SNProcess.startTime(for: pid) : 0
        return ControlPeer(pid: pid, uid: uid, startTime: started == 0 ? nil : started)
    }

    /// A `holding` reply: moves the connection to the held pool (exactly once); false when 8 are held.
    func promote(_ connection: ControlConnection) -> Bool {
        guard pool.promote() else { return false }
        poolChanged()
        return true
    }

    /// A finished connection frees the slot of the pool it is in (exactly once, enforced by the connection).
    func released(_ connection: ControlConnection, wasHeld: Bool) {
        connections[ObjectIdentifier(connection)] = nil
        pool.release(wasHeld: wasHeld)
        assert(pool.active >= 0 && pool.held >= 0)
        poolChanged()
    }

    private func poolChanged() {
        onPoolChange?(pool.held, pool.active)
    }

    private func pingHeld() {
        guard pool.held > 0 else { return }
        for connection in connections.values { connection.ping() }
    }
}

/// One client: read one line (≤ 64 KB, within 2 s), answer once, close. Queue only.
/// The connection's slot stays taken until its handler has returned, even if the client
/// hung up first (that cancels the handler's task), so a client can't start more than 4
/// handlers by connecting and leaving. A `holding` reply instead keeps it open in the held
/// pool (0.3 §2.10) until EOF, an extra byte, a failed write, its handler's `finish` or stop.
private final class ControlConnection: @unchecked Sendable {
    private let fd: Int32
    private let queue: DispatchQueue
    private let peer: ControlPeer
    private let handle: ControlListener.Handler
    private weak var listener: ControlListener?
    let hold = ControlHold()
    private var source: DispatchSourceRead?
    private var buffer = Data()
    private var gotRequest = false
    /// The request asked for `--json` (final lines are wrapped like replies).
    private var json = false
    /// A byte arrived after the request's newline (in the same chunk or later): a hold refuses then (R5-5).
    private var extraAfterRequest = false
    /// The socket is closed (replied, timed out, client gone or server stopped).
    private var finished = false
    /// A handler runs and hasn't replied yet.
    private var inFlight = false
    /// In the held pool.
    private var isHeld = false
    /// The slot was given back (exactly once).
    private var released = false
    private var cancellation: ControlCancellation?

    init(fd: Int32, queue: DispatchQueue, peer: ControlPeer, handle: @escaping ControlListener.Handler,
         listener: ControlListener) {
        self.fd = fd
        self.queue = queue
        self.peer = peer
        self.handle = handle
        self.listener = listener
    }

    func start() {
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        // The source owns the descriptor: it closes only after the source is cancelled.
        source.setCancelHandler { [fd] in close(fd) }
        self.source = source
        source.resume()
        // Only the request must arrive in time; after a holding reply there is no read timeout (§2.10).
        queue.asyncAfter(deadline: .now() + KitControl.readTimeoutSeconds) { [weak self] in
            guard let self, !self.gotRequest else { return }
            self.hold.close(.eof)
            self.finish()
        }
    }

    private func readAvailable() {
        guard !finished else { return }
        var chunk = [UInt8](repeating: 0, count: 8_192)
        let n = chunk.withUnsafeMutableBytes { raw in read(fd, raw.baseAddress, raw.count) }
        if n < 0 && (errno == EAGAIN || errno == EINTR) { return }
        guard n > 0 else {
            // EOF or error: the client is gone; a running handler is cancelled, a hold ends.
            cancellation?.cancel()
            hold.close(n == 0 ? .eof : .error)
            finish()
            return
        }
        if isHeld {
            // A held client can't stream data and keep the queue busy: any byte ends the hold.
            hold.close(.extra)
            finish()
            return
        }
        guard !gotRequest else {
            // Ordinary verbs ignore extra bytes; a hold verb's holding reply turns into a close.
            extraAfterRequest = true
            return
        }
        buffer.append(contentsOf: chunk[0..<n])
        if let newline = buffer.firstIndex(of: 0x0A) {
            gotRequest = true
            if buffer.index(after: newline) < buffer.endIndex { extraAfterRequest = true }
            let line = buffer[buffer.startIndex..<newline]
            buffer = Data()
            switch KitControl.decodeRequest(Data(line)) {
            case .failure(let response):
                reply(response)
            case .success(let request):
                json = request.json
                let token = ControlCancellation()
                cancellation = token
                inFlight = true
                handle(request, peer, token, hold) { [self] response in
                    // Strong: the slot is only released (or moved) by this reply.
                    queue.async { [self] in
                        inFlight = false
                        cancellation = nil
                        if response.holding {
                            becomeHeld(response)
                        } else {
                            reply(response)
                        }
                        releaseIfDone()
                    }
                }
            }
        } else if buffer.count > KitControl.maxMessageBytes {
            gotRequest = true
            reply(.failure(ControlExit.usage, L("Request too large.")))
        }
    }

    private func reply(_ response: ControlResponse) {
        guard !finished else { return }
        hold.close(.finished)
        _ = Self.sendOnce(fd, response)
        finish()
    }

    /// The handler answered `holding` (dispatch only lets `holds: true` verbs do that).
    private func becomeHeld(_ response: ControlResponse) {
        guard !finished else {
            // The client left while the handler ran: no hold, the request slot is freed as usual.
            hold.close(.eof)
            return
        }
        if extraAfterRequest {
            hold.close(.extra)
            finish()
            return
        }
        if hold.isClosed {
            // The handler finished the hold before this reply got here: holding line, then its final line.
            if let final = hold.takePendingFinal(), Self.sendOnce(fd, response) {
                _ = ControlServer.sendHeld(fd, wrapped(final))
            }
            finish()
            return
        }
        guard listener?.promote(self) == true else {
            hold.close(.limit)
            _ = Self.sendOnce(fd, .failure(ControlExit.refused, L("Snaptic is already holding for 8 commands.")))
            finish()
            return
        }
        isHeld = true
        guard Self.sendOnce(fd, response) else {
            hold.close(.error)
            finish()
            return
        }
        // Only pings and one final line from now on, so a stalled reader can't make Snaptic queue much (L5).
        var size = KitControl.heldSendBufferBytes
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        let pending = hold.attach { [weak self, queue] final in
            queue.async { self?.writeFinal(final) }
        }
        if let pending {
            writeFinal(pending)
        } else if hold.isClosed {
            finish()
        }
    }

    private func wrapped(_ final: ControlResponse) -> ControlResponse {
        var line = json ? KitControl.jsonReply(final) : final
        line.holding = false
        return line
    }

    private func writeFinal(_ final: ControlResponse) {
        guard !finished else { return }
        _ = ControlServer.sendHeld(fd, wrapped(final))
        finish()
    }

    /// One ping; a full buffer or an error ends the hold.
    func ping() {
        guard isHeld, !finished else { return }
        if !ControlServer.sendHeld(fd, data: KitControl.pingLine) {
            hold.close(.ping)
            finish()
        }
    }

    /// Frees the slot once the socket is closed and no handler is running.
    private func releaseIfDone() {
        guard finished, !inFlight, !released else { return }
        released = true
        listener?.released(self, wasHeld: isHeld)
    }

    /// Writes one reply line, waiting at most 2 s for the client to take it. False when it didn't get through.
    @discardableResult
    static func sendOnce(_ fd: Int32, _ response: ControlResponse) -> Bool {
        let data = KitControl.encode(response)
            ?? KitControl.encode(ControlResponse.failure(response.exitCode, L("Reply too large.")))
            ?? Data()
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var offset = 0
            while offset < raw.count {
                let n = write(fd, base + offset, raw.count - offset)
                if n > 0 { offset += n; continue }
                if n < 0 && errno == EINTR { continue }
                guard n < 0 && errno == EAGAIN else { return false }
                var poller = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                guard poll(&poller, 1, 2_000) > 0 else { return false }
            }
            return true
        }
    }

    /// Idempotent: closes the socket; the slot is freed now, or when a running handler
    /// returns.
    func finish() {
        guard !finished else { return }
        finished = true
        if let source {
            source.cancel()
        } else {
            close(fd)
        }
        source = nil
        releaseIfDone()
    }

    /// Server stop: the handler is cancelled, the hold ends and the slot is freed when the handler returns.
    func abandon() {
        cancellation?.cancel()
        hold.close(.server)
        finish()
    }
}
