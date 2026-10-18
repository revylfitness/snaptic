import AppKit
import Darwin
import SnapticKit

// Process exit watching for holds (owner: J; PLAN 0.3 §2.5, §2.8, N17, R5-14): the only user of EVFILT_PROC and
// proc_pidinfo in Awake. One kqueue per watch (≤ 8 holds), read through a DispatchSourceRead on the main queue and
// closed in its cancel handler. The kevent is armed FIRST and the process re-read after, so an exit between the
// caller's check and the arm can't be missed: ESRCH, another start time or another user refuses the watch.

@MainActor final class ProcessWatch: AwakeServiceLifecycle {
    /// Ancestor hops for the holder name (N17).
    static let maxAncestorHops = 16

    weak var context: AwakeContext?
    private var active = false
    private var watches: [UInt64: Watch] = [:]
    private var next: UInt64 = 0

    private final class Watch {
        let source: DispatchSourceRead
        var onExit: (@MainActor () -> Void)?
        var endHandler: UInt64?
        weak var lifetime: Lifetime?
        init(source: DispatchSourceRead, onExit: @escaping @MainActor () -> Void) {
            self.source = source
            self.onExit = onExit
        }
    }

    init() {}

    /// Live watches (diagnostics, tests of the hold cap).
    var count: Int { watches.count }

    // MARK: Facts

    /// proc_pidinfo(PROC_PIDTBSDINFO): the owner uid and the start time in microseconds since 1970 (the same value as
    /// SNProcess.startTime, so callers can compare). nil when the pid is gone or unreadable.
    func facts(_ pid: Int32) -> (uid: uid_t, startTime: UInt64)? {
        guard let info = Self.bsdInfo(pid) else { return nil }
        return (info.pbi_uid, info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec)
    }

    // MARK: Watching

    /// Arms kqueue EV_ADD EVFILT_PROC NOTE_EXIT (a DispatchSourceRead on the kq fd, main queue) FIRST, then re-reads
    /// facts: false (refused) on ESRCH, start-time mismatch or another uid. The handler runs once, on main; `lifetime`
    /// ending first cancels the watch without running it. Refused while inactive.
    func watch(pid: Int32, startTime: UInt64, lifetime: Lifetime, onExit: @escaping @MainActor () -> Void) -> Bool {
        guard active, pid > 1, !lifetime.isEnded else { return false }
        let kq = kqueue()
        guard kq >= 0 else { return false }
        _ = fcntl(kq, F_SETFD, FD_CLOEXEC)
        var change = kevent(ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ENABLE | EV_ONESHOT),
                            fflags: UInt32(NOTE_EXIT), data: 0, udata: nil)
        guard kevent(kq, &change, 1, nil, 0, nil) == 0 else {
            close(kq)
            return false
        }
        // Armed: now the process must still be the one the caller named.
        guard let now = facts(pid), now.startTime == startTime, now.uid == getuid() else {
            close(kq)
            return false
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: kq, queue: .main)
        next &+= 1
        let id = next
        let watch = Watch(source: source, onExit: onExit)
        watch.lifetime = lifetime
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fired(id, kq: kq) }
        }
        source.setCancelHandler { close(kq) }
        watches[id] = watch
        watch.endHandler = lifetime.addEndHandler { [weak self] in self?.cancel(id, runHandler: false) }
        source.resume()
        return true
    }

    /// N17 holder name: the first regular app among `pid` and its ancestors (pbi_ppid, ≤ 16 hops, same uid), by its
    /// localized name; nil → "the command line". Local UI only; never stored.
    func holderName(for pid: Int32) -> String? {
        let uid = getuid()
        var current = pid
        var seen = Set<Int32>()
        for _ in 0...Self.maxAncestorHops {
            guard current > 1, seen.insert(current).inserted, let info = Self.bsdInfo(current), info.pbi_uid == uid else {
                return nil
            }
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular,
               let name = app.localizedName, !name.isEmpty {
                return TextSanitizer.clean(name, maxScalars: 64)
            }
            current = Int32(bitPattern: info.pbi_ppid)
        }
        return nil
    }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
    }

    /// Defensive path only (R5-14: holds end `.commandLineOff` before `process` deactivates): every remaining watch's
    /// handler runs once (SessionController records `.processExited`), then every kqueue closes.
    func deactivate() {
        guard active else { return }
        active = false
        for id in watches.keys.sorted() { cancel(id, runHandler: true) }
        watches = [:]
        context = nil
    }

    // MARK: Private

    private func fired(_ id: UInt64, kq: Int32) {
        guard watches[id] != nil else { return }
        var event = kevent()
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        let n = kevent(kq, nil, 0, &event, 1, &timeout)
        // A spurious wake-up (no event) keeps the watch; an error or the exit note ends it.
        if n == 0 { return }
        if n > 0, event.filter == Int16(EVFILT_PROC), event.fflags & UInt32(NOTE_EXIT) == 0 { return }
        cancel(id, runHandler: true)
    }

    private func cancel(_ id: UInt64, runHandler: Bool) {
        guard let watch = watches.removeValue(forKey: id) else { return }
        watch.source.cancel()
        let handler = watch.onExit
        watch.onExit = nil
        if let lifetime = watch.lifetime { lifetime.removeEndHandler(watch.endHandler) }
        if runHandler { handler?() }
    }

    private nonisolated static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }
}
