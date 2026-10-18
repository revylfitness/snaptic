import AppKit
import Combine
import SnapticKit
import SnapticShims

/// DDC controls (PLAN §7, parity §6): volume, mute, contrast and other VCP controls with
/// per-control tuning and periodic readback; input switching with a renamed / hidden /
/// reordered list and LG's alternate addressing; DDC standby / power-on; custom VCP
/// controls and raw get/set. PreConfirm codes always go through PreConfirmPresenter.
@MainActor final class DDCController: DisplayFeatureController, DiagnosticsContributor, SessionParticipant {
    static var id: DisplayControllerID { .ddc }
    static var privateSymbols: [PrivateSymbol] { [] }

    /// Action ids other controllers call (KeysController's volume and mute keys).
    static let volumeUpAction = DisplayActionID(rawValue: "c.volumeUp")
    static let volumeDownAction = DisplayActionID(rawValue: "c.volumeDown")
    static let volumeUpFineAction = DisplayActionID(rawValue: "c.volumeUpFine")
    static let volumeDownFineAction = DisplayActionID(rawValue: "c.volumeDownFine")
    static let muteAction = DisplayActionID(rawValue: "c.mute")
    /// DDC settings, per-display tuning and the input slots (in `keys`).
    static var observedSections: Set<DisplaysConfigSection> { [.ddc, .perDisplayDDC, .keys] }

    /// The volume step action for a direction and step size.
    static func volumeAction(up: Bool, fine: Bool) -> DisplayActionID {
        switch (up, fine) {
        case (true, false): return volumeUpAction
        case (false, false): return volumeDownAction
        case (true, true): return volumeUpFineAction
        case (false, true): return volumeDownFineAction
        }
    }

    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private(set) var effective: Set<DisplayFeature> = []
    private var menuItems: DDCMenuItems?
    private var readbackTimer: Timer?
    private var nextReadback: [DisplayKey: [UInt8: TimeInterval]] = [:]
    private var loaded: Set<DisplayKey> = []
    private var muteRestore: [DisplayKey: UInt16] = [:]
    private var paused = false
    private var sinks: [AnyCancellable] = []
    /// The user's last live change per display and code (value, uptime): read-backs that disagree are ignored for
    /// a second after it (0.3 §4.5, Kit `LiveReadback`).
    private var userSets: [DisplayKey: [UInt8: (value: Double, at: TimeInterval)]] = [:]
    /// Last link status seen per display, so the page revision bumps only when it changes.
    private var linkSeen: [DisplayKey: DDCService.LinkStatus] = [:]
    /// Live values of custom range controls (fractions), for the menu's sliders.
    private var customValues: [DisplayKey: [UInt8: Double]] = [:]
    private let customSubject = PassthroughSubject<(key: DisplayKey, code: UInt8, value: Double), Never>()

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability {
        SNDDC.isAvailable() ? .available : .unavailable(L("Hardware controls aren’t available on this Mac"))
    }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        context.registerSession(self, lifetime: lifetime)
        context.ddc.controller = self
        context.diagnostics.register(self, section: L("Hardware controls"), lifetime: lifetime)
        let items = DDCMenuItems(context: context, controller: self)
        menuItems = items
        context.menus.register(items, lifetime: lifetime)
        context.ddc.onFramingLearned = { [weak self] key, framing in
            guard let ctx = self?.context else { return }
            PerDisplayEdit.update(ctx, key) { $0.ddc.framing = framing }
        }
        context.ddc.observeChanges(lifetime: lifetime) { [weak self] key in
            self?.linkMayHaveChanged(key)
            self?.ddcChanged(key)
        }
        registerActions(context, lifetime: lifetime)
        registerCommands(context, lifetime: lifetime)
        updateReadback()
        for display in context.registry.displays where context.ddc.isAvailable(display.key) { ddcChanged(display.key) }
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        self.effective = effective
        context?.runtime.revision(.ddc).bump()
        context?.requestMenuRebuild()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        if old.ddc != new.ddc || old.perDisplay.values.mapValues(\.ddc) != new.perDisplay.values.mapValues(\.ddc) {
            nextReadback.removeAll()
            updateReadback()
            context?.runtime.revision(.ddc).bump()
            context?.requestMenuRebuild()
        }
        if old.keys.inputSlots != new.keys.inputSlots, let ctx = context, let lifetime { registerSlotActions(ctx, lifetime: lifetime) }
    }

    func stop() {
        readbackTimer?.invalidate()
        readbackTimer = nil
        context?.ddc.onFramingLearned = nil
        if context?.ddc.controller === self { context?.ddc.controller = nil }
        sinks.removeAll()
        nextReadback.removeAll()
        loaded.removeAll()
        muteRestore.removeAll()
        userSets.removeAll()
        linkSeen.removeAll()
        customValues.removeAll()
        menuItems = nil
        slotLifetime = nil
        lifetime = nil
        context = nil
    }

    func sessionDidPause() { paused = true }
    func sessionDidResume() { paused = false }

    // MARK: Values

    private func ddcChanged(_ key: DisplayKey) {
        guard let context, context.ddc.isAvailable(key), !loaded.contains(key), let lifetime else { return }
        loaded.insert(key)
        let ddc = context.ddc
        lifetime.spawn { [weak self] in
            let caps = await ddc.capabilities(of: key, refresh: false)
            guard let self, let ctx = self.context else { return }
            let live = ctx.runtime.runtime(for: key)
            func supported(_ code: UInt8) -> Bool { caps == nil || caps?.supports(code) == true }
            if supported(VCPPolicy.volume), let r = await ddc.read(VCPPolicy.volume, from: key), r.max > 0 {
                self.noteReadback(VCPPolicy.volume, self.fraction(key, VCPPolicy.volume, r), for: key)
            }
            if caps?.supports(VCPPolicy.mute) == true, let r = await ddc.read(VCPPolicy.mute, from: key) {
                live.muted = r.current == 1
            }
            if supported(VCPPolicy.contrast), let r = await ddc.read(VCPPolicy.contrast, from: key), r.max > 0 {
                self.noteReadback(VCPPolicy.contrast, self.fraction(key, VCPPolicy.contrast, r), for: key)
            }
            for control in ctx.config.value.perDisplay[key]?.ddc.customControls ?? [] where control.kind == .range {
                guard supported(control.code), let r = await ddc.read(control.code, from: key), r.max > 0 else { continue }
                self.noteReadback(control.code, self.fraction(key, control.code, r), for: key)
            }
            if self.effective.contains(.ddcInput), supported(VCPPolicy.input), let r = await ddc.read(VCPPolicy.input, from: key) {
                live.input = r.current & 0xFF
            }
            if self.effective.contains(.ddcPower), caps?.supports(VCPPolicy.power) == true,
               let r = await ddc.read(VCPPolicy.power, from: key) {
                live.powerOn = r.current == 1
            }
            ctx.runtime.revision(.ddc).bump()
            ctx.requestMenuRebuild()
        }
    }

    /// Link status or capabilities changed (probe answered, failed, replug): pages showing them refresh.
    private func linkMayHaveChanged(_ key: DisplayKey) {
        guard let context else { return }
        let status = context.ddc.linkStatus(key)
        guard linkSeen[key] != status else { return }
        linkSeen[key] = status
        context.runtime.revision(.ddc).bump()
    }

    // MARK: Live values (0.3 §4.5)

    /// A read-back of a continuous control: shown unless the user just set a different value. A 0.5% wobble
    /// isn't a change.
    func noteReadback(_ code: UInt8, _ fraction: Double, for key: DisplayKey) {
        guard let context, fraction.isFinite else { return }
        if let shown = shownValue(code, for: key), abs(shown - fraction) <= 0.005 { return }
        let set = userSets[key]?[code]
        guard LiveReadback.accepts(fraction, setValue: set?.value, setAt: set?.at,
                                   now: ProcessInfo.processInfo.systemUptime) else { return }
        showValue(code, fraction, for: key, context: context)
    }

    private func showValue(_ code: UInt8, _ fraction: Double, for key: DisplayKey, context: DisplaysContext) {
        let live = context.runtime.runtime(for: key)
        switch code {
        case VCPPolicy.volume:
            if abs((live.volume ?? -1) - fraction) > 0.0005 { live.volume = fraction }
        case VCPPolicy.contrast:
            if abs((live.contrast ?? -1) - fraction) > 0.0005 { live.contrast = fraction }
        default:
            if abs((customValues[key]?[code] ?? -1) - fraction) > 0.0005 {
                customValues[key, default: [:]][code] = fraction
                customSubject.send((key: key, code: code, value: fraction))
            }
        }
    }

    private func shownValue(_ code: UInt8, for key: DisplayKey) -> Double? {
        switch code {
        case VCPPolicy.volume: return context?.runtime.runtime(for: key).volume
        case VCPPolicy.contrast: return context?.runtime.runtime(for: key).contrast
        default: return customValues[key]?[code]
        }
    }

    /// The live fraction of a custom range control (nil until read or set).
    func customValue(_ code: UInt8, for key: DisplayKey) -> Double? {
        if let v = customValues[key]?[code] { return v }
        guard let context, let reading = context.ddc.lastReading(code, of: key), reading.max > 0 else { return nil }
        return fraction(key, code, reading)
    }

    /// Live updates of one custom control, for a menu slider (starts with the current value).
    func customPublisher(_ code: UInt8, for key: DisplayKey) -> AnyPublisher<Double?, Never> {
        customSubject
            .filter { $0.key == key && $0.code == code }
            .map { Optional($0.value) }
            .prepend(customValue(code, for: key))
            .eraseToAnyPublisher()
    }

    /// A live drag began: read-backs hold off as after a change.
    func holdReadbacks(_ code: UInt8, for key: DisplayKey) {
        guard let current = shownValue(code, for: key) ?? customValue(code, for: key) else { return }
        userSets[key, default: [:]][code] = (current, ProcessInfo.processInfo.systemUptime)
    }

    /// DisplayLiveController's delivery: shows the value at once, remembers it against read-backs and writes it
    /// (DDCService keeps the newest value per code and paces writes). `final` ends a drag.
    func setLive(_ code: UInt8, _ fraction: Double, for key: DisplayKey, final: Bool) {
        let standard = code == VCPPolicy.volume || code == VCPPolicy.contrast
        guard effective.contains(standard ? .ddcControls : .ddcCustom), fraction.isFinite else { return }
        setFraction(code, min(1, max(0, fraction)), for: key)
        if final, code == VCPPolicy.volume, context?.runtime.runtime(for: key).muted == true {
            context?.runtime.runtime(for: key).muted = false
        }
    }

    func fraction(_ key: DisplayKey, _ code: UInt8, _ reading: DDCReading) -> Double {
        let tuning = context?.config.value.perDisplay[key]?.ddc.tuning(code) ?? DDCControlTuning()
        return tuning.fraction(raw: reading.current, displayMax: reading.max)
    }

    func raw(_ key: DisplayKey, _ code: UInt8, fraction: Double) -> UInt16 {
        guard let context else { return 0 }
        let tuning = context.config.value.perDisplay[key]?.ddc.tuning(code) ?? DDCControlTuning()
        let max = context.ddc.lastReading(code, of: key)?.max ?? 100
        return tuning.raw(fraction: fraction, displayMax: max == 0 ? 100 : max)
    }

    /// Whether a control is on for a display (tuning override, else the capabilities).
    func isControlEnabled(_ code: UInt8, for key: DisplayKey) -> Bool {
        guard let context else { return false }
        if let explicit = context.config.value.perDisplay[key]?.ddc.tuning(code).enabled { return explicit }
        guard let caps = context.ddc.cachedCapabilities(key) else {
            return code == VCPPolicy.brightness || code == VCPPolicy.contrast || code == VCPPolicy.volume
        }
        return caps.supports(code)
    }

    /// Inputs in display order: the saved list (renamed, hidden, reordered) then any the
    /// capabilities list that aren't saved yet.
    func inputList(for key: DisplayKey, includeHidden: Bool = false) -> [DDCInputEntry] {
        guard let context else { return [] }
        let saved = context.config.value.perDisplay[key]?.ddc.inputs ?? []
        var result = saved
        let listed = context.ddc.cachedCapabilities(key)?.inputSources ?? []
        let known = Set(saved.filter { !$0.lgAlt }.map(\.value))
        for value in (listed.isEmpty ? [0x0F, 0x10, 0x11, 0x12, 0x1B] : listed) where !known.contains(value & 0xFF) {
            result.append(DDCInputEntry(value: value & 0xFF, name: VCPPolicy.inputName(value)))
        }
        return includeHidden ? result : result.filter { !$0.hidden }
    }

    func inputName(_ entry: DDCInputEntry) -> String {
        entry.name.isEmpty ? VCPPolicy.inputName(entry.value) : entry.name
    }

    // MARK: Writes

    /// How an interactive write ended (the CLI maps these to `ControlExit`).
    enum WriteOutcome: Equatable {
        case done
        /// The policy refused it (denied code, locked manufacturer code).
        case refused
        /// The user declined the confirmation, or it timed out.
        case declined
        /// The monitor didn't answer, or DDC refused it for this display.
        case failed

        var exitCode: Int32 {
            switch self {
            case .done: return ControlExit.ok
            case .refused: return ControlExit.refused
            case .declined: return ControlExit.cancelled
            case .failed: return ControlExit.unavailable
            }
        }
    }

    /// Writes one VCP value, asking first when the policy needs it. Interactive only.
    @discardableResult
    func write(_ code: UInt8, _ value: UInt16, to key: DisplayKey, message: String? = nil, lgAlt: Bool = false) async -> Bool {
        await writeOutcome(code, value, to: key, message: message, lgAlt: lgAlt) == .done
    }

    func writeOutcome(_ code: UInt8, _ value: UInt16, to key: DisplayKey, message: String? = nil,
                      lgAlt: Bool = false) async -> WriteOutcome {
        guard let context else { return .failed }
        let tier = VCPPolicy.tier(code: code, value: value, capabilities: context.ddc.cachedCapabilities(key))
        var token: PreConfirmToken?
        switch tier {
        case .denied:
            context.toasts.show(L("Snaptic never sends that command: it can reset or lock the display."), lifetime: lifetime)
            return .refused
        case .unlockable:
            guard context.config.value.perDisplay[key]?.ddc.isUnlocked(code) == true else {
                context.toasts.show(L("Unlock \(VCPPolicy.hex(code)) for this display in Hardware Controls › Advanced first."),
                                    lifetime: lifetime)
                return .refused
            }
            fallthrough
        case .preConfirm:
            let text = message ?? L("Send VCP \(VCPPolicy.hex(code)) = \(value) to this display? Some commands switch the picture away from this Mac.")
            token = await context.preConfirm.confirm(key: key, vcp: code, value: value, message: text,
                                                     allowKey: PreConfirmAllowList.entry(vcp: code, value: value))
            guard token != nil else { return .declined }
        case .safe:
            break
        }
        guard let ctx = self.context else { return .failed }
        let address = lgAlt ? DDCPacket.alternateSourceAddress : DDCPacket.sourceAddress
        return await ctx.ddc.write(code, value, to: key, interactive: true, token: token, dataAddress: address) ? .done : .failed
    }

    func setFraction(_ code: UInt8, _ fraction: Double, for key: DisplayKey) {
        guard let context, let lifetime, fraction.isFinite else { return }
        let value = raw(key, code, fraction: fraction)
        userSets[key, default: [:]][code] = (fraction, ProcessInfo.processInfo.systemUptime)
        showValue(code, fraction, for: key, context: context)
        lifetime.spawn { [weak self] in _ = await self?.write(code, value, to: key) }
    }

    func step(_ code: UInt8, _ target: DisplayTarget, delta: Double) {
        guard let context else { return }
        for display in DisplayTargets.resolve(target, context) where context.ddc.isAvailable(display.key) {
            guard isControlEnabled(code, for: display.key) else { continue }
            let live = context.runtime.runtime(for: display.key)
            let current = code == VCPPolicy.volume ? live.volume : live.contrast
            let base = current ?? context.ddc.lastReading(code, of: display.key).map { fraction(display.key, code, $0) } ?? 0.5
            let next = min(1, max(0, base + delta))
            setFraction(code, next, for: display.key)
            if code == VCPPolicy.volume, live.muted == true { live.muted = false }
            let showOSD = code != VCPPolicy.volume || (context.config.value.perDisplay[display.key]?.keys.showVolumeOSD ?? true)
            if showOSD {
                Feedback.show(context, code == VCPPolicy.volume ? .volume : .contrast, value: next, max: 1, display: display)
            }
        }
    }

    func toggleMute(_ target: DisplayTarget) {
        guard let context, let lifetime else { return }
        for display in DisplayTargets.resolve(target, context) where context.ddc.isAvailable(display.key) {
            let key = display.key
            let live = context.runtime.runtime(for: key)
            let mute = !(live.muted ?? false)
            live.muted = mute
            let useMuteCode = context.ddc.cachedCapabilities(key)?.supports(VCPPolicy.mute) ?? false
            if mute, !useMuteCode { muteRestore[key] = context.ddc.lastReading(VCPPolicy.volume, of: key)?.current ?? 50 }
            let restore = muteRestore[key] ?? 50
            lifetime.spawn { [weak self] in
                guard let self else { return }
                let ok: Bool
                if useMuteCode {
                    ok = await self.write(VCPPolicy.mute, mute ? 1 : 2, to: key)
                } else {
                    ok = await self.write(VCPPolicy.volume, mute ? 0 : restore, to: key)
                }
                if !ok { live.muted = !mute }
            }
            Feedback.show(context, .mute, value: mute ? 1 : 0, max: 1, display: display)
        }
    }

    /// Callers: menus, the panel, input slots, layouts. Refused (false) while `ddcInput`
    /// is off; true means the switch was started (it may still ask first).
    @discardableResult
    func setInput(_ entry: DDCInputEntry, on key: DisplayKey) -> Bool {
        guard let context, let lifetime, let display = context.registry.info(for: key) else { return false }
        guard effective.contains(.ddcInput) else {
            EventLog.shared.record(.ddc, "Input switch refused: input switching is off")
            return false
        }
        let name = TextSanitizer.clean(display.name, maxScalars: 64)
        let message = L("Switch “\(name)” to \(inputName(entry))? It shows that source until you switch back with the display’s buttons or from Snaptic.")
        let code = entry.lgAlt ? VCPPolicy.lgAlternateInput : VCPPolicy.input
        lifetime.spawn { [weak self] in
            guard let self else { return }
            if await self.write(code, entry.value, to: key, message: message, lgAlt: entry.lgAlt) {
                self.context?.runtime.runtime(for: key).input = entry.value
                if let ctx = self.context, ctx.runtime.isEffective(.osd) {
                    ctx.osd.show(.input, text: self.inputName(entry), on: display.desktopID)
                }
                VoiceOverAnnouncer.announce(L("Input: ") + self.inputName(entry))
            }
        }
        return true
    }

    /// Power on is safe; standby is confirmed and refused on the only display you can see.
    /// Refused (false) while `ddcPower` is off.
    @discardableResult
    func setPower(_ on: Bool, on key: DisplayKey) -> Bool {
        guard let context, let lifetime, let display = context.registry.info(for: key) else { return false }
        guard effective.contains(.ddcPower) else {
            EventLog.shared.record(.ddc, "DDC power change refused: DDC power is off")
            return false
        }
        if !on {
            let others = context.registry.displays.contains { $0.key != key && $0.isOnline && $0.isStronglyVisible }
            guard others else {
                context.toasts.show(L("That’s the only display you can see, so Snaptic won’t turn it off."), lifetime: lifetime)
                return false
            }
        }
        let value: UInt16 = on ? VCPPolicy.powerOn : (context.config.value.perDisplay[key]?.ddc.standbyValue ?? 4)
        let name = TextSanitizer.clean(display.name, maxScalars: 64)
        let message = L("Put “\(name)” on standby? Wake it with its power button or from Snaptic.")
        lifetime.spawn { [weak self] in
            guard let self else { return }
            if await self.write(VCPPolicy.power, value, to: key, message: message) {
                self.context?.runtime.runtime(for: key).powerOn = on
            }
        }
        return true
    }

    func runCustom(_ control: DDCCustomControl, on key: DisplayKey, fraction: Double? = nil) {
        guard let lifetime else { return }
        if control.kind == .range, let fraction {
            setFraction(control.code, fraction, for: key)
            return
        }
        let value = control.value
        lifetime.spawn { [weak self] in _ = await self?.write(control.code, value, to: key) }
    }

    // MARK: Readback

    private func updateReadback() {
        guard let context, context.config.value.ddc.readback else {
            readbackTimer?.invalidate()
            readbackTimer = nil
            return
        }
        guard readbackTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readbackTick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        readbackTimer = timer
    }

    private func readbackTick() {
        guard let context, let lifetime, !paused, context.sessionGate.isOpen else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let config = context.config.value
        for display in context.registry.displays where context.ddc.isAvailable(display.key) {
            let per = config.perDisplay[display.key]?.ddc ?? PerDisplayDDC()
            var codes: [UInt8: Double] = [:]
            for code in [VCPPolicy.brightness, VCPPolicy.volume, VCPPolicy.contrast] where isControlEnabled(code, for: display.key) {
                let interval = per.tuning(code).readbackInterval
                codes[code] = interval > 0 ? interval : config.ddc.defaultReadbackInterval
            }
            for (key, tuning) in per.controls.values where tuning.readbackInterval > 0 { codes[key.code] = tuning.readbackInterval }
            for (code, interval) in codes {
                let due = nextReadback[display.key]?[code] ?? 0
                guard now >= due else { continue }
                nextReadback[display.key, default: [:]][code] = now + interval
                let key = display.key
                let ddc = context.ddc
                lifetime.spawn { [weak self] in
                    guard let reading = await ddc.read(code, from: key), let self, let ctx = self.context else { return }
                    let f = self.fraction(key, code, reading)
                    let live = ctx.runtime.runtime(for: key)
                    switch code {
                    case VCPPolicy.brightness: ctx.brightness.noteHardwareChanged(key, hardware: f)
                    case VCPPolicy.input: live.input = reading.current & 0xFF
                    case VCPPolicy.power: live.powerOn = reading.current == 1
                    default:
                        // Volume, contrast and custom controls.
                        guard reading.max > 0 else { return }
                        self.noteReadback(code, f, for: key)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private var slotLifetime: Lifetime?

    private func registerActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        let steps: [(DisplayActionID, String, UInt8, Double, Bool)] = [
            (Self.volumeUpAction, L("Volume Up"), VCPPolicy.volume, 1, false),
            (Self.volumeDownAction, L("Volume Down"), VCPPolicy.volume, -1, false),
            (Self.volumeUpFineAction, L("Volume Up (Fine)"), VCPPolicy.volume, 1, true),
            (Self.volumeDownFineAction, L("Volume Down (Fine)"), VCPPolicy.volume, -1, true),
            (DisplayActionID(rawValue: "c.contrastUp"), L("Contrast Up"), VCPPolicy.contrast, 1, false),
            (DisplayActionID(rawValue: "c.contrastDown"), L("Contrast Down"), VCPPolicy.contrast, -1, false),
            (DisplayActionID(rawValue: "c.contrastUpFine"), L("Contrast Up (Fine)"), VCPPolicy.contrast, 1, true),
            (DisplayActionID(rawValue: "c.contrastDownFine"), L("Contrast Down (Fine)"), VCPPolicy.contrast, -1, true),
        ]
        for (id, title, code, sign, fine) in steps {
            ctx.actions.register(Action(id: id, title: title, feature: .ddcControls,
                                        cliAllowed: true) { [weak self] target in
                guard let self, let ctx = self.context else { return }
                self.step(code, target, delta: sign * ctx.config.value.keys.step(fine: fine))
            }, lifetime: lifetime)
        }
        ctx.actions.register(Action(id: Self.muteAction, title: L("Mute"), feature: .ddcControls,
                                    cliAllowed: true) { [weak self] target in self?.toggleMute(target) }, lifetime: lifetime)
        ctx.actions.register(Action(id: DisplayActionID(rawValue: "c.ddcPowerOn"), title: L("Turn On Display"),
                                    feature: .ddcPower, cliAllowed: true) { [weak self] target in
            guard let self, let ctx = self.context else { return }
            for d in DisplayTargets.resolve(target, ctx) { self.setPower(true, on: d.key) }
        }, lifetime: lifetime)
        ctx.actions.register(Action(id: DisplayActionID(rawValue: "c.ddcStandby"), title: L("Turn Off Display"),
                                    feature: .ddcPower, cliAllowed: false) { [weak self] target in
            guard let self, let ctx = self.context else { return }
            for d in DisplayTargets.resolve(target, ctx) { self.setPower(false, on: d.key) }
        }, lifetime: lifetime)
        registerSlotActions(ctx, lifetime: lifetime)
    }

    /// Input slots 1–10 (display + input from Keys & Shortcuts).
    private func registerSlotActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        slotLifetime?.end()
        let life = lifetime.child()
        slotLifetime = life
        let slots = ctx.config.value.keys.inputSlots
        for index in 0..<KeysConfig.maxSlots {
            ctx.actions.register(Action(id: DisplayActionID(rawValue: "c.inputSlot\(index + 1)"),
                                        title: L("Input Slot \(index + 1)"), feature: .ddcInput, cliAllowed: false) {
                [weak self] target in
                guard let self, let ctx = self.context, index < slots.count else { return }
                let slot = slots[index]
                let key = slot.display ?? DisplayTargets.resolve(target, ctx).first?.key
                guard let key else { return }
                let entry = self.inputList(for: key, includeHidden: true).first { $0.value == slot.value && $0.lgAlt == slot.lgAlt }
                    ?? DDCInputEntry(value: slot.value, name: "", lgAlt: slot.lgAlt)
                self.setInput(entry, on: key)
            }, lifetime: life)
        }
    }

    private func registerCommands(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.commands.register("set volume", policy: .low, offOnly: false, cliAllowed: true,
                              summary: L("Set hardware volume: set volume 40 [display] (or +5 / -5)"), lifetime: lifetime) {
            [weak self] request, _ in await self?.setLevelCommand(VCPPolicy.volume, request) ?? DisplayTargets.notRunning()
        }
        ctx.commands.register("set contrast", policy: .low, offOnly: false, cliAllowed: true,
                              summary: L("Set hardware contrast: set contrast 70 [display]"), lifetime: lifetime) {
            [weak self] request, _ in await self?.setLevelCommand(VCPPolicy.contrast, request) ?? DisplayTargets.notRunning()
        }
        ctx.commands.register("get volume", policy: .read, offOnly: false, cliAllowed: true,
                              summary: L("Print hardware volume per display: get volume [display]"), lifetime: lifetime) {
            [weak self] request, _ in await self?.getLevelCommand(VCPPolicy.volume, request) ?? DisplayTargets.notRunning()
        }
        ctx.commands.register("get contrast", policy: .read, offOnly: false, cliAllowed: true,
                              summary: L("Print hardware contrast per display: get contrast [display]"), lifetime: lifetime) {
            [weak self] request, _ in await self?.getLevelCommand(VCPPolicy.contrast, request) ?? DisplayTargets.notRunning()
        }
        ctx.commands.register("get input", policy: .read, offOnly: false, cliAllowed: true,
                              summary: L("Print the current input per display: get input [display]"), lifetime: lifetime) {
            [weak self] request, _ in await self?.getInputCommand(request) ?? DisplayTargets.notRunning()
        }
        ctx.commands.register("input", policy: .preConfirm, offOnly: false, cliAllowed: true,
                              summary: L("Switch input: input <name|hex value> [display] (asks first unless allowed)"),
                              lifetime: lifetime) { [weak self] request, _ in
            guard let self, let ctx = self.context else { return DisplayTargets.notRunning() }
            let usage = L("Usage: input <name|hex value> [display]. ") + DisplayTargets.usage
            let (parsed, error) = DisplayTargets.cliArguments(request.arguments, valueCount: 1, usage: usage, ctx)
            guard let parsed else { return error ?? .failure(ControlExit.usage, usage) }
            guard self.effective.contains(.ddcInput) else { return .failure(ControlExit.unavailable, L("Input switching is off")) }
            guard let display = DisplayTargets.resolve(parsed.target, ctx).first(where: { ctx.ddc.isAvailable($0.key) }) else {
                return .failure(ControlExit.notFound, L("No display with hardware controls matches"))
            }
            let wanted = parsed.values[0].lowercased()
            let list = self.inputList(for: display.key, includeHidden: true)
            let entry = list.first { self.inputName($0).lowercased() == wanted }
                ?? VCPPolicy.parseCode(wanted).map { v in list.first { $0.value == UInt16(v) } ?? DDCInputEntry(value: UInt16(v), name: "") }
            guard let entry else { return .failure(ControlExit.notFound, L("Unknown input. Try `snaptic get input`.")) }
            let code = entry.lgAlt ? VCPPolicy.lgAlternateInput : VCPPolicy.input
            let outcome = await self.writeOutcome(code, entry.value, to: display.key, lgAlt: entry.lgAlt)
            if outcome == .done { self.context?.runtime.runtime(for: display.key).input = entry.value }
            return outcome == .done ? .ok() : .failure(outcome.exitCode, Self.message(outcome))
        }
        ctx.commands.register("ddc", policy: .preConfirm, offOnly: false, cliAllowed: true,
                              summary: L("Raw hardware commands (DDC/CI): ddc get <code> | ddc set <code> <value> | ddc caps [display]"),
                              lifetime: lifetime) { [weak self] request, _ in
            guard let self, let ctx = self.context else { return DisplayTargets.notRunning() }
            let usage = L("Usage: ddc get <code> | ddc set <code> <value> | ddc caps [display]")
            var args = request.arguments
            guard let op = args.first?.lowercased(), ["get", "set", "caps"].contains(op) else {
                return .failure(ControlExit.usage, usage)
            }
            args.removeFirst()
            let valueCount = op == "set" ? 2 : (op == "get" ? 1 : 0)
            let (parsed, error) = DisplayTargets.cliArguments(args, valueCount: valueCount, usage: usage, ctx)
            guard let parsed else { return error ?? .failure(ControlExit.usage, usage) }
            guard let display = DisplayTargets.resolve(parsed.target, ctx).first(where: { ctx.ddc.isAvailable($0.key) }) else {
                return .failure(ControlExit.notFound, L("No display with hardware controls matches. ") + DisplayTargets.usage)
            }
            switch op {
            case "caps":
                guard let caps = await ctx.ddc.capabilities(of: display.key, refresh: true) else {
                    return .failure(ControlExit.unavailable, L("The display returned no capabilities"))
                }
                let codes = caps.vcp.keys.sorted().map { VCPPolicy.hex($0) }
                let model = TextSanitizer.clean(caps.model ?? "?", maxScalars: 64)
                if request.json {
                    return DisplayTargets.rows([(display, [], ["model": model, "mccs": caps.mccsVersion ?? "", "vcp": codes])],
                                               json: true, none: "", ctx)
                }
                return .ok("model \(model), mccs \(caps.mccsVersion ?? "?")\nvcp \(codes.joined(separator: " "))")
            case "get":
                guard let code = VCPPolicy.parseCode(parsed.values[0]) else { return .failure(ControlExit.usage, L("Not a VCP code")) }
                guard self.effective.contains(.ddcControls) || self.effective.contains(.ddcCustom) else {
                    return .failure(ControlExit.unavailable, L("Hardware controls are off"))
                }
                guard let r = await ctx.ddc.read(code, from: display.key) else {
                    return .failure(ControlExit.unavailable, L("No reply"))
                }
                if request.json {
                    return DisplayTargets.rows([(display, [], ["code": "0x" + VCPPolicy.hex(code), "current": Int(r.current),
                                                               "max": Int(r.max)])], json: true, none: "", ctx)
                }
                return .ok("\(r.current)/\(r.max)")
            default:
                guard let code = VCPPolicy.parseCode(parsed.values[0]),
                      let value = Self.parseValue(parsed.values[1]) else {
                    return .failure(ControlExit.usage, L("Usage: ddc set <code> <value>"))
                }
                // Power is allowed with ddcPower; other raw writes need ddcCustom (or a standard control).
                let standard = VCPPolicy.continuousCodes.contains(code) && self.effective.contains(.ddcControls)
                let power = code == VCPPolicy.power && self.effective.contains(.ddcPower)
                guard standard || power || self.effective.contains(.ddcCustom) else {
                    return .failure(ControlExit.unavailable, L("Turn on Custom controls in Hardware Controls › Advanced for raw writes"))
                }
                if code == VCPPolicy.power, value != VCPPolicy.powerOn,
                   !ctx.registry.displays.contains(where: { $0.key != display.key && $0.isOnline && $0.isStronglyVisible }) {
                    return .failure(ControlExit.refused, L("That's the only display you can see"))
                }
                let outcome = await self.writeOutcome(code, value, to: display.key)
                guard outcome == .done else { return .failure(outcome.exitCode, Self.message(outcome)) }
                if request.json {
                    return DisplayTargets.rows([(display, [], ["code": "0x" + VCPPolicy.hex(code), "value": Int(value)])],
                                               json: true, none: "", ctx)
                }
                return .ok()
            }
        }
    }

    /// "50", "0x32", "32h" → a 16-bit value.
    static func parseValue(_ text: String) -> UInt16? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let v = UInt16(t) { return v }
        var hex = t
        if hex.hasPrefix("0x") { hex.removeFirst(2) } else if hex.hasSuffix("h") { hex.removeLast() } else { return nil }
        guard (1...4).contains(hex.count) else { return nil }
        return UInt16(hex, radix: 16)
    }

    private static func message(_ outcome: WriteOutcome) -> String {
        switch outcome {
        case .done: return ""
        case .refused: return L("Snaptic doesn’t send that command, or it’s locked for this display (Hardware Controls › Advanced)")
        case .declined: return L("Not confirmed")
        case .failed: return L("The display didn’t accept it or didn’t reply")
        }
    }

    private func setLevelCommand(_ code: UInt8, _ request: ControlRequest) async -> ControlResponse {
        guard let ctx = context else { return DisplayTargets.notRunning() }
        let usage = L("Usage: <percent|+n|-n> [display]. ") + DisplayTargets.usage
        let (parsed, error) = DisplayTargets.cliArguments(request.arguments, valueCount: 1, usage: usage, ctx)
        guard let parsed else { return error ?? .failure(ControlExit.usage, usage) }
        guard effective.contains(.ddcControls) else { return .failure(ControlExit.unavailable, L("Hardware controls are off")) }
        let displays = DisplayTargets.resolve(parsed.target, ctx).filter { ctx.ddc.isAvailable($0.key) && isControlEnabled(code, for: $0.key) }
        guard !displays.isEmpty else { return .failure(ControlExit.notFound, L("No display with hardware controls has that control")) }
        var written: [(display: DisplayInfo, text: [String], json: [String: Any])] = []
        for d in displays {
            let live = ctx.runtime.runtime(for: d.key)
            let current = (code == VCPPolicy.volume ? live.volume : live.contrast) ?? 0.5
            guard let v = DisplayTargets.level(parsed.values[0], current: current) else {
                return .failure(ControlExit.usage, L("Not a value"))
            }
            let outcome = await writeOutcome(code, raw(d.key, code, fraction: v), to: d.key)
            guard outcome == .done else { return .failure(outcome.exitCode, Self.message(outcome)) }
            if code == VCPPolicy.volume { live.volume = v } else { live.contrast = v }
            written.append((d, [], [code == VCPPolicy.volume ? "volume" : "contrast": Int((v * 100).rounded())]))
        }
        guard request.json, let ctx = context else { return .ok() }
        return DisplayTargets.rows(written, json: true, none: L("No display with hardware controls has that control"), ctx)
    }

    /// Reads the control fresh (falls back to the last value seen).
    private func getLevelCommand(_ code: UInt8, _ request: ControlRequest) async -> ControlResponse {
        guard let ctx = context else { return DisplayTargets.notRunning() }
        let what = code == VCPPolicy.volume ? "volume" : "contrast"
        let usage = L("Usage: get \(what) [display]. ") + DisplayTargets.usage
        let (parsed, error) = DisplayTargets.cliArguments(request.arguments, valueCount: 0, default: .all, usage: usage, ctx)
        guard let parsed else { return error ?? .failure(ControlExit.usage, usage) }
        guard effective.contains(.ddcControls) else { return .failure(ControlExit.unavailable, L("Hardware controls are off")) }
        let displays = DisplayTargets.resolve(parsed.target, ctx).filter { ctx.ddc.isAvailable($0.key) && isControlEnabled(code, for: $0.key) }
        var rows: [(display: DisplayInfo, text: [String], json: [String: Any])] = []
        for d in displays {
            let reading = await ctx.ddc.read(code, from: d.key) ?? ctx.ddc.lastReading(code, of: d.key)
            guard let reading, reading.max > 0 else { continue }
            let percent = Int((fraction(d.key, code, reading) * 100).rounded())
            var text = ["\(percent)%"]
            var json: [String: Any] = [what: percent, "raw": Int(reading.current), "max": Int(reading.max)]
            if code == VCPPolicy.volume, let muted = self.context?.runtime.runtime(for: d.key).muted {
                text.append(muted ? "muted" : "unmuted")
                json["muted"] = muted
            }
            rows.append((d, text, json))
        }
        guard let ctx = context else { return DisplayTargets.notRunning() }
        return DisplayTargets.rows(rows, json: request.json, none: L("No display with hardware controls has that control"), ctx)
    }

    private func getInputCommand(_ request: ControlRequest) async -> ControlResponse {
        guard let ctx = context else { return DisplayTargets.notRunning() }
        let usage = L("Usage: get input [display]. ") + DisplayTargets.usage
        let (parsed, error) = DisplayTargets.cliArguments(request.arguments, valueCount: 0, default: .all, usage: usage, ctx)
        guard let parsed else { return error ?? .failure(ControlExit.usage, usage) }
        guard effective.contains(.ddcInput) else { return .failure(ControlExit.unavailable, L("Input switching is off")) }
        let displays = DisplayTargets.resolve(parsed.target, ctx).filter { ctx.ddc.isAvailable($0.key) }
        var rows: [(display: DisplayInfo, text: [String], json: [String: Any])] = []
        for d in displays {
            let fresh = await ctx.ddc.read(VCPPolicy.input, from: d.key).map { $0.current & 0xFF }
            guard let value = fresh ?? context?.runtime.runtime(for: d.key).input else { continue }
            if fresh != nil { context?.runtime.runtime(for: d.key).input = value }
            let entry = inputList(for: d.key, includeHidden: true).first { $0.value == value && !$0.lgAlt }
            let name = entry.map { inputName($0) } ?? VCPPolicy.inputName(value)
            let hex = "0x" + VCPPolicy.hex(UInt8(truncatingIfNeeded: value))
            let available = inputList(for: d.key).map { inputName($0) }
            rows.append((d, [name, hex, available.joined(separator: ", ")], ["input": name, "value": Int(value), "inputs": available]))
        }
        guard let ctx = context else { return DisplayTargets.notRunning() }
        return DisplayTargets.rows(rows, json: request.json, none: L("No display with hardware controls matches"), ctx)
    }

    // MARK: Diagnostics (DDC caps appear when ddc is active)

    func diagnostics() -> [(String, String)] {
        guard let context else { return [] }
        var rows: [(String, String)] = [("Readback", context.config.value.ddc.readback ? "on" : "off")]
        for (index, d) in context.registry.displays.filter({ $0.isOnline && !$0.isBuiltin }).enumerated() {
            let ddc = context.ddc
            let status: String
            switch ddc.linkStatus(d.key) {
            case .ok: status = "ok"
            case .failed: status = "no reply"
            case .unknown: status = "not probed"
            }
            var parts = ["\(status)", ddc.transportDescription(d.key) ?? "-", "framing \(ddc.framing(d.key)?.rawValue ?? "-")",
                         "writes today \(ddc.writesToday(d.key))"]
            if let caps = ddc.cachedCapabilities(d.key) {
                parts.append("caps \(caps.vcp.keys.sorted().map { VCPPolicy.hex($0) }.joined(separator: " "))")
                if let mccs = caps.mccsVersion { parts.append("MCCS \(mccs)") }
            }
            rows.append(("Display \(index + 1)", parts.joined(separator: ", ")))
        }
        return rows
    }
}
