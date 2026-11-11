import AppKit
import SnapticKit

/// The Length engine's app glue (lead; PLAN 0.4 §4.2.3, A2, R3-15). K3 put the lengths, verify-on-next-tick and the
/// 250 ms screen re-apply in the Kit core, over `IconsItemsPort` (`IconsItems`), so Length has no visibility port.
/// What the core still needs from AppKit lives here: the screens it sizes `|` for, and the main-queue scheduler in
/// `.common` modes both engines run on (so a timer still fires while a menu tracks or a slider drags). A3's
/// `IconsMonitors` uses the same scheduler.
enum LengthBackend {
    /// Every screen in AppKit's global space (R3-12), for `IconsEngineHost.screens()`.
    @MainActor static func screens() -> [IconsScreen] {
        NSScreen.screens.map(screen)
    }

    @MainActor static func screen(_ s: NSScreen) -> IconsScreen {
        let f = s.frame
        var auxMinX: Double?
        if let aux = s.auxiliaryTopRightArea {
            // Documented in the screen's space, which is global; a value outside the screen is read as local.
            let x = Double(aux.minX)
            auxMinX = x >= Double(f.minX) && x <= Double(f.maxX) ? x : x + Double(f.minX)
        }
        return IconsScreen(frame: IconsRect(x: f.minX, y: f.minY, width: f.width, height: f.height),
                           safeAreaTop: Double(s.safeAreaInsets.top), auxiliaryTopRightMinX: auxMinX)
    }

    /// The primary screen's height: Accessibility's y origin is its top edge (`AXInventory`). Nil with no screen.
    @MainActor static var primaryHeight: Double? {
        NSScreen.screens.first.map { Double($0.frame.height) }
    }
}

/// `IconsSchedulerPort` on the main run loop in `.common` modes. `after(0)` runs on the next turn.
@MainActor final class IconsScheduler: @preconcurrency IconsSchedulerPort {
    init() {}

    @discardableResult
    func after(_ seconds: Double, _ work: @escaping () -> Void) -> IconsCancellable {
        let token = IconsTimerToken()
        let delay = seconds.isFinite ? max(0, seconds) : 0
        // The closure holds the token until the timer fires or is invalidated (the core may drop its reference).
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard !token.cancelled else { return }
                token.finish()
                work()
            }
        }
        token.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        return token
    }
}

/// One scheduled work item. Cancelling is idempotent; the timer is released once it fires or is cancelled.
@MainActor final class IconsTimerToken: @preconcurrency IconsCancellable {
    fileprivate var timer: Timer?
    private(set) var cancelled = false

    fileprivate init() {}

    func cancel() {
        cancelled = true
        finish()
    }

    fileprivate func finish() {
        timer?.invalidate()
        timer = nil
    }
}
