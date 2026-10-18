import AppKit
import SnapticKit

/// The only route from a live slider (Settings `.live`, the menu's `MenuSliderRow`s, the Displays panel) to display
/// hardware (PLAN 0.3 §4.5). A latest-wins mailbox per (display, control) (Kit `LiveMailbox`): DDC controls are sent
/// at most 20 times a second, software and Apple brightness at display rate; the value that ends a drag is always
/// sent. When a drag ends the shown value (`DisplayRuntime`) is set to the target at once and read-backs that disagree
/// are ignored for a second (`LiveReadback`), so the slider doesn't snap back while the monitor catches up.
///
/// Delivery is on the main queue (it runs while a menu is open, N15). Several instances may exist (each menu
/// contributor and page holds one); slots are per instance, and the services behind them coalesce writes too.
@MainActor final class DisplayLiveController: DisplayLiveControlling {
    weak var context: DisplaysContext?

    /// DDC writes: at most 20 per second per (display, control).
    static let ddcInterval: Double = 1.0 / 20
    /// Gamma, overlay and Apple brightness: one per display frame.
    static let softwareInterval: Double = 1.0 / 60

    private struct Slot: Hashable {
        let display: DisplayKey
        let control: LiveControl
    }

    private var mailbox = LiveMailbox<Slot>()
    private var flush: DispatchWorkItem?

    init() {}

    convenience init(context: DisplaysContext) {
        self.init()
        self.context = context
    }

    func set(_ control: LiveControl, _ value: Double, for display: DisplayKey, phase: DragPhase) {
        guard let context, value.isFinite else { return }
        let slot = Slot(display: display, control: control)
        let now = ProcessInfo.processInfo.systemUptime
        if phase == .began {
            // Nothing moved yet; read-backs hold off while the user drags.
            if let code = Self.vcp(control) {
                context.ddc.controller?.holdReadbacks(code, for: display)
            } else {
                context.brightness.holdReadbacks(for: display)
            }
            return
        }
        let pace = interval(for: control, display: display, context: context)
        if let send = mailbox.submit(value, for: slot, final: phase == .ended, interval: pace, now: now) {
            deliver(send, to: slot, final: phase == .ended, context: context)
        }
        scheduleFlush()
    }

    // MARK: Delivery

    private func interval(for control: LiveControl, display: DisplayKey, context: DisplaysContext) -> Double {
        switch control {
        case .brightness:
            return context.brightness.hardwareMethod(for: display) == .ddc ? Self.ddcInterval : Self.softwareInterval
        case .contrast, .volume, .custom:
            return Self.ddcInterval
        }
    }

    /// The VCP code a DDC control writes; nil for brightness (BrightnessService picks the method).
    static func vcp(_ control: LiveControl) -> UInt8? {
        switch control {
        case .brightness: return nil
        case .contrast: return VCPPolicy.contrast
        case .volume: return VCPPolicy.volume
        case .custom(let code): return code
        }
    }

    private func deliver(_ value: Double, to slot: Slot, final: Bool, context: DisplaysContext) {
        if let code = Self.vcp(slot.control) {
            context.ddc.controller?.setLive(code, value, for: slot.display, final: final)
        } else {
            let snapped = context.brightness.scale(for: slot.display)?.snapped(value) ?? value
            context.brightness.set(snapped, for: slot.display, source: .user)
        }
    }

    /// Sends waiting values when their slot opens; re-arms while anything waits.
    private func scheduleFlush() {
        flush?.cancel()
        flush = nil
        guard let deadline = mailbox.nextDeadline else { return }
        let wait = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flushDue() }
        }
        flush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    private func flushDue() {
        flush = nil
        guard let context else {
            mailbox.removeAll()
            return
        }
        for item in mailbox.due(now: ProcessInfo.processInfo.systemUptime) {
            deliver(item.value, to: item.key, final: false, context: context)
        }
        scheduleFlush()
    }
}
