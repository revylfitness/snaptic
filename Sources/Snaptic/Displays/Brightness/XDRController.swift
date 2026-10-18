import AppKit
import Combine
import SnapticKit

/// XDR extra brightness (PLAN §6.4, Beta): per display, when EDR potential > 1. Picks
/// method A (overlay) or B (gamma) from what's effective and what calibration said,
/// extends the brightness slider above 100%, registers toggle / XDR ± actions, the
/// `toggle xdr` verb, menu toggles with a paused badge, and the auto-pause toast.
@MainActor final class XDRController: DisplayFeatureController, PanicParticipant, DiagnosticsContributor {
    static var id: DisplayControllerID { .xdr }
    static var privateSymbols: [PrivateSymbol] { [] }

    static let toggleAction = DisplayActionID(rawValue: "c.xdrToggle")
    static let upAction = DisplayActionID(rawValue: "c.xdrUp")
    static let downAction = DisplayActionID(rawValue: "c.xdrDown")
    static var observedSections: Set<DisplaysConfigSection> { [.brightness, .perDisplayBrightness] }

    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private var sinks: [AnyCancellable] = []
    private var menuItems: ColorMenuItems?
    /// Displays whose brightness is above 100% (boosted), as last seen.
    private var aboveSDR: Set<DisplayKey> = []

    init() {}

    /// Static host facts only: displays come and go, so whether one has EDR headroom is
    /// checked per display in `EDRBoost.xdrMethod` (menus, toggles, keys and the slider).
    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability {
        if let reason = AffectedModels.xdrUnavailableReason(HostInfo.current) { return .unavailable(reason) }
        return .available
    }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        context.registerPanic(self, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Extra brightness"), lifetime: lifetime)
        let items = ColorMenuItems(context: context, part: .xdr, owner: self)
        menuItems = items
        context.menus.register(items, lifetime: lifetime)
        context.edr.onPauseChange = { [weak self] reason in
            guard let self, let ctx = self.context else { return }
            if let reason {
                ctx.toasts.show(L("Extra brightness paused: ") + reason, lifetime: self.lifetime)
            }
            ctx.runtime.revision(.xdr).bump()
            ctx.requestMenuRebuild()
        }
        context.edr.onCalibrated = { [weak self] key in
            self?.apply(key)
            self?.context?.runtime.revision(.xdr).bump()
        }
        registerActions(context, lifetime: lifetime)
        context.commands.register("toggle xdr", policy: .low, offOnly: false, cliAllowed: true,
                                  summary: L("Toggle extra brightness: toggle xdr [display]"),
                                  lifetime: lifetime) { [weak self] request, _ in
            guard let self, let ctx = self.context else { return DisplayTargets.notRunning() }
            let usage = L("Usage: toggle xdr [display]. ") + DisplayTargets.usage
            let (parsed, error) = DisplayTargets.cliArguments(request.arguments, valueCount: 0, usage: usage, ctx)
            guard let parsed else { return error ?? .failure(ControlExit.usage, usage) }
            guard ctx.runtime.isEffective(.xdr) else { return .failure(ControlExit.unavailable, L("Extra brightness is off")) }
            let changed = self.toggle(parsed.target)
            return changed ? .ok() : .failure(ControlExit.notFound, L("No display with extra brightness matches"))
        }
        context.commands.register("get xdr", policy: .read, offOnly: false, cliAllowed: true,
                                  summary: L("Print extra brightness per display: get xdr [display]"),
                                  lifetime: lifetime) { [weak self] request, _ in
            guard let self, let ctx = self.context else { return DisplayTargets.notRunning() }
            let usage = L("Usage: get xdr [display]. ") + DisplayTargets.usage
            let (parsed, error) = DisplayTargets.cliArguments(request.arguments, valueCount: 0, default: .all, usage: usage, ctx)
            guard let parsed else { return error ?? .failure(ControlExit.usage, usage) }
            guard ctx.runtime.isEffective(.xdr) else { return .failure(ControlExit.unavailable, L("Extra brightness is off")) }
            let rows = DisplayTargets.resolve(parsed.target, ctx).compactMap { d -> (display: DisplayInfo, text: [String], json: [String: Any])? in
                let (method, _) = self.method(for: d.key)
                guard let method else { return nil }
                let on = self.isEnabled(d.key)
                let boost = Int((ctx.edr.isBoosting(d.key) ? ctx.edr.appliedBoost(d.key) : 1) * 100)
                var state = on ? "on" : "off"
                if on, ctx.edr.pauseReason != nil { state = "paused" }
                var json: [String: Any] = ["xdr": state, "boost": boost, "method": method.rawValue]
                if let reason = ctx.edr.pauseReason, on { json["pausedBecause"] = reason }
                return (d, [state, "\(boost)%", method.rawValue], json)
            }
            return DisplayTargets.rows(rows, json: request.json, none: L("No display with extra brightness matches"), ctx)
        }
        context.registry.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.applyAll() } }
            .store(in: &sinks)
        context.brightness.changeEvents
            .filter { $0.source != .restore }
            .sink { [weak self] change in self?.brightnessChanged(change) }
            .store(in: &sinks)
        applyAll()
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) { applyAll() }

    /// The Extra Brightness item and pages show whether a display is boosted: refresh them when that flips (the
    /// slider itself follows `DisplayRuntime`).
    private func brightnessChanged(_ change: BrightnessService.Change) {
        let above = change.value > 1.0001
        guard above != aboveSDR.contains(change.key) else { return }
        if above { aboveSDR.insert(change.key) } else { aboveSDR.remove(change.key) }
        context?.runtime.revision(.xdr).bump()
        context?.requestMenuRebuild()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        if old.brightness.xdrMaxScale != new.brightness.xdrMaxScale || old.brightness.xdrMethod != new.brightness.xdrMethod
            || old.perDisplay.values.mapValues(\.brightness) != new.perDisplay.values.mapValues(\.brightness) {
            applyAll()
        }
    }

    func stop() {
        sinks.removeAll()
        if let context {
            context.edr.onPauseChange = nil
            context.edr.removeAll()
            for d in context.registry.displays {
                context.brightness.setXDR(enabled: false, max: 1, method: .overlay, for: d.key)
            }
        }
        context?.edr.onCalibrated = nil
        menuItems = nil
        aboveSDR.removeAll()
        lifetime = nil
        context = nil
    }

    func panicRestore() {
        context?.edr.removeAll()
        guard let context else { return }
        for d in context.registry.displays { context.brightness.setXDR(enabled: false, max: 1, method: .overlay, for: d.key) }
    }

    // MARK: Method choice (in EDRBoost, so pages can reach it)

    func method(for key: DisplayKey) -> (EDRBoost.Method?, String) {
        context?.edr.xdrMethod(for: key) ?? (nil, L("Not running"))
    }

    func isEnabled(_ key: DisplayKey) -> Bool { context?.config.value.perDisplay[key]?.brightness.xdrEnabled ?? false }

    private func applyAll() {
        guard let context else { return }
        for display in context.registry.displays where display.isOnline { apply(display.key) }
        context.runtime.revision(.xdr).bump()
        context.requestMenuRebuild()
    }

    private func apply(_ key: DisplayKey) {
        guard let context else { return }
        let (method, _) = method(for: key)
        if let method, isEnabled(key), context.edr.calibrating == nil {
            context.brightness.setXDR(enabled: true, max: context.edr.maxBoost(for: key), method: method, for: key)
        } else if context.edr.calibrating?.key != key {
            context.brightness.setXDR(enabled: false, max: 1, method: method ?? .overlay, for: key)
        }
    }

    // MARK: Actions

    @discardableResult
    func toggle(_ target: DisplayTarget) -> Bool {
        guard let context else { return false }
        var changed = false
        for display in DisplayTargets.resolve(target, context) where method(for: display.key).0 != nil {
            let on = !isEnabled(display.key)
            PerDisplayEdit.update(context, display.key) { $0.brightness.xdrEnabled = on }
            changed = true
            if context.runtime.isEffective(.osd) {
                context.osd.show(.xdr, text: on ? L("Extra brightness on") : L("Extra brightness off"), on: display.desktopID)
            }
            VoiceOverAnnouncer.announce(on ? L("Extra brightness on") : L("Extra brightness off"))
        }
        return changed
    }

    private func step(_ target: DisplayTarget, up: Bool) {
        guard let context else { return }
        for display in DisplayTargets.resolve(target, context) where isEnabled(display.key) {
            guard let value = context.brightness.value(for: display.key) else { continue }
            let stepSize = context.config.value.keys.step(fine: false)
            // XDR ± move within the boosted range: below 100% they start at 100%.
            let next = up ? max(1, value) + stepSize : max(1, value - stepSize)
            context.brightness.set(next, for: display.key, source: .user)
            Feedback.brightness(context, display)
        }
    }

    private func registerActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.actions.register(Action(id: Self.toggleAction, title: L("Extra Brightness On or Off"), feature: .xdr,
                                    cliAllowed: true) { [weak self] target in self?.toggle(target) }, lifetime: lifetime)
        ctx.actions.register(Action(id: Self.upAction, title: L("Extra Brightness Up"), feature: .xdr,
                                    cliAllowed: true) { [weak self] target in self?.step(target, up: true) }, lifetime: lifetime)
        ctx.actions.register(Action(id: Self.downAction, title: L("Extra Brightness Down"), feature: .xdr,
                                    cliAllowed: true) { [weak self] target in self?.step(target, up: false) }, lifetime: lifetime)
    }

    // MARK: Menu


    // MARK: Diagnostics

    func diagnostics() -> [(String, String)] {
        guard let context else { return [] }
        var rows: [(String, String)] = [("Paused", context.edr.pauseReason ?? "no")]
        for (index, d) in context.registry.displays.filter({ $0.isOnline }).enumerated() {
            let (m, reason) = method(for: d.key)
            rows.append(("Display \(index + 1)",
                         String(format: "potential %.2f, headroom %.2f, ", context.edr.potential(for: d.key), context.edr.headroom(for: d.key))
                            + "\(isEnabled(d.key) ? "on" : "off"), method \(m?.rawValue ?? "none") (\(reason))"))
        }
        return rows
    }
}
