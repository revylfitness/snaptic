import AppKit
import ApplicationServices
import SnapticKit

/// "Gather windows here" (PLAN §9.4, R5.7): moves every standard window of every regular
/// app onto one display, cascaded inside its visible area. Needs Accessibility (asked
/// through PermissionFlow on use); a shortcut-triggered gather asks for confirmation in a
/// toast first. Never offered to the CLI.
@MainActor final class WindowGatherer {
    private let permissions: PermissionFlow
    private let toasts: ToastPresenter
    private var running = false

    /// Seconds one app may take; slow apps are skipped, never waited on.
    nonisolated static let perAppBudget: Double = 0.5
    nonisolated static let totalBudget: Double = 4
    nonisolated static let cascade: CGFloat = 26
    nonisolated static let maxWindowsPerApp = 50

    init(permissions: PermissionFlow, toasts: ToastPresenter) {
        self.permissions = permissions
        self.toasts = toasts
    }

    /// The display under the pointer (the menu's own display when chosen from a menu).
    static var pointerScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// `confirm`: triggered by a shortcut, so ask first (R5.7). `lifetime`: the caller's;
    /// a confirmation can't run after it ends.
    func gather(onto screen: NSScreen?, confirm: Bool, lifetime: Lifetime) {
        guard let screen = screen ?? Self.pointerScreen, !lifetime.isEnded else { return }
        guard permissions.state(.accessibility) == .granted else {
            // Asked for by the user (menu or shortcut): always show the guide.
            permissions.presentGuide(.accessibility, reason: L("Gather windows moves other apps' windows."))
            return
        }
        let name = TextSanitizer.clean(screen.localizedName, maxScalars: 64)
        if confirm {
            toasts.show(L("Move all windows to ") + name + "?",
                        action: ToastAction(title: L("Gather")) { [weak self, weak screen] in
                            guard let self, let screen else { return }
                            self.perform(onto: screen)
                        },
                        lifetime: lifetime)
        } else {
            perform(onto: screen)
        }
    }

    private func perform(onto screen: NSScreen) {
        guard !running else { return }
        running = true
        // AX works in global coordinates with a top-left origin on the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let visible = screen.visibleFrame
        let target = CGRect(x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isHidden }
            .map { $0.processIdentifier }
        Task { @MainActor [weak self] in
            let moved = await Task.detached(priority: .userInitiated) {
                WindowGatherer.move(pids: pids, into: target)
            }.value
            guard let self else { return }
            self.running = false
            EventLog.shared.record(.switcher, "Gathered \(moved) windows")
            self.toasts.show(moved == 1 ? L("Moved 1 window.") : L("Moved ") + String(moved) + L(" windows."))
        }
    }

    /// Off main: AX calls can block on a busy app.
    nonisolated private static func move(pids: [pid_t], into target: CGRect) -> Int {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(totalBudget * 1_000_000_000)
        var moved = 0
        var offset: CGFloat = 0
        for pid in pids {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { break }
            let appDeadline = min(deadline, now + UInt64(perAppBudget * 1_000_000_000))
            func outOfTime() -> Bool { DispatchTime.now().uptimeNanoseconds > appDeadline }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, WindowManager.axTimeout)
            for window in AX.elements(app, kAXWindowsAttribute).prefix(maxWindowsPerApp) {
                if outOfTime() { break }
                AXUIElementSetMessagingTimeout(window, WindowManager.axTimeout)
                guard AX.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      AX.bool(window, kAXMinimizedAttribute) != true,
                      AX.bool(window, "AXFullScreen") != true,
                      let position = AX.position(window), let size = AX.size(window) else { continue }
                let frame = CGRect(origin: position, size: size)
                if target.contains(CGPoint(x: frame.midX, y: frame.midY)) { continue }
                var newSize = CGSize(width: min(size.width, target.width), height: min(size.height, target.height))
                if newSize.width < 40 || newSize.height < 40 { newSize = size }
                if offset + newSize.width > target.width || offset + newSize.height > target.height { offset = 0 }
                if newSize != size { AX.setSize(window, newSize) }
                if AX.setPosition(window, CGPoint(x: target.minX + offset, y: target.minY + offset)) {
                    moved += 1
                    offset += cascade
                }
            }
        }
        return moved
    }
}
