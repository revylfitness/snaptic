import AppKit
import Combine
import SnapticKit

/// Software color adjustments (PLAN §2.1 `color`, parity §5.1): contrast, gamma (+RGB),
/// gain (+RGB), temperature, black/white levels and invert, composed by the gamma
/// service. Actions for ±, invert, reset and suspend; CLI `set gamma`, `set temperature`,
/// `set software-contrast`, `color reset|invert|suspend`; a Color submenu per display.
/// Panic restores ColorSync; adjustments come back on the next change or after Resume.
@MainActor final class ColorController: DisplayFeatureController, PanicParticipant, DiagnosticsContributor,
    DisplayMenuContributor {
    static var id: DisplayControllerID { .color }
    static var privateSymbols: [PrivateSymbol] { [] }

    static var observedSections: Set<DisplaysConfigSection> { [.color, .perDisplayColor] }

    enum Control: String, CaseIterable {
        case gamma, contrast, temperature

        var title: String {
            switch self {
            case .gamma: return L("Gamma")
            case .contrast: return L("Contrast (software)")
            case .temperature: return L("Color Temperature")
            }
        }
    }

    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private var sinks: [AnyCancellable] = []
    /// After a panic nothing is re-applied until the user changes something or resumes.
    private var heldByPanic = false
    /// Restore "off" or Safe Mode: saved adjustments wait for the user's next change.
    private var heldAtLaunch = false
    private var menuItems: ColorMenuItems?

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability {
        if AffectedModels.gammaIsUnreliable(HostInfo.current) { return .unavailable(AffectedModels.reason(.gammaNoOp)) }
        return .available
    }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        context.registerPanic(self, lifetime: lifetime)
        context.gamma.colorController = self
        context.diagnostics.register(self, section: L("Color adjustments"), lifetime: lifetime)
        let items = ColorMenuItems(context: context, part: .color, owner: self)
        menuItems = items
        context.menus.register(items, lifetime: lifetime)
        registerActions(context, lifetime: lifetime)
        registerCommands(context, lifetime: lifetime)
        let restore = context.config.value.brightness.restoreMode
        heldAtLaunch = context.safeMode.isActive || (restore == .off && context.runtime.isEffective(.brightnessRestore))
        context.registry.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.applyAll() } }
            .store(in: &sinks)
        context.runtime.$isPanicLatched
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] latched in
                MainActor.assumeIsolated {
                    if !latched {
                        self?.heldByPanic = false
                        self?.applyAll()
                    }
                }
            }
            .store(in: &sinks)
        applyAll()
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) { applyAll() }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        let a = old.perDisplay.values.mapValues(\.color), b = new.perDisplay.values.mapValues(\.color)
        if a != b || old.color != new.color {
            heldByPanic = false
            heldAtLaunch = false
            applyAll()
            context?.requestMenuRebuild()
        }
    }

    func stop() {
        sinks.removeAll()
        if context?.gamma.colorController === self { context?.gamma.colorController = nil }
        if let context {
            for d in context.registry.displays { context.gamma.setAdjustments(ColorAdjustments(), for: d.key) }
        }
        menuItems = nil
        lifetime = nil
        context = nil
    }

    func panicRestore() {
        heldByPanic = true
        guard let context else { return }
        for d in context.registry.displays { context.gamma.setAdjustments(ColorAdjustments(), for: d.key) }
        context.colorSync.restoreAll()
        context.runtime.revision(.color).bump()
    }

    // MARK: Applying

    /// Whether adjustments can apply to a display (gamma-capable, not a mirror target).
    func canAdjust(_ display: DisplayInfo) -> Bool {
        guard let context, display.isOnline, display.mirrorOf == nil else { return false }
        guard display.isBuiltin || display.transport == .wired || display.isSmartHiDPIPair else { return false }
        return context.gamma.isAllowed && !context.gamma.hasGivenUp(display.key)
    }

    func reasonUnavailable(_ display: DisplayInfo) -> String? {
        guard let context else { return nil }
        if context.gamma.blockedByCustomProfile { return L("A custom color profile is active (see the safeguard below).") }
        if display.mirrorOf != nil { return L("Mirrored displays follow their source.") }
        if !(display.isBuiltin || display.transport == .wired || display.isSmartHiDPIPair) {
            return L("Color tables don't apply to this connection.")
        }
        if context.gamma.hasGivenUp(display.key) { return L("Another app keeps changing this display's colors.") }
        return nil
    }

    private func applyAll() {
        // Pages show whether adjustments apply now (held, safeguard, give-up), so they refresh on every pass.
        context?.runtime.revision(.color).bump()
        guard let context, !heldByPanic, !heldAtLaunch else { return }
        let config = context.config.value
        for display in context.registry.displays where display.isOnline {
            let per = config.perDisplay[display.key]?.color ?? PerDisplayColor()
            let adjustments = canAdjust(display) ? per.effectiveAdjustments(suspendAll: config.color.suspendAll) : ColorAdjustments()
            context.gamma.setAdjustments(adjustments, for: display.key)
        }
    }

    func adjustments(_ key: DisplayKey) -> ColorAdjustments {
        context?.config.value.perDisplay[key]?.color.adjustments ?? ColorAdjustments()
    }

    func update(_ key: DisplayKey, _ body: (inout ColorAdjustments) -> Void) {
        guard let context else { return }
        PerDisplayEdit.update(context, key) { per in
            var a = per.color.adjustments
            body(&a)
            per.color.adjustments = a.sanitized()
        }
    }

    // MARK: Actions

    private func step(_ control: Control, _ target: DisplayTarget, sign: Double, fine: Bool) {
        guard let context else { return }
        let config = context.config.value.color
        let factor = fine ? 0.25 : 1
        for display in DisplayTargets.resolve(target, context) where canAdjust(display) {
            update(display.key) { a in
                switch control {
                case .gamma: a.gamma += sign * config.shortcutStep * 2 * factor
                case .contrast: a.contrast += sign * config.shortcutStep * factor
                case .temperature: a.temperature += sign * config.temperatureStep * factor
                }
            }
            let a = adjustments(display.key)
            let text: String
            switch control {
            case .gamma: text = String(format: "%@ %.2f", L("Gamma"), a.gamma)
            case .contrast: text = String(format: "%@ %.0f%%", L("Contrast"), a.contrast * 100)
            case .temperature: text = String(format: "%.0f K", a.temperature)
            }
            if context.runtime.isEffective(.osd) {
                context.osd.show(control == .contrast ? .contrast : .nightShift, text: text, on: display.desktopID)
            }
            VoiceOverAnnouncer.announce(text)
        }
    }

    func toggleInvert(_ target: DisplayTarget) {
        guard let context else { return }
        for display in DisplayTargets.resolve(target, context) where canAdjust(display) {
            update(display.key) { $0.inverted.toggle() }
        }
    }

    func reset(_ target: DisplayTarget) {
        guard let context else { return }
        for display in DisplayTargets.resolve(target, context) {
            PerDisplayEdit.update(context, display.key) { per in
                let brightness = per.color.adjustments.brightness
                per.color.adjustments = ColorAdjustments()
                per.color.adjustments.brightness = brightness
                per.color.suspended = false
            }
        }
    }

    func toggleSuspend(_ target: DisplayTarget) {
        guard let context else { return }
        if target == .all {
            context.config.value.color.suspendAll.toggle()
            return
        }
        for display in DisplayTargets.resolve(target, context) {
            PerDisplayEdit.update(context, display.key) { $0.color.suspended.toggle() }
        }
    }

    private func registerActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        for control in Control.allCases {
            for (suffix, sign, fine) in [("Up", 1.0, false), ("Down", -1.0, false), ("UpFine", 1.0, true), ("DownFine", -1.0, true)] {
                let id = DisplayActionID(rawValue: "c.\(control.rawValue)\(suffix)")
                let direction = sign > 0 ? L("Up") : L("Down")
                let title = control.title + " " + direction + (fine ? L(" (Fine)") : "")
                ctx.actions.register(Action(id: id, title: title, feature: .color, cliAllowed: true) { [weak self] target in
                    self?.step(control, target, sign: sign, fine: fine)
                }, lifetime: lifetime)
            }
        }
        ctx.actions.register(Action(id: DisplayActionID(rawValue: "c.invert"), title: L("Invert Colors"), feature: .color,
                                    cliAllowed: true) { [weak self] t in self?.toggleInvert(t) }, lifetime: lifetime)
        ctx.actions.register(Action(id: DisplayActionID(rawValue: "c.colorReset"), title: L("Reset Color Adjustments"),
                                    feature: .color, cliAllowed: true) { [weak self] t in self?.reset(t) }, lifetime: lifetime)
        ctx.actions.register(Action(id: DisplayActionID(rawValue: "c.colorSuspend"), title: L("Suspend Color Adjustments"),
                                    feature: .color, cliAllowed: true) { [weak self] t in self?.toggleSuspend(t) }, lifetime: lifetime)
    }

    private func registerCommands(_ ctx: DisplaysContext, lifetime: Lifetime) {
        let setters: [(String, String, ClosedRange<Double>, WritableKeyPath<ColorAdjustments, Double>)] = [
            ("set gamma", L("Set software gamma: set gamma 1.2 [display] (0.5–2)"), ColorAdjustments.gammaRange, \.gamma),
            ("set temperature", L("Set color temperature: set temperature 5000 [display] (1900–10000 K)"),
             ColorAdjustments.temperatureRange, \.temperature),
            ("set software-contrast", L("Set software contrast: set software-contrast 1.1 [display] (0.5–1.5)"),
             ColorAdjustments.contrastRange, \.contrast),
        ]
        for (verb, summary, range, path) in setters {
            ctx.commands.register(verb, policy: .low, offOnly: false, cliAllowed: true, summary: summary,
                                  lifetime: lifetime) { [weak self] request in
                guard let self, let ctx = self.context else { return DisplayTargets.notRunning() }
                let usage = L("Usage: ") + summary
                let (parsed, error) = DisplayTargets.cliArguments(request.arguments, valueCount: 1, usage: usage, ctx)
                guard let parsed else { return error ?? .failure(ControlExit.usage, usage) }
                guard let value = Double(parsed.values[0]), value.isFinite else { return .failure(ControlExit.usage, usage) }
                guard ctx.runtime.isEffective(.color) else { return .failure(ControlExit.unavailable, L("Color adjustments are off")) }
                let displays = DisplayTargets.resolve(parsed.target, ctx).filter { self.canAdjust($0) }
                guard !displays.isEmpty else { return .failure(ControlExit.notFound, L("No display with color adjustments matches")) }
                let clamped = min(range.upperBound, max(range.lowerBound, value))
                for d in displays { self.update(d.key) { $0[keyPath: path] = clamped } }
                guard request.json else { return .ok() }
                let field = String(verb.dropFirst(4))
                let rows = displays.map { d -> (display: DisplayInfo, text: [String], json: [String: Any]) in
                    (d, [], [field: clamped])
                }
                return DisplayTargets.rows(rows, json: true, none: L("No display with color adjustments matches"), ctx)
            }
        }
        ctx.commands.register("color", policy: .low, offOnly: false, cliAllowed: true,
                              summary: L("color reset|invert|suspend [display]"), lifetime: lifetime) { [weak self] request in
            guard let self, let ctx = self.context else { return DisplayTargets.notRunning() }
            let usage = L("Usage: color reset|invert|suspend [display]")
            let (parsed, error) = DisplayTargets.cliArguments(request.arguments, valueCount: 1, usage: usage, ctx)
            guard let parsed else { return error ?? .failure(ControlExit.usage, usage) }
            guard ctx.runtime.isEffective(.color) else { return .failure(ControlExit.unavailable, L("Color adjustments are off")) }
            guard !DisplayTargets.resolve(parsed.target, ctx).isEmpty else {
                return .failure(ControlExit.notFound, L("No display matches"))
            }
            switch parsed.values[0].lowercased() {
            case "reset": self.reset(parsed.target)
            case "invert": self.toggleInvert(parsed.target)
            case "suspend": self.toggleSuspend(parsed.target)
            default: return .failure(ControlExit.usage, usage)
            }
            return .ok()
        }
    }

    // MARK: Menu

    /// The items moved to `ColorMenuItems` (R5-13), registered in start(). The conformance stays only while
    /// `DisplaysModule.menuContributorTypes` lists this type; it contributes nothing itself.
    var descriptors: [DisplayMenuItemDescriptor] { [] }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] { [] }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] { [] }

    func diagnostics() -> [(String, String)] {
        guard let context else { return [] }
        var rows: [(String, String)] = [
            ("Held", heldByPanic ? "after Restore All" : (heldAtLaunch ? "until the next change" : "no")),
            ("Suspend all", context.config.value.color.suspendAll ? "yes" : "no"),
            ("Custom profile safeguard", context.gamma.blockedByCustomProfile ? "active" : "inactive"),
        ]
        for (index, d) in context.registry.displays.filter({ $0.isOnline }).enumerated() {
            let a = adjustments(d.key)
            rows.append(("Display \(index + 1)", a.isIdentity ? "neutral"
                            : String(format: "gamma %.2f contrast %.2f %.0f K%@", a.gamma, a.contrast, a.temperature,
                                     a.inverted ? " inverted" : "")))
        }
        return rows
    }
}
