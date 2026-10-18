import AppKit
import Combine
import SnapticKit

// "Restore All Displays" (owner: B). PLAN §4.7 + R5.4: ⌃⌥⌘⎋ (fallback ⌃⌥⌘⇧⎋, or the user's own shortcut
// first; 0.3 §4.6 M6), the menu and the CLI. Reverts modes Snaptic set in the last 60 s, re-enables displays
// Snaptic disabled, runs every PanicParticipant (each feature's own row of the R5.4 panic table), honors
// invariant 8, shows a HUD and sets the latch that pauses automation until Resume.
//
// 0.3 §4.5: page-visible state (latch, shortcut registration) bumps `revision(.diagnostics)`, the revision the
// Confirm display changes section and Display Information observe; menu items are built with MenuKit (§5.1).

fileprivate extension DisplayActionID {
    static let restoreAll = PanicCoordinator.restoreActionID
    static let resumeAutomation = PanicCoordinator.resumeActionID
}

fileprivate extension DisplayMenuItemID {
    static let restoreAll = DisplayMenuItemID(rawValue: "b.restoreAll")
    static let resumeAutomation = DisplayMenuItemID(rawValue: "b.resumeAutomation")
}

/// The panic shortcut setting as PanicCoordinator reads it (publishes only when one of these changes).
private struct PanicShortcutSettings: Equatable {
    let enabled: Bool
    let candidates: [HotkeyCombo]
    init(_ safety: SafetyConfig) {
        enabled = safety.panicHotkeyEnabled
        candidates = safety.panicHotkeyCandidates
    }
}

@MainActor final class PanicCoordinator: DisplayMenuContributor, DiagnosticsContributor, ControlDeclaring {
    typealias Controls = PanicCoordinatorControls

    /// Action ids other files use (F's Resume buttons): `ctx.actions.perform(PanicCoordinator.resumeActionID…)`.
    nonisolated static let restoreActionID = DisplayActionID(rawValue: "b.restoreAll")
    nonisolated static let resumeActionID = DisplayActionID(rawValue: "b.resumeAutomation")
    /// The name the shortcut is registered under (also the `owner` of the Settings shortcut row, so the row
    /// doesn't report its own registration as a conflict).
    static var shortcutOwner: String { L("Restore All Displays") }
    private(set) var isLatched = false
    /// Set by DisplaysModule; called whenever `isLatched` changes.
    var onLatchChanged: (@MainActor () -> Void)?

    /// Features that make the panic shortcut worth registering (geometry, gamma, overlay, virtual).
    static let guardedFeatures: Set<DisplayFeature> = [
        .resolution, .hiddenModes, .scaleMatch, .mainDisplay, .arrangement, .mirroring, .rotation, .underscan,
        .hdrToggle, .disconnect, .autoDisconnectBuiltin, .protection, .layouts,
        .brightnessGamma, .brightnessOverlay, .dimToBlack, .dimOnLock, .xdr, .color, .menuBarOverlays,
        .virtualScreens, .smartHiDPI, .pip,
    ]

    private weak var context: DisplaysContext?
    /// Kept after stop (it outlives module starts) so the last state change still reaches open pages.
    private weak var runtime: DisplaysRuntimeState?
    private var lifetime: Lifetime?
    private var hotkeyLifetime: Lifetime?
    private(set) var registeredHotkey: HotkeyCombo? {
        didSet { if registeredHotkey != oldValue { changed() } }
    }
    private(set) var hotkeyProblem: String? {
        didSet { if hotkeyProblem != oldValue { changed() } }
    }
    /// The candidate list the current registration was made from.
    private var registeredCandidates: [HotkeyCombo] = []
    private var sinks: [AnyCancellable] = []
    private(set) var lastPanicAt: Date?

    init() {}

    /// Registers the panic hotkey and the CLI/menu entry points.
    func start(_ context: DisplaysContext, lifetime: Lifetime) {
        guard self.context == nil else { return }
        self.context = context
        self.lifetime = lifetime
        runtime = context.runtime
        context.preConfirm.attach(context)

        context.actions.register(Action(id: .restoreAll, title: L("Restore All Displays"), feature: .overview,
                                        cliAllowed: true) { [weak self] _ in
            self?.panic(reason: L("Restore All Displays"))
        }, lifetime: lifetime)
        context.actions.register(Action(id: .resumeAutomation, title: L("Resume Display Automation"), feature: .overview,
                                        cliAllowed: true) { [weak self] _ in self?.resume() }, lifetime: lifetime)
        context.commands.register("panic", policy: .low, offOnly: false, cliAllowed: true,
                                  summary: L("Restore all displays and pause display automation"),
                                  lifetime: lifetime) { [weak self] _ in
            guard let self else { return .failure(ControlExit.unavailable, L("Displays are off")) }
            self.panic(reason: L("Command line"))
            return .ok(L("Displays restored. Display automation is paused until `snaptic resume`."))
        }
        context.commands.register("resume", policy: .low, offOnly: false, cliAllowed: true,
                                  summary: L("Resume display automation after Restore All Displays"),
                                  lifetime: lifetime) { [weak self] _ in
            guard let self else { return .failure(ControlExit.unavailable, L("Displays are off")) }
            let was = self.isLatched
            self.resume()
            return .ok(was ? L("Display automation resumed.") : L("Display automation wasn't paused."))
        }
        context.menus.register(self, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Restore All Displays"), lifetime: lifetime)
        context.diagnostics.register(context.privateAPI, section: L("Private interfaces"), lifetime: lifetime)

        context.runtime.$effectiveFeatures
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateHotkey() } }
            .store(in: &sinks)
        // Only the safety section's shortcut fields (0.3 §4.5): other config writes never reach here.
        context.config.$value
            .map { PanicShortcutSettings($0.safety) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.updateHotkey() } }
            .store(in: &sinks)
        updateHotkey()
        changed()
    }

    func stop() {
        sinks.removeAll()
        hotkeyLifetime?.end()
        hotkeyLifetime = nil
        registeredHotkey = nil
        registeredCandidates = []
        hotkeyProblem = nil
        context?.preConfirm.attach(nil)
        context = nil
        lifetime = nil
        changed()
    }

    /// One coalesced publish for the pages that show the latch or the shortcut (0.3 §4.5).
    private func changed() {
        runtime?.revision(.diagnostics).bump()
    }

    // MARK: Hotkey

    /// Registered while a guarded feature is effective and the setting is on — or regardless
    /// of the setting while Snaptic holds a long-armed state (PLAN §4.7). The guard client calls
    /// this when its long-armed state appears or goes away.
    func updateHotkey() {
        guard let ctx = context, let lifetime, !lifetime.isEnded else { return }
        let guarded = !ctx.runtime.effectiveFeatures.isDisjoint(with: Self.guardedFeatures)
        let candidates = guarded ? ctx.config.value.safety.panicHotkeys(longArmed: ctx.guardClient.hasLongState) : []
        // Same list as last time and something registered: nothing to do. A changed list (a new custom combo in
        // front) re-registers from the top, so the user's own combo wins as soon as it is set.
        if registeredHotkey != nil, candidates == registeredCandidates { return }
        registeredCandidates = candidates
        hotkeyLifetime?.end()
        hotkeyLifetime = nil
        registeredHotkey = nil
        guard !candidates.isEmpty else {
            hotkeyProblem = nil
            return
        }
        let life = lifetime.child()
        for combo in candidates {
            do {
                _ = try ctx.hotkeys.register(combo, owner: Self.shortcutOwner, lifetime: life) { [weak self] in
                    self?.panic(reason: L("Keyboard shortcut"))
                }
                hotkeyLifetime = life
                registeredHotkey = combo
                // The user's own combo lost to another app while a default stood in for it (the default's own
                // fallback is the documented behavior, not a problem).
                hotkeyProblem = combo == candidates.first || candidates.first == SafetyConfig.defaultPanicHotkey ? nil
                    : L("\(HotkeyRules.displayString(candidates[0])) is used by another app, so \(HotkeyRules.displayString(combo)) restores your displays instead.")
                return
            } catch {
                continue
            }
        }
        life.end()
        hotkeyProblem = L("Another app uses these shortcuts, so Restore All Displays has none right now.")
        EventLog.shared.record(.safety, "Panic shortcut could not be registered")
    }

    /// "⌃⌥⌘⎋" (diagnostics, menus).
    static func describe(_ combo: HotkeyCombo) -> String { HotkeyRules.displayString(combo) }

    // MARK: Panic

    func panic(reason: String) {
        guard let ctx = context else { return }
        EventLog.shared.record(.safety, "Restore All Displays (\(reason))")
        // 1. Pending trial → Revert; modes Snaptic set in the last 60 s; Snaptic-disabled displays.
        let reverted = ctx.transactions.panicRevert()
        // 2. Each feature's own panic row (overlays, gamma/ColorSync, hosts, streams, sleep, hooks…).
        for participant in ctx.panicParticipants { participant.panicRestore() }
        // 3. Backstops for the always-safe parts (idempotent).
        let effective = ctx.runtime.effectiveFeatures
        if !effective.isDisjoint(with: [.brightnessOverlay, .menuBarOverlays, .xdr, .dimToBlack]) { ctx.overlays.removeAll() }
        if !effective.isDisjoint(with: [.brightnessGamma, .color, .xdr, .dimToBlack, .dimOnLock]) { ctx.gamma.restoreAll() }
        // 4. Latch automation until Resume.
        lastPanicAt = Date()
        let summary = reverted > 0 ? L("Displays restored (\(reverted) changes undone). Display automation is paused.")
                                   : L("Displays restored. Display automation is paused.")
        ctx.runtime.lastPanicSummary = summary
        ctx.toasts.show(summary, action: ToastAction(title: L("Resume")) { [weak self] in self?.resume() })
        setLatched(true)
        changed()
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: summary, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func resume() {
        guard isLatched else { return }
        EventLog.shared.record(.safety, "Display automation resumed")
        setLatched(false)
    }

    private func setLatched(_ on: Bool) {
        guard isLatched != on else { return }
        isLatched = on
        onLatchChanged?()
        changed()
        context?.requestMenuRebuild()
    }

    // MARK: Menu (0.3 §4.8 b.*, §5.2)

    /// Every item id this contributor can produce (R5-13). The 0.2 quick-menu copy is gone (C3).
    static var menuItemIDs: [DisplayMenuItemID] { [.restoreAll, .resumeAutomation] }

    var descriptors: [DisplayMenuItemDescriptor] {
        [DisplayMenuItemDescriptor(id: .restoreAll, title: L("Restore All Displays"), slot: .tools, defaultVisibility: .visible),
         DisplayMenuItemDescriptor(id: .resumeAutomation, title: L("Resume Display Automation"), slot: .tools,
                                   defaultVisibility: .visible)]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] { [] }

    /// The menu builder places these by id (§4.8): Restore All Displays in Display Tools, and at the top level of
    /// the Displays section while a change awaits confirmation; Resume Display Automation under the "Display
    /// automation is paused" status row, produced only while paused.
    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools else { return [] }
        let restore = MenuKit.action(L("Restore All Displays"), symbol: "arrow.uturn.backward.circle",
                                     control: ControlID("menu.display.b.restoreAll")) { [weak self] in
            self?.panic(reason: L("Menu"))
        }
        if let combo = registeredHotkey { restore.toolTip = Self.describe(combo) }
        var items: [(DisplayMenuItemID, NSMenuItem)] = [(.restoreAll, restore)]
        if isLatched {
            items.append((.resumeAutomation, MenuKit.action(L("Resume Display Automation"), symbol: "play.circle",
                                                            control: ControlID("menu.display.b.resume")) { [weak self] in
                self?.resume()
            }))
        }
        return items
    }

    func diagnostics() -> [(String, String)] {
        [("Latched", isLatched ? "yes" : "no"),
         ("Shortcut", registeredHotkey.map(Self.describe) ?? "not registered"),
         ("Participants", "\(context?.panicParticipants.count ?? 0)")]
    }
}
