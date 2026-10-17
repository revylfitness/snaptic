import AppKit
import Combine
import SnapticKit
import SnapticShims

// MARK: Shared helpers for C's controllers

/// Resolves action and CLI targets to displays.
enum DisplayTargets {
    /// The display under the pointer (its desktop, so a Smart HiDPI pair resolves to the pair).
    @MainActor static func pointerDisplay(_ ctx: DisplaysContext) -> DisplayInfo? {
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(location, $0.frame, false) }),
              let id = screen.displayID else { return nil }
        return ctx.registry.info(desktopID: id) ?? ctx.registry.info(hardwareID: id)
    }

    /// The display with the focused window.
    @MainActor static func focusedDisplay(_ ctx: DisplaysContext) -> DisplayInfo? {
        guard let id = NSScreen.main?.displayID else { return nil }
        return ctx.registry.info(desktopID: id)
    }

    @MainActor static func resolve(_ target: DisplayTarget, _ ctx: DisplaysContext) -> [DisplayInfo] {
        let online = ctx.registry.displays.filter { $0.isOnline }
        switch target {
        case .display(let key):
            return online.filter { $0.key == key }
        case .main:
            return online.filter(\.isMain).prefix(1).map { $0 }
        case .pointer:
            return pointerDisplay(ctx).map { [$0] } ?? online.filter(\.isMain)
        case .all:
            return online
        }
    }

    /// The KeysConfig target for shortcuts and keys.
    @MainActor static func keyTarget(_ ctx: DisplaysContext) -> DisplayTarget {
        switch ctx.config.value.keys.target {
        case .pointer: return .pointer
        case .focusedWindow: return focusedDisplay(ctx).map { .display($0.key) } ?? .main
        case .all: return .all
        }
    }

    /// "main", "pointer", "all", a 32-hex key, a 1-based menu index, or a name prefix.
    @MainActor static func select(_ text: String, _ ctx: DisplaysContext) -> DisplayTarget? {
        let t = text.trimmingCharacters(in: .whitespaces)
        switch t.lowercased() {
        case "main": return .main
        case "pointer", "mouse": return .pointer
        case "all": return .all
        default: break
        }
        if let key = DisplayKey(rawValue: t.lowercased()) { return .display(key) }
        let online = ctx.registry.displays.filter { $0.isOnline }
        if let index = Int(t), index >= 1, index <= online.count { return .display(online[index - 1].key) }
        let lower = t.lowercased()
        if let match = online.first(where: { $0.name.lowercased() == lower })
            ?? online.first(where: { $0.name.lowercased().hasPrefix(lower) }) {
            return .display(match.key)
        }
        return nil
    }

    /// Splits CLI arguments into values and an optional trailing display selector.
    @MainActor static func cliTarget(_ arguments: [String], valueCount: Int, _ ctx: DisplaysContext)
        -> (target: DisplayTarget, values: [String])? {
        var args = arguments
        var target: DisplayTarget = .main
        if let i = args.firstIndex(of: "--display"), i + 1 < args.count {
            guard let t = select(args[i + 1], ctx) else { return nil }
            target = t
            args.removeSubrange(i...(i + 1))
        } else if args.count > valueCount, let last = args.last {
            guard let t = select(last, ctx) else { return nil }
            target = t
            args.removeLast()
        }
        guard args.count == valueCount else { return nil }
        return (target, args)
    }

    /// "50", "50%", "+10", "-5" → a 0…max level relative to `current` (percent units).
    static func level(_ text: String, current: Double, max: Double = 1) -> Double? {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("%") { t.removeLast() }
        let relative = t.hasPrefix("+") || t.hasPrefix("-")
        guard let n = Double(t), n.isFinite else { return nil }
        let v = relative ? current + n / 100 : n / 100
        return Swift.min(max, Swift.max(0, v))
    }

    static let usage = L("Display: main, pointer, all, a number from the menu, or a name.")
}

/// OSD plus VoiceOver feedback (announcements happen whenever VoiceOver runs, R3.7).
enum Feedback {
    @MainActor static func show(_ ctx: DisplaysContext, _ kind: OSDKind, value: Double, max: Double, display: DisplayInfo,
                                detail: String? = nil) {
        if ctx.runtime.isEffective(.osd) || ctx.runtime.isEffective(.osdBroadcast) {
            ctx.osd.show(kind, value: value, max: max, on: display.desktopID, detail: detail)
        }
        let name = TextSanitizer.clean(display.name, maxScalars: 64)
        let what: String
        switch kind {
        case .brightness: what = L("Brightness")
        case .contrast: what = L("Contrast")
        case .volume: what = L("Volume")
        case .mute: what = value > 0 ? L("Muted") : L("Unmuted")
        case .xdr: what = L("Extra brightness")
        default: what = ""
        }
        let text = kind == .mute ? "\(name): \(what)" : "\(name): \(what) \(VoiceOverAnnouncer.percent(value / Swift.max(max, 0.0001)))"
        VoiceOverAnnouncer.announce(text)
    }

    /// Brightness OSD for a display, with nits when that's on.
    @MainActor static func brightness(_ ctx: DisplaysContext, _ display: DisplayInfo) {
        guard let value = ctx.brightness.value(for: display.key) else { return }
        var detail: String?
        if ctx.runtime.isEffective(.nits), ctx.config.value.brightness.showNits, let nits = ctx.brightness.nits(for: display.key) {
            detail = NitsModel.label(nits.value, estimate: nits.estimate)
        }
        if value > 1 {
            show(ctx, .xdr, value: value, max: 1, display: display, detail: detail ?? L("Extra brightness"))
        } else {
            show(ctx, .brightness, value: value, max: 1, display: display, detail: detail)
        }
    }
}

/// Small helpers for persisted per-display settings.
enum PerDisplayEdit {
    @MainActor static func update(_ ctx: DisplaysContext, _ key: DisplayKey, _ body: (inout PerDisplayConfig) -> Void) {
        var config = ctx.config.value
        var per = config.perDisplay[key] ?? PerDisplayConfig()
        body(&per)
        config.perDisplay[key] = per
        ctx.config.value = config
    }

    @MainActor static func registerHotkey(_ ctx: DisplaysContext, _ combo: HotkeyCombo, owner: String, lifetime: Lifetime,
                                          action: @escaping @MainActor () -> Void) -> String? {
        do {
            _ = try ctx.hotkeys.register(combo, owner: owner, lifetime: lifetime, action: action)
            return nil
        } catch let error as GlobalHotkeys.RegisterError {
            switch error {
            case .conflict(let other): return L("already used by \(other)")
            case .systemRefused: return L("macOS refused the shortcut")
            case .notBuilt: return L("global shortcuts aren't available yet")
            case .invalid(let reason): return reason
            case .ended: return L("the feature stopped")
            }
        } catch {
            return L("the shortcut couldn't be registered")
        }
    }
}

// MARK: Brightness controller

/// Serves `brightness`, the four methods, `brightnessRestore`, `dimToBlack`, `dimOnLock`
/// and `nits` (PLAN §2.1, §6.1). Registers the slider menu items, ± actions, the
/// `set brightness` / `get brightness` CLI verbs, panic and session participation, and
/// diagnostics.
@MainActor final class BrightnessController: DisplayFeatureController, PanicParticipant, SessionParticipant,
    DiagnosticsContributor {
    static var id: DisplayControllerID { .brightness }
    static var privateSymbols: [PrivateSymbol] { [] }

    static let upAction = DisplayActionID(rawValue: "c.brightnessUp")
    static let downAction = DisplayActionID(rawValue: "c.brightnessDown")
    static let fineUpAction = DisplayActionID(rawValue: "c.brightnessUpFine")
    static let fineDownAction = DisplayActionID(rawValue: "c.brightnessDownFine")

    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private var effective: Set<DisplayFeature> = []
    private var menuItems: BrightnessMenuItems?
    private var sinks: [AnyCancellable] = []
    private var askedDarker: Set<DisplayKey> = []

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability {
        switch feature {
        case .brightnessApple:
            return context.privateAPI.availability(of: .dsGetBrightness)
        case .brightnessDDC:
            return SNDDC.isAvailable() ? .available : .unavailable(L("DDC isn't available on this Mac"))
        case .brightnessGamma:
            if AffectedModels.gammaIsUnreliable(HostInfo.current) { return .unavailable(AffectedModels.reason(.gammaNoOp)) }
            return .available
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
        context.registerPanic(self, lifetime: lifetime)
        context.registerSession(self, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Brightness"), lifetime: lifetime)
        let items = BrightnessMenuItems(context: context)
        menuItems = items
        context.menus.register(items, lifetime: lifetime)
        registerActions(context, lifetime: lifetime)
        registerCommands(context, lifetime: lifetime)
        context.brightness.changeEvents
            .sink { [weak self] change in self?.brightnessChanged(change) }
            .store(in: &sinks)
        context.brightness.reevaluate()
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        self.effective = effective
        context?.brightness.reevaluate()
        context?.requestMenuRebuild()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        let oldPer = old.perDisplay.values.mapValues(\.brightness)
        let newPer = new.perDisplay.values.mapValues(\.brightness)
        let changedKeys = Set(newPer.keys).union(oldPer.keys).filter { key in
            let a = oldPer[key] ?? PerDisplayBrightness(), b = newPer[key] ?? PerDisplayBrightness()
            return a.method != b.method || a.switchover != b.switchover || a.minHardware != b.minHardware
                || a.gammaWorks != b.gammaWorks || a.nits != b.nits
        }
        for key in changedKeys { context?.brightness.reevaluate(key) }
        if !changedKeys.isEmpty { context?.requestMenuRebuild() }
    }

    func stop() {
        sinks.removeAll()
        menuItems = nil
        lifetime = nil
        context = nil
        askedDarker.removeAll()
    }

    // MARK: Panic / session

    func panicRestore() { context?.brightness.resetSoftware() }

    func sessionDidPause() {
        guard let context, effective.contains(.dimOnLock) else { return }
        context.brightness.setLockDim(context.config.value.brightness.dimOnLockLevel)
    }

    func sessionDidResume() {
        // The session gate already re-checked the session dictionary (on console, unlocked).
        context?.brightness.setLockDim(nil)
    }

    // MARK: Changes

    private func brightnessChanged(_ change: BrightnessService.Change) {
        menuItems?.update(change.key, value: change.value)
        if change.source == .user || change.source == .keys { askDidItGetDarker(change.key) }
    }

    /// "Did it get darker?" the first time gamma dims a display (PLAN §6.1).
    private func askDidItGetDarker(_ key: DisplayKey) {
        guard let context, let lifetime, !askedDarker.contains(key),
              context.brightness.softwareMethod(for: key) == .gamma,
              context.config.value.perDisplay[key]?.brightness.gammaWorks == nil,
              let out = context.brightness.output(for: key), out.software < 0.7 else { return }
        askedDarker.insert(key)
        PerDisplayEdit.update(context, key) { $0.brightness.gammaWorks = true }
        context.toasts.show(L("Snaptic dimmed this display with its color table. If it didn't get darker, switch to overlay dimming."),
                            action: ToastAction(title: L("It didn't get darker")) { [weak self] in
                                guard let self, let ctx = self.context else { return }
                                PerDisplayEdit.update(ctx, key) { $0.brightness.gammaWorks = false }
                                ctx.brightness.reevaluate(key)
                            }, lifetime: lifetime)
    }

    // MARK: Actions and CLI

    func stepBrightness(_ target: DisplayTarget, delta: Double, source: BrightnessService.Source = .user) {
        guard let context else { return }
        for display in DisplayTargets.resolve(target, context) where context.brightness.value(for: display.key) != nil {
            context.brightness.step(delta, for: display.key, source: source)
            Feedback.brightness(context, display)
        }
    }

    private func registerActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        let entries: [(DisplayActionID, String, Bool, Double)] = [
            (Self.upAction, L("Brightness Up"), false, 1),
            (Self.downAction, L("Brightness Down"), false, -1),
            (Self.fineUpAction, L("Brightness Up (Fine)"), true, 1),
            (Self.fineDownAction, L("Brightness Down (Fine)"), true, -1),
        ]
        for (id, title, fine, sign) in entries {
            ctx.actions.register(Action(id: id, title: title, feature: .brightness, cliAllowed: true) { [weak self] target in
                guard let self, let ctx = self.context else { return }
                self.stepBrightness(target, delta: sign * ctx.config.value.keys.step(fine: fine))
            }, lifetime: lifetime)
        }
    }

    private func registerCommands(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.commands.register("set brightness", policy: .low, offOnly: false, cliAllowed: true,
                              summary: L("Set brightness: set brightness 60 [display] (or +10 / -10)"),
                              lifetime: lifetime) { [weak self] request in
            guard let self, let ctx = self.context else { return .failure(2, L("Displays isn't running")) }
            guard let parsed = DisplayTargets.cliTarget(request.arguments, valueCount: 1, ctx) else {
                return .failure(64, L("Usage: set brightness <percent|+n|-n> [display]. ") + DisplayTargets.usage)
            }
            let displays = DisplayTargets.resolve(parsed.target, ctx).filter { ctx.brightness.value(for: $0.key) != nil }
            guard !displays.isEmpty else { return .failure(3, L("No display with brightness control matches")) }
            for d in displays {
                let current = ctx.brightness.value(for: d.key) ?? 1
                let range = ctx.brightness.range(for: d.key)
                guard let v = DisplayTargets.level(parsed.values[0], current: current, max: range.upperBound) else {
                    return .failure(64, L("Not a brightness value"))
                }
                ctx.brightness.set(v, for: d.key, source: .cli)
            }
            return .ok()
        }
        ctx.commands.register("get brightness", policy: .read, offOnly: false, cliAllowed: true,
                              summary: L("Print brightness per display"), lifetime: lifetime) { [weak self] request in
            guard let self, let ctx = self.context else { return .failure(2, L("Displays isn't running")) }
            let target = request.arguments.first.flatMap { DisplayTargets.select($0, ctx) } ?? .all
            let lines = DisplayTargets.resolve(target, ctx).compactMap { d -> String? in
                guard let v = ctx.brightness.value(for: d.key) else { return nil }
                let method = ctx.brightness.activeMethod(for: d.key)?.rawValue ?? "-"
                return "\(TextSanitizer.clean(d.name, maxScalars: 64))\t\(Int((v * 100).rounded()))%\t\(method)"
            }
            return .ok(lines.joined(separator: "\n"))
        }
    }

    // MARK: Diagnostics

    func diagnostics() -> [(String, String)] {
        guard let context else { return [] }
        var rows: [(String, String)] = []
        rows.append(("Host", "\(HostInfo.current.chipName), macOS \(HostInfo.current.osMajor).\(HostInfo.current.osMinor)"))
        rows.append(("Gamma", AffectedModels.gammaIsUnreliable(HostInfo.current) ? "affected model (overlay used)"
                        : (context.gamma.blockedByCustomProfile ? "off: custom profile safeguard" : "available")))
        for (index, d) in context.registry.displays.filter({ $0.isOnline }).enumerated() {
            let b = context.brightness
            let value = b.value(for: d.key).map { String(format: "%.2f", $0) } ?? "-"
            let hw = b.hardwareMethod(for: d.key)?.rawValue ?? "-"
            let sw = b.softwareMethod(for: d.key)?.rawValue ?? "-"
            rows.append(("Display \(index + 1)", "\(value) via \(hw) + \(sw): \(b.methodReason(for: d.key)); gamma \(context.gamma.diagnostics(for: d.key))"))
        }
        return rows
    }
}
