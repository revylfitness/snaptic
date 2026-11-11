import Foundation
import SnapticKit
import SnapticShims

/// The hang watchdog (lead; PLAN 0.4 §4.11, X-1, A2). A main-queue timer in `.common` modes stamps a heartbeat every
/// 500 ms; a dedicated thread looks every 250 ms, and when main's last beat is over 3 s old while the shim holds a
/// restriction it calls `invalidateAll` from that thread (S0-5: safe off main) so the icons come back while main is
/// still stuck. Once main beats again, `onRelease` runs there (A5: the core fails safe with `.hang` and counts
/// `icons.hangExpand`). Length can't change a length off main, so the watchdog only matters on Native (README text).
/// While it runs, `EmergencyActions` can release the restriction from the signal path too.
final class IconsWatchdog: @unchecked Sendable {
    /// Main, after a release.
    @MainActor var onRelease: (() -> Void)?

    /// DEBUG builds only (M12): `defaults write <Snaptic's id> Debug.icons.hangMainSeconds 6` blocks main once, right
    /// after the next successful activation, then the key is removed.
    static let debugHangKey = "Debug.icons.hangMainSeconds"

    private let lock = NSLock()
    private var lastBeat = ProcessInfo.processInfo.systemUptime
    private var firedThisHang = false
    private var releasedUnreported = false
    private var thread: Thread?
    private var heartbeat: Timer?
    private var emergency: EmergencyActions.Token?

    init() {}

    @MainActor var isRunning: Bool { thread != nil }

    @MainActor func start() {
        guard thread == nil else { return }
        beat()
        let timer = Timer(timeInterval: IconsWatchdogRule.heartbeat, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
        let thread = Thread { [weak self] in
            while !Thread.current.isCancelled {
                Thread.sleep(forTimeInterval: IconsWatchdogRule.poll)
                guard let self else { return }
                self.check()
            }
        }
        thread.name = "com.snaptic.icons.watchdog"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        emergency = EmergencyActions.shared.add("icons.invalidateAll") { SNMenuBarVisibility.invalidateAll() }
    }

    @MainActor func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        thread?.cancel()
        thread = nil
        if let emergency { EmergencyActions.shared.remove(emergency) }
        emergency = nil
        lock.lock()
        firedThisHang = false
        releasedUnreported = false
        lock.unlock()
    }

    /// M12: called after each successful Native activation (`NativeBackend.onActivated`).
    @MainActor func debugHangIfRequested(_ defaults: UserDefaults = .standard) {
        #if DEBUG
        guard let seconds = IconsWatchdogRule.debugHang(defaults.double(forKey: Self.debugHangKey)) else { return }
        defaults.removeObject(forKey: Self.debugHangKey)
        DispatchQueue.main.async { Thread.sleep(forTimeInterval: seconds) }
        #endif
    }

    // MARK: Main

    @MainActor private func beat() {
        lock.lock()
        lastBeat = ProcessInfo.processInfo.systemUptime
        firedThisHang = false
        let report = releasedUnreported
        releasedUnreported = false
        lock.unlock()
        if report { onRelease?() }
    }

    // MARK: Watchdog thread

    private func check() {
        lock.lock()
        let age = (ProcessInfo.processInfo.systemUptime - lastBeat) * 1000
        let fire = IconsWatchdogRule.shouldRelease(mainAgeMillis: age, held: NativeBackend.heldCount,
                                                   firedThisHang: firedThisHang)
        if fire {
            firedThisHang = true
            releasedUnreported = true
        }
        lock.unlock()
        if fire { SNMenuBarVisibility.invalidateAll() }
    }
}
