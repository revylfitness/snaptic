import AppKit
import Combine
import SnapticKit
import SnapticShims

/// System color features (PLAN §6.5): ColorSync profile picker and actions (with the
/// custom-profile warning), Night Shift toggle and strength, Apple display presets, and
/// the built-in auto-brightness toggle.
@MainActor final class SystemColorsController: DisplayFeatureController, DiagnosticsContributor {
    static var id: DisplayControllerID { .systemColors }
    static var privateSymbols: [PrivateSymbol] { [] }

    static var observedSections: Set<DisplaysConfigSection> { [] }
    static let nightShiftAction = DisplayActionID(rawValue: "c.nightShiftToggle")
    static let nightShiftUpAction = DisplayActionID(rawValue: "c.nightShiftUp")
    static let nightShiftDownAction = DisplayActionID(rawValue: "c.nightShiftDown")

    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private var effective: Set<DisplayFeature> = []
    private(set) var nightShiftOn: Bool?
    private(set) var nightShiftStrength: Double?
    private var menuItems: ColorMenuItems?

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability {
        switch feature {
        case .nightShift:
            return SNNightShift.isAvailable() ? .available : .unavailable(L("Night Shift isn’t available on this Mac"))
        case .applePresets:
            return SNMonitorPanel.isAvailable() && context.privateAPI.monitorPanelSupports("presets") ? .available
                : .unavailable(L("Apple display presets aren’t available"))
        case .autoBrightness:
            return context.privateAPI.availability(of: .dsHasAmbientLight)
        default:
            return .available
        }
    }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        context.diagnostics.register(self, section: L("System colors"), lifetime: lifetime)
        context.colorSync.systemColors = self
        let items = ColorMenuItems(context: context, part: .systemColors, owner: self)
        menuItems = items
        context.menus.register(items, lifetime: lifetime)
        context.colorSync.onProfilesChanged = { [weak self] in
            self?.context?.runtime.revision(.systemColors).bump()
            self?.context?.requestMenuRebuild()
        }
        registerNightShift(context, lifetime: lifetime)
        refreshNightShift()
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        self.effective = effective
        refreshNightShift()
        context?.runtime.revision(.systemColors).bump()
        context?.requestMenuRebuild()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {}

    func stop() {
        context?.colorSync.onProfilesChanged = nil
        if context?.colorSync.systemColors === self { context?.colorSync.systemColors = nil }
        menuItems = nil
        lifetime = nil
        context = nil
    }

    // MARK: Profiles

    /// Applies a profile; non-factory profiles first warn about the safeguard (UI-triggered only).
    func applyProfile(_ profile: ColorProfileInfo?, to key: DisplayKey, confirm: Bool = true) {
        guard let context else { return }
        if let profile, confirm, !context.config.value.color.allowGammaWithCustomProfile {
            let alert = NSAlert()
            alert.messageText = L("Use “\(TextSanitizer.clean(profile.name, maxScalars: 64))”?")
            alert.informativeText = L("While a custom color profile is active, color-table dimming and color adjustments move to overlay dimming or turn off on all displays (a macOS black-screen bug). You can override this in Color settings.")
            alert.addButton(withTitle: L("Use Profile"))
            alert.addButton(withTitle: L("Cancel"))
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        if !context.colorSync.setProfile(profile?.url, for: key) {
            context.toasts.show(L("macOS didn’t accept that color profile."), lifetime: lifetime)
        }
        context.gamma.refreshSafeguard()
        context.runtime.revision(.systemColors).bump()
    }

    // MARK: Night Shift

    func refreshNightShift() {
        let on: Bool?
        let strength: Double?
        if effective.contains(.nightShift) {
            on = SNNightShift.enabledState()?.boolValue
            strength = SNNightShift.currentStrength()?.doubleValue
        } else {
            on = nil
            strength = nil
        }
        guard on != nightShiftOn || strength != nightShiftStrength else { return }
        nightShiftOn = on
        nightShiftStrength = strength
        context?.runtime.revision(.systemColors).bump()
    }

    @discardableResult
    func toggleNightShift() -> Bool? {
        guard effective.contains(.nightShift) else { return nil }
        let on = !(SNNightShift.enabledState()?.boolValue ?? false)
        guard SNNightShift.setEnabled(on) else { return nil }
        refreshNightShift()
        if let ctx = context, ctx.runtime.isEffective(.osd), let main = ctx.registry.displays.first(where: \.isMain) {
            ctx.osd.show(.nightShift, text: on ? L("Night Shift on") : L("Night Shift off"), on: main.desktopID)
        }
        VoiceOverAnnouncer.announce(on ? L("Night Shift on") : L("Night Shift off"))
        context?.requestMenuRebuild()
        return on
    }

    func setNightShiftStrength(_ value: Double) {
        guard effective.contains(.nightShift), value.isFinite else { return }
        _ = SNNightShift.setStrength(Float(min(1, max(0, value))))
        refreshNightShift()
    }

    private func stepNightShift(_ sign: Double) {
        let current = SNNightShift.currentStrength()?.doubleValue ?? 0.5
        setNightShiftStrength(current + sign * 0.1)
        if let ctx = context, ctx.runtime.isEffective(.osd), let main = ctx.registry.displays.first(where: \.isMain) {
            ctx.osd.show(.nightShift, value: nightShiftStrength ?? 0, max: 1, on: main.desktopID)
        }
    }

    private func registerNightShift(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.actions.register(Action(id: Self.nightShiftAction, title: L("Night Shift On or Off"), feature: .nightShift,
                                    cliAllowed: true) { [weak self] _ in _ = self?.toggleNightShift() }, lifetime: lifetime)
        ctx.actions.register(Action(id: Self.nightShiftUpAction, title: L("Night Shift Warmer"), feature: .nightShift,
                                    cliAllowed: true) { [weak self] _ in self?.stepNightShift(1) }, lifetime: lifetime)
        ctx.actions.register(Action(id: Self.nightShiftDownAction, title: L("Night Shift Cooler"), feature: .nightShift,
                                    cliAllowed: true) { [weak self] _ in self?.stepNightShift(-1) }, lifetime: lifetime)
        // `toggle nightShift` matches too: verbs compare case-insensitively.
        let verbs = [("toggle night-shift", L("Turn Night Shift on or off")), ("toggle nightshift", L("Same as toggle night-shift"))]
        for (verb, summary) in verbs {
            ctx.commands.register(verb, policy: .low, offOnly: false, cliAllowed: true,
                                  summary: summary, lifetime: lifetime) { [weak self] request, _ in
                guard let self, self.context != nil else { return DisplayTargets.notRunning() }
                guard request.arguments.isEmpty else { return .failure(ControlExit.usage, L("Usage: toggle night-shift")) }
                guard self.effective.contains(.nightShift) else {
                    return .failure(ControlExit.unavailable, L("Night Shift controls are off"))
                }
                guard let on = self.toggleNightShift() else {
                    return .failure(ControlExit.unavailable, L("Night Shift isn't available"))
                }
                return .ok(on ? L("Night Shift on") : L("Night Shift off"))
            }
        }
    }

    // MARK: Apple presets and auto-brightness

    func applyPreset(_ preset: AppleDisplayPreset, to key: DisplayKey) {
        guard let context else { return }
        if !context.monitorPanel.applyPreset(id: preset.id, for: key) {
            context.toasts.show(L("The preset couldn’t be selected."), lifetime: lifetime)
        }
        // A fixed-brightness preset disables Apple native brightness: let brightness re-check.
        context.brightness.reevaluate(key)
        context.runtime.revision(.systemColors).bump()
        context.requestMenuRebuild()
    }

    func setAutoBrightness(_ on: Bool, for key: DisplayKey) {
        guard let context, effective.contains(.autoBrightness) else { return }
        if !context.appleBrightness.setAutoBrightness(on, of: key) {
            context.toasts.show(L("Automatic brightness couldn’t be changed."), lifetime: lifetime)
        }
        context.runtime.revision(.systemColors).bump()
        context.requestMenuRebuild()
    }

    // MARK: Menu


    func diagnostics() -> [(String, String)] {
        guard let context else { return [] }
        return [
            ("Night Shift", nightShiftOn.map { $0 ? "on" : "off" } ?? "unavailable"),
            ("Profiles installed", String(context.colorSync.installedProfiles().count)),
            ("Custom profile in use", context.colorSync.anyCustomProfile ? "yes" : "no"),
            ("Apple presets", context.monitorPanel.isAvailable ? "available" : "unavailable"),
            ("Auto-brightness control", context.appleBrightness.hasAutoBrightnessControl ? "available" : "unavailable"),
        ]
    }
}
