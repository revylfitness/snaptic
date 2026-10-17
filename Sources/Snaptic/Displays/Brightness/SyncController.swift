import AppKit
import Combine
import SnapticKit

/// Brightness sync (PLAN §6.1 "Sync"): a source display drives the others, absolute or
/// delta, with offsets, a 2% deadband, DDC writes ≥ 3 s apart and a 10 s pause after a
/// manual change on a target. ⇧ on the brightness keys skips sync. External changes on
/// a DDC source are seen only with readback on (R5.8).
@MainActor final class SyncController: DisplayFeatureController, DiagnosticsContributor, DisplayMenuContributor {
    static var id: DisplayControllerID { .sync }
    static var privateSymbols: [PrivateSymbol] { [] }

    static let toggleAction = DisplayActionID(rawValue: "c.syncToggle")
    static let toggleItem = DisplayMenuItemID(rawValue: "c.sync.toggle")

    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private var sinks: [AnyCancellable] = []
    private var states: [DisplayKey: SyncTargetState] = [:]
    private var lastSource: Double?
    private var trailing: [DisplayKey: DispatchWorkItem] = [:]
    /// Set by KeysController for one change (⇧ held).
    private var skipUntil: TimeInterval = 0

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability { .available }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        context.diagnostics.register(self, section: L("Brightness sync"), lifetime: lifetime)
        context.menus.register(self, lifetime: lifetime)
        context.actions.register(Action(id: Self.toggleAction, title: L("Toggle Brightness Sync"), feature: .sync,
                                        cliAllowed: true) { [weak self] _ in self?.togglePaused() }, lifetime: lifetime)
        context.commands.register("toggle sync", policy: .low, offOnly: false, cliAllowed: true,
                                  summary: L("Pause or resume brightness sync"), lifetime: lifetime) { [weak self] _ in
            guard let self else { return .failure(2, L("Displays isn't running")) }
            let paused = self.togglePaused()
            return .ok(paused ? L("Brightness sync paused") : L("Brightness sync on"))
        }
        context.brightness.changeEvents
            .sink { [weak self] change in self?.handle(change) }
            .store(in: &sinks)
        lastSource = sourceKey().flatMap { context.brightness.value(for: $0) }
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {}

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        if old.brightness.syncSource != new.brightness.syncSource || old.brightness.syncMode != new.brightness.syncMode {
            states.removeAll()
            lastSource = sourceKey().flatMap { context?.brightness.value(for: $0) }
        }
        if old.brightness.syncPaused != new.brightness.syncPaused { context?.requestMenuRebuild() }
    }

    func stop() {
        sinks.removeAll()
        trailing.values.forEach { $0.cancel() }
        trailing.removeAll()
        states.removeAll()
        lastSource = nil
        lifetime = nil
        context = nil
    }

    /// The next brightness change on the source doesn't sync (⇧ held on a key press).
    func skipNextChange() { skipUntil = ProcessInfo.processInfo.systemUptime + 0.5 }

    var isPaused: Bool { context?.config.value.brightness.syncPaused ?? false }

    @discardableResult
    func togglePaused() -> Bool {
        guard let context else { return false }
        context.config.value.brightness.syncPaused.toggle()
        let paused = context.config.value.brightness.syncPaused
        VoiceOverAnnouncer.announce(paused ? L("Brightness sync paused") : L("Brightness sync on"))
        return paused
    }

    /// The configured source, or the built-in display.
    func sourceKey() -> DisplayKey? {
        guard let context else { return nil }
        let online = context.registry.displays.filter { $0.isOnline }
        if let chosen = context.config.value.brightness.syncSource, online.contains(where: { $0.key == chosen }) { return chosen }
        return online.first(where: \.isBuiltin)?.key
    }

    private func handle(_ change: BrightnessService.Change) {
        guard let context, !isPaused else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let source = sourceKey()
        if change.key != source {
            // A user change on a target pauses syncing that target for 10 s.
            if change.source == .user || change.source == .keys || change.source == .cli {
                states[change.key, default: SyncTargetState()].lastManualAt = now
            }
            return
        }
        guard change.source != .sync else { return }
        if change.source == .automation && !context.config.value.brightness.syncExternalChanges {
            lastSource = change.value
            return
        }
        if change.source == .restore || now < skipUntil {
            lastSource = change.value
            return
        }
        let previous = lastSource
        lastSource = change.value
        let config = context.config.value
        for display in context.registry.displays where display.isOnline && display.key != change.key {
            let per = config.perDisplay[display.key]?.brightness ?? PerDisplayBrightness()
            guard per.syncEnabled, let current = context.brightness.value(for: display.key) else { continue }
            let range = context.brightness.range(for: display.key)
            let target = SyncMath.target(source: min(1, change.value), previousSource: previous.map { min(1, $0) },
                                         targetCurrent: min(1, current), offset: per.syncOffset, mode: config.brightness.syncMode,
                                         range: 0...min(1, range.upperBound))
            write(target, to: display.key, now: now)
        }
    }

    private func write(_ value: Double, to key: DisplayKey, now: TimeInterval) {
        guard let context else { return }
        let isDDC = context.brightness.hardwareMethod(for: key) == .ddc
        var state = states[key] ?? SyncTargetState()
        trailing[key]?.cancel()
        trailing[key] = nil
        if SyncMath.shouldWrite(value, state: state, now: now, isDDC: isDDC) {
            context.brightness.set(value, for: key, source: .sync)
            SyncMath.didWrite(value, state: &state, now: now)
            states[key] = state
        } else if let at = SyncMath.nextWriteTime(value, state: state, now: now, isDDC: isDDC) {
            // Rate-limited: write the latest value once the window opens.
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.trailing[key] = nil
                    self.write(value, to: key, now: ProcessInfo.processInfo.systemUptime)
                }
            }
            trailing[key] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, at - now), execute: work)
        }
    }

    // MARK: Menu

    var descriptors: [DisplayMenuItemDescriptor] {
        [DisplayMenuItemDescriptor(id: Self.toggleItem, title: L("Brightness sync"), slot: .tools, defaultVisibility: .visible)]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] { [] }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools else { return [] }
        return [(Self.toggleItem, CMenu.item(L("Sync Brightness"), on: !isPaused) { [weak self] in self?.togglePaused() })]
    }

    func diagnostics() -> [(String, String)] {
        guard let context else { return [] }
        let source = sourceKey().flatMap { key in context.registry.displays.firstIndex { $0.key == key } }
        return [("Source", source.map { "display \($0 + 1)" } ?? "none"),
                ("Mode", context.config.value.brightness.syncMode.rawValue),
                ("Paused", isPaused ? "yes" : "no"),
                ("Targets tracked", String(states.count))]
    }
}
