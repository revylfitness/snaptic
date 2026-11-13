import AppKit
import ApplicationServices
import CoreGraphics
import SnapticKit

/// Dock click actions (lead; PLAN 0.5 §4.11; A5): a listen-only tap on left mouse-down and mouse-up, so a Dock click
/// is never swallowed, feeding K3's `DockClickRules`.
/// - The callback stamps the time and the location and returns; the press is sampled and the resolver run on the
///   next main turn. Nothing reads AX or the window list in the callback (X2-17).
/// - Mouse-down samples the press before the Dock acts: the item under the pointer (the observer's latest selection
///   against the §4.1 hit band), the active app from the activation history, the app's on-screen layer-0 windows and,
///   with Restore all on, its window and minimized counts (the Dock read, off main).
/// - Hide or Minimize runs 100 ms after the mouse-up, after `confirm`; Hide is skipped if the app's on-screen layer-0
///   count grew meanwhile. `Dock.disable.clickActions` is read at each mouse-up the resolver would act on.
/// - macOS disabling the tap is counted by the breaker (three in 60 s turn click actions off until relaunch);
///   otherwise trust is re-checked on the next main turn and the tap re-enabled, or removed when trust is gone.
/// - Counts and enums only reach diagnostics; nothing names an app.
@MainActor
final class DockClickTap {
    /// §4.11, §4.17: until relaunch.
    private(set) static var breaker = DockTapBreaker()

    /// Whether the settings ask for the tap at all.
    static func wanted(_ config: DockConfig) -> Bool {
        config.clickActions != .doNothing || config.restoreAllMinimized
    }

    var config: DockConfig
    /// `DockObserver`'s latest selection, raw (§4.1); the module keeps it current.
    var selection: DockSelection?
    /// The module's pause (§4.17); the VoiceOver pause doesn't stop click actions.
    var pause: DockPauseReason?

    private var tap: DockEventTap?
    private let geometry: @MainActor () -> DockGeometrySnapshot
    private let killSwitch: @MainActor () -> Bool
    private let onStopped: @MainActor (_ tripped: Bool) -> Void
    private var history = DockActivationHistory()
    private var activationToken: NSObjectProtocol?

    /// The press being resolved, with the windows its read found (Restore all).
    private var press: DockClickPress?
    private var pressID = 0
    private var pressItems: [WindowItem] = []
    private var pressReading = false
    /// A mouse-up that came while the press's read was still out: its time and whether it was on the same item.
    private var pendingUp: (at: Double, onSameItem: Bool)?
    private let actTimer = DockOneShot()

    // §4.22: counts and enums only.
    private var skips: [DockClickSkip: Int] = [:]
    private var acted: [DockClickAction: Int] = [:]
    private var restores = 0

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// Nil when the tap can't be created (no Accessibility trust, or macOS refused it).
    init?(config: DockConfig, geometry: @escaping @MainActor () -> DockGeometrySnapshot,
          killSwitch: @escaping @MainActor () -> Bool, onStopped: @escaping @MainActor (_ tripped: Bool) -> Void) {
        self.config = config
        self.geometry = geometry
        self.killSwitch = killSwitch
        self.onStopped = onStopped
        let box = DockTapHandlers()
        guard let tap = DockEventTap(types: [.leftMouseDown, .leftMouseUp], listenOnly: true, handlers: box) else {
            return nil
        }
        self.tap = tap
        box.handler = { [weak self] type, event in
            self?.tapped(type, event)
            return false
        }
        box.onDisabled = { [weak self] in self?.tapDisabled() }
        DockPreviewsModule.liveCount(.clickTap, up: true)
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            history.record(pid: front, at: 0)
        }
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            let at = ProcessInfo.processInfo.systemUptime
            MainActor.assumeIsolated {
                guard let pid else { return }
                self?.history.record(pid: pid, at: at)
            }
        }
        tap.setEnabled(true)
    }

    var isRunning: Bool { tap != nil }

    /// The module stopped, the settings turned click actions off, or trust or the breaker took the tap.
    func stop() {
        actTimer.cancel()
        if let activationToken { NSWorkspace.shared.notificationCenter.removeObserver(activationToken) }
        activationToken = nil
        press = nil
        pendingUp = nil
        pressItems = []
        pressID += 1
        guard let tap else { return }
        tap.invalidate()
        self.tap = nil
        DockPreviewsModule.liveCount(.clickTap, up: false)
    }

    /// §4.22: counts and enums only.
    var diagnosticsLines: [String] {
        let skipped = DockClickSkip.allCases.compactMap { reason in
            skips[reason].map { "\(reason.rawValue) \($0)" }
        }
        return [
            "Click actions: hide \(acted[.hideApp] ?? 0), minimize \(acted[.minimizeWindows] ?? 0), "
                + "restore all \(restores)",
            "Click skips: " + (skipped.isEmpty ? "none" : skipped.joined(separator: ", ")),
        ]
    }

    // MARK: The callback (main run loop)

    /// Stamps and hops; listen-only, so the event always goes on.
    private func tapped(_ type: CGEventType, _ event: CGEvent) {
        let down = type == .leftMouseDown
        guard down || type == .leftMouseUp else { return }
        if down, selection == nil { return }
        let at = Self.now
        let location = event.location
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.mouse(down: down, at: at, location: location) }
        }
    }

    /// Counted in the callout (pure); trust is read and the tap re-enabled or removed on the next main turn.
    private func tapDisabled() {
        let tripped = Self.breaker.disabled(at: Self.now)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let tap = self.tap else { return }
                if tripped {
                    self.stop()
                    EventLog.shared.record(.dock, "dock.breaker.\(DockFeature.clickActions.rawValue)")
                    self.onStopped(true)
                } else if AXIsProcessTrusted() {
                    tap.setEnabled(true)
                } else {
                    self.stop()
                    self.onStopped(false)
                }
            }
        }
    }

    // MARK: Resolving (main)

    private func mouse(down: Bool, at: Double, location: CGPoint) {
        guard tap != nil else { return }
        // The event's location is global with the origin at the primary display's top-left; K2 works in Cocoa's.
        let p = DockPoint(x: Double(location.x), y: Double(Screens.primaryHeight) - Double(location.y))
        if down { mouseDown(at: at, p) } else { mouseUp(at: at, p) }
    }

    /// Whether `p` is on the selected item, and its app's pid when it's a running app.
    private func item(at p: DockPoint) -> (on: Bool, pid: Int32?) {
        guard let s = selection else { return (false, nil) }
        let on = s.itemFrame.contains(p) || DockPreviewRules.hitBand(s, geometry()).contains(p)
        return (on, on && s.showsPanel ? s.pid : nil)
    }

    private func mouseDown(at: Double, _ p: DockPoint) {
        actTimer.cancel()
        pressID += 1
        press = nil
        pendingUp = nil
        pressItems = []
        pressReading = false
        let hit = item(at: p)
        guard hit.on else { return }
        // Only the inputs the resolver can use: the window list only when the app is the active one.
        var visible = 0
        if let pid = hit.pid, config.clickActions != .doNothing,
           history.active(at: at - DockClickRules.activeLead) == pid {
            visible = Self.layer0Count(pid)
        }
        press = DockClickRules.press(at: at, pid: hit.pid, history: history, visibleOnSpace: visible, windowCount: 0,
                                     minimizedCount: 0, action: config.clickActions,
                                     restoreAll: config.restoreAllMinimized)
        guard let pid = hit.pid, config.restoreAllMinimized else { return }
        pressReading = true
        let id = pressID
        Task { @MainActor [weak self] in
            let read = await WindowManager.shared.windows(for: pid)
            self?.pressRead(read.items.filter { !$0.isWindowless }, id: id)
        }
    }

    private func pressRead(_ items: [WindowItem], id: Int) {
        guard id == pressID, pressReading, var press else { return }
        pressReading = false
        pressItems = items
        press.windowCount = items.count
        press.minimizedCount = items.filter(\.isMinimized).count
        self.press = press
        if let up = pendingUp {
            pendingUp = nil
            resolve(press, upAt: up.at, onSameItem: up.onSameItem)
        }
    }

    private func mouseUp(at: Double, _ p: DockPoint) {
        guard let press else { return }
        let hit = item(at: p)
        let same = hit.on && hit.pid != nil && hit.pid == press.pid
        if pressReading {
            pendingUp = (at, same)
            return
        }
        resolve(press, upAt: at, onSameItem: same)
    }

    private func resolve(_ press: DockClickPress, upAt: Double, onSameItem: Bool) {
        self.press = nil
        let decision = DockClickRules.mouseUp(press, at: upAt, onSameItem: onSameItem, history: history, pause: pause,
                                              breakerTripped: Self.breaker.tripped, killSwitch: killSwitch)
        guard let pid = press.pid else {
            count(decision)
            return
        }
        switch decision {
        case let .skip(reason):
            skips[reason, default: 0] += 1
        case .restoreAll:
            restoreAll()
        case let .wait(action, at):
            let baseline = action == .hideApp ? Self.layer0Count(pid) : 0
            actTimer.arm(after: at - Self.now) { [weak self] in
                self?.confirm(press, action, pid: pid, baseline: baseline)
            }
        case let .act(action):
            perform(action, pid: pid)
        }
    }

    private func count(_ decision: DockClickDecision) {
        if case let .skip(reason) = decision { skips[reason, default: 0] += 1 }
    }

    private func confirm(_ press: DockClickPress, _ action: DockClickAction, pid: Int32, baseline: Int) {
        let grew = action == .hideApp && Self.layer0Count(pid) > baseline
        let decision = DockClickRules.confirm(press, action, at: Self.now, history: history, layer0Grew: grew)
        if case let .act(action) = decision {
            perform(action, pid: pid)
        } else {
            count(decision)
        }
    }

    // MARK: Acting

    private func perform(_ action: DockClickAction, pid: Int32) {
        switch action {
        case .doNothing:
            return
        case .hideApp:
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
            app.hide()
        case .minimizeWindows:
            WindowManager.shared.markWindowsDirty(pid)
            Task { @MainActor in
                let read = await WindowManager.shared.windows(for: pid)
                for item in read.items where item.axElement != nil && !item.isWindowless && !item.isMinimized
                    && !item.isFullscreen && !item.isOnOtherSpace {
                    WindowManager.shared.toggleMinimized(item)
                }
            }
        }
        acted[action, default: 0] += 1
    }

    /// Every window was minimized at mouse-down: all of them come back.
    private func restoreAll() {
        for item in pressItems where item.isMinimized && item.axElement != nil {
            WindowManager.shared.toggleMinimized(item)
        }
        pressItems = []
        restores += 1
    }

    /// The app's on-screen layer-0 windows on the current Space (`CGWindowList`, never AX).
    private static func layer0Count(_ pid: Int32) -> Int {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return 0 }
        return list.reduce(0) { n, info in
            let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue
            return owner == pid && layer == 0 ? n + 1 : n
        }
    }
}
