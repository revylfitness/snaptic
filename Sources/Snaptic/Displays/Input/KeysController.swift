import AppKit
import Combine
import CoreAudio
import SnapticKit

/// What the media-key tap may read off main: a lock-protected copy of everything the
/// per-press decision needs (PLAN §8.1, R3C §5.4).
final class KeyDecisionSnapshot: @unchecked Sendable {
    struct Display: Sendable {
        var key: DisplayKey
        /// CG global coordinates (top-left origin), as CGEvent.location reports.
        var bounds: CGRect
        var isBuiltin: Bool
        var isMain: Bool
        var isFocused: Bool
        /// macOS adjusts this display's brightness itself (built-in, Apple displays).
        var macControls: Bool
        /// Snaptic manages brightness here.
        var weControl: Bool
        var xdrEnabled: Bool
        var position: Double
        /// DDC volume works here.
        var volumeOK: Bool
        /// Name the volume policy matches against the sound output (sanitized, lowercased).
        var audioName: String
        var keysEnabled: Bool
    }

    struct State: Sendable {
        var brightnessKeys = false
        var volumeKeys = false
        var brightnessPolicy = KeyPolicy.uncontrollableOnly
        var brightnessAlsoSystem = false
        var volumeAlsoSystem = false
        var muteAlsoSystem = false
        var target = KeyTarget.pointer
        var volumePolicy = VolumePolicy.matchingOutput
        var outputName: String?
        var outputHasVolume = true
        var mirrorActionAvailable = false
        var displays: [Display] = []
    }

    private let lock = NSLock()
    private var state = State()

    func update(_ new: State) {
        lock.lock()
        state = new
        lock.unlock()
    }

    var current: State {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    static let shift: UInt64 = 0x20000
    static let control: UInt64 = 0x40000
    static let option: UInt64 = 0x80000
    static let command: UInt64 = 0x100000

    enum Intent: Equatable, Sendable {
        case none
        case openSettings
        case toggleMirror
        case adjust([DisplayKey])
    }

    /// Brightness targets for a press, honoring the modifier rules (PLAN §8.1).
    static func brightnessIntent(_ s: State, up: Bool, flags: UInt64, at location: CGPoint) -> (Intent, alsoSystem: Bool) {
        guard s.brightnessKeys else { return (.none, true) }
        let opt = flags & option != 0, sh = flags & shift != 0, ctl = flags & control != 0, cmd = flags & command != 0
        if opt && !sh && !ctl && !cmd { return (.openSettings, false) }
        if cmd && !opt && !sh && !ctl && !up { return s.mirrorActionAvailable ? (.toggleMirror, false) : (.none, true) }
        let pointer = s.displays.first { $0.bounds.contains(location) }
        var targets: [Display]
        if ctl && cmd {
            targets = s.displays.filter { !$0.isBuiltin }
        } else if ctl {
            targets = s.displays.filter(\.isBuiltin)
        } else if sh && cmd {
            targets = s.displays.filter { $0.key != pointer?.key }
        } else {
            switch s.target {
            case .pointer: targets = pointer.map { [$0] } ?? s.displays.filter(\.isMain)
            case .focusedWindow: targets = s.displays.filter(\.isFocused)
            case .all: targets = s.displays
            }
        }
        targets = targets.filter(\.keysEnabled)
        let xdrException: (Display) -> Bool = { d in
            d.xdrEnabled && d.weControl && ((up && d.position >= 0.999) || (!up && d.position > 1.0001))
        }
        let acting: [Display]
        switch s.brightnessPolicy {
        case .always:
            acting = targets.filter(\.weControl)
        case .uncontrollableOnly:
            acting = targets.filter { ($0.weControl && !$0.macControls) || xdrException($0) }
        }
        guard !acting.isEmpty else { return (.none, true) }
        // Displays macOS handles itself (and we don't) still get the key.
        let leftForMac = targets.contains { d in d.macControls && !acting.contains { $0.key == d.key } }
        return (.adjust(acting.map(\.key)), s.brightnessAlsoSystem || leftForMac)
    }

    /// Volume targets: by the sound output policy.
    static func volumeTargets(_ s: State, at location: CGPoint) -> [DisplayKey] {
        guard s.volumeKeys else { return [] }
        let capable = s.displays.filter { $0.volumeOK && $0.keysEnabled }
        guard !capable.isEmpty else { return [] }
        func byTarget() -> [Display] {
            switch s.target {
            case .pointer:
                return capable.filter { $0.bounds.contains(location) }.prefix(1).map { $0 }
            case .focusedWindow: return capable.filter(\.isFocused)
            case .all: return capable
            }
        }
        switch s.volumePolicy {
        case .matchingOutput:
            guard let output = s.outputName?.lowercased(), !output.isEmpty else { return [] }
            return capable.filter { !$0.audioName.isEmpty && (output.contains($0.audioName) || $0.audioName.contains(output)) }.map(\.key)
        case .noVolumeControl:
            return s.outputHasVolume ? [] : byTarget().map(\.key)
        case .always:
            return byTarget().map(\.key)
        }
    }

    /// The tap's verdict (tap thread).
    func verdict(_ key: MediaKeyService.Key, flags: UInt64, location: CGPoint) -> MediaKeyService.Verdict {
        let s = current
        switch key {
        case .brightnessUp, .brightnessDown:
            let (intent, alsoSystem) = Self.brightnessIntent(s, up: key == .brightnessUp, flags: flags, at: location)
            if intent == .none { return .pass }
            return alsoSystem ? .handleAndPass : .handle
        case .volumeUp, .volumeDown, .mute:
            guard !Self.volumeTargets(s, at: location).isEmpty else { return .pass }
            let also = key == .mute ? s.muteAlsoSystem : s.volumeAlsoSystem
            return also ? .handleAndPass : .handle
        }
    }
}

/// Brightness / volume keys (media-key tap), F14/F15 alternates and custom shortcuts for
/// every registered display action (PLAN §8.1, §8.2).
@MainActor final class KeysController: DisplayFeatureController, DiagnosticsContributor {
    static var id: DisplayControllerID { .keys }
    static var privateSymbols: [PrivateSymbol] { [] }

    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?
    private var lifetime: Lifetime?
    private var effective: Set<DisplayFeature> = []
    private let snapshot = KeyDecisionSnapshot()
    private var sinks: [AnyCancellable] = []
    private var pollTimer: Timer?
    private var hotkeyLifetime: Lifetime?
    /// Why a shortcut couldn't be registered, by action id (shown on the Keys page).
    private(set) var hotkeyProblems: [DisplayActionID: String] = [:]
    private var detentArmed: [DisplayKey: TimeInterval] = [:]
    private var output: (name: String?, hasVolume: Bool) = (nil, true)
    /// NSEvent monitors watching media keys while the tap can't run (no Accessibility).
    private var pressMonitors: [Any] = []
    /// Once per launch: the controller outlives module restarts.
    private var untrustedNotice = UntrustedKeyNotice()

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability { .available }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        context.diagnostics.register(self, section: L("Keys and shortcuts"), lifetime: lifetime)
        context.mediaKeys.keysController = self
        // W4: a grant made in System Settings starts the tap without a relaunch.
        context.permissions.observe(lifetime: lifetime) { [weak self] permission, granted in
            guard permission == .accessibility else { return }
            self?.accessibilityChanged(granted: granted)
        }
        context.registry.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refreshSnapshot() } }
            .store(in: &sinks)
        context.brightness.changeEvents
            .sink { [weak self] _ in self?.refreshSnapshot() }
            .store(in: &sinks)
        let poll = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAudio()
                self?.refreshSnapshot()
            }
        }
        poll.tolerance = 0.5
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll
        refreshAudio()
        configureTap()
        registerHotkeys()
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        self.effective = effective
        configureTap()
        registerHotkeys()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        if old.keys != new.keys || old.perDisplay.values.mapValues(\.keys) != new.perDisplay.values.mapValues(\.keys) {
            refreshSnapshot()
            if old.keys.shortcuts != new.keys.shortcuts || old.keys.alternateKeys != new.keys.alternateKeys { registerHotkeys() }
        }
    }

    func stop() {
        removePressMonitors()
        sinks.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        hotkeyLifetime?.end()
        hotkeyLifetime = nil
        hotkeyProblems = [:]
        if let context {
            if context.mediaKeys.keysController === self { context.mediaKeys.keysController = nil }
            context.mediaKeys.stop()
            context.mediaKeys.swallowPolicy = nil
            context.mediaKeys.onKey = nil
            context.mediaKeys.onRepeat = nil
            context.mediaKeys.onTrustLost = nil
        }
        snapshot.update(KeyDecisionSnapshot.State())
        lifetime = nil
        context = nil
    }

    // MARK: Tap

    var tapRunning: Bool { context?.mediaKeys.isRunning ?? false }

    private func configureTap() {
        guard let context else { return }
        refreshSnapshot()
        let wanted = effective.contains(.brightnessKeys) || effective.contains(.volumeKeys)
        guard wanted else {
            context.mediaKeys.stop()
            removePressMonitors()
            return
        }
        let snap = snapshot
        context.mediaKeys.swallowPolicy = { key, flags, location in snap.verdict(key, flags: flags, location: location) }
        context.mediaKeys.onKey = { [weak self] key, flags in self?.handle(key, flags: flags, isRepeat: false) }
        context.mediaKeys.onRepeat = { [weak self] key, flags in self?.handle(key, flags: flags, isRepeat: true) }
        context.mediaKeys.onTrustLost = { [weak self] in
            guard let self, let ctx = self.context else { return }
            ctx.toasts.show(L("Brightness and volume keys stopped: Snaptic lost the Accessibility permission."),
                            lifetime: self.lifetime)
        }
        if !context.mediaKeys.isRunning { context.mediaKeys.start() }
        updatePressMonitor()
    }

    /// Accessibility changed (PermissionFlow): start the tap on a grant; on a revoke the tap
    /// stops itself, and the press monitor explains the first ignored press.
    private func accessibilityChanged(granted: Bool) {
        guard context != nil else { return }
        let wanted = effective.contains(.brightnessKeys) || effective.contains(.volumeKeys)
        if granted, wanted, !tapRunning {
            EventLog.shared.record(.keys, "Accessibility granted: starting the media key tap")
            retryTap()
        } else {
            updatePressMonitor()
        }
    }

    /// While the keys are wanted but the tap can't run, watch presses (NSEvent monitors
    /// see them without Accessibility) to explain the first one Snaptic had to ignore.
    private func updatePressMonitor() {
        let wanted = effective.contains(.brightnessKeys) || effective.contains(.volumeKeys)
        guard let context, wanted, !tapRunning,
              untrustedNotice.wantsPresses(trusted: context.mediaKeys.isTrusted) else {
            removePressMonitors()
            return
        }
        guard pressMonitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.observedPress(event) }
        }) {
            pressMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .systemDefined, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.observedPress(event) }
            return event
        }) {
            pressMonitors.append(local)
        }
    }

    private func removePressMonitors() {
        pressMonitors.forEach { NSEvent.removeMonitor($0) }
        pressMonitors.removeAll()
    }

    /// A media key seen by the monitor: never acted on (macOS handles it), at most one toast.
    private func observedPress(_ event: NSEvent) {
        guard let context, event.type == .systemDefined,
              let press = MediaKeyPress.parse(subtype: Int(event.subtype.rawValue), data1: event.data1) else { return }
        let trusted = context.mediaKeys.isTrusted
        if trusted {
            // Granted without PermissionFlow noticing yet.
            context.permissions.refresh()
            if !tapRunning { retryTap() } else { removePressMonitors() }
            return
        }
        refreshSnapshot()
        let verdict = snapshot.verdict(press.key, flags: UInt64(event.modifierFlags.rawValue), location: Self.cgPointer())
        guard untrustedNotice.shouldShow(press, trusted: trusted, wouldAct: verdict != .pass) else { return }
        removePressMonitors()
        let name = DisplaysUIText.permissionName(.accessibility, osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        let isBrightness = press.key == .brightnessUp || press.key == .brightnessDown
        let message = isBrightness ? L("Brightness keys need \(name)") : L("Volume keys need \(name)")
        EventLog.shared.record(.keys, "Media key ignored: Accessibility not granted")
        context.toasts.show(message, action: ToastAction(title: L("Grant…")) { [weak self] in
            self?.context?.permissions.presentGuide(.accessibility, reason: L("Brightness and volume keys for your displays"))
        }, lifetime: lifetime)
    }

    /// Retries the tap after the permission was granted (Keys page button, PermissionFlow).
    func retryTap() {
        context?.mediaKeys.stop()
        removePressMonitors()
        configureTap()
    }

    private func refreshAudio() {
        guard effective.contains(.volumeKeys) else { return }
        output = Self.defaultOutput()
    }

    private func refreshSnapshot() {
        guard let context else { return }
        let config = context.config.value
        var state = KeyDecisionSnapshot.State()
        state.brightnessKeys = effective.contains(.brightnessKeys)
        state.volumeKeys = effective.contains(.volumeKeys)
        state.brightnessPolicy = config.keys.brightnessPolicy
        state.brightnessAlsoSystem = config.keys.brightnessAlsoSystem
        state.volumeAlsoSystem = config.keys.volumeAlsoSystem
        state.muteAlsoSystem = config.keys.muteAlsoSystem
        state.target = config.keys.target
        state.volumePolicy = config.keys.volumePolicy
        state.outputName = output.name
        state.outputHasVolume = output.hasVolume
        state.mirrorActionAvailable = mirrorAction() != nil
        let focused = NSScreen.main?.displayID
        for d in context.registry.displays where d.isOnline && d.isActive {
            let per = config.perDisplay[d.key]
            let caps = context.ddc.cachedCapabilities(d.key)
            let volumeOK = context.ddc.isAvailable(d.key) && (caps?.supports(VCPPolicy.volume) ?? (context.ddc.lastReading(VCPPolicy.volume, of: d.key) != nil))
            let audioName = TextSanitizer.clean(per?.keys.audioDeviceName ?? d.name, maxScalars: 64).lowercased()
            state.displays.append(KeyDecisionSnapshot.Display(
                key: d.key, bounds: CGDisplayBounds(d.mirrorOf ?? d.desktopID), isBuiltin: d.isBuiltin, isMain: d.isMain,
                isFocused: focused == d.desktopID,
                macControls: context.appleBrightness.isSupported(d.key) && context.brightness.hardwareMethod(for: d.key) != .ddc,
                weControl: context.brightness.value(for: d.key) != nil,
                xdrEnabled: per?.brightness.xdrEnabled ?? false, position: context.brightness.value(for: d.key) ?? 1,
                volumeOK: volumeOK, audioName: audioName, keysEnabled: per?.keys.keysEnabled ?? true))
        }
        snapshot.update(state)
    }

    /// D's mirroring toggle, when registered and its feature is on (⌘ + brightness down).
    private func mirrorAction() -> Action? {
        guard let context, let action = context.actions.action(.dMirrorToggle),
              context.runtime.isEffective(action.feature) else { return nil }
        return action
    }

    /// CGEvent-style location of the pointer (top-left origin).
    private static func cgPointer() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

    // MARK: Handling (main)

    private func handle(_ key: MediaKeyService.Key, flags: UInt64, isRepeat: Bool) {
        guard let context else { return }
        refreshSnapshot()
        let state = snapshot.current
        let location = Self.cgPointer()
        switch key {
        case .brightnessUp, .brightnessDown:
            let up = key == .brightnessUp
            let (intent, _) = KeyDecisionSnapshot.brightnessIntent(state, up: up, flags: flags, at: location)
            switch intent {
            case .none:
                return
            case .openSettings:
                if !isRepeat { context.openSettings("displays.brightness") }
            case .toggleMirror:
                // Through the registry, so the feature check applies.
                if !isRepeat, mirrorAction() != nil { context.actions.perform(.dMirrorToggle, on: .pointer) }
            case .adjust(let keys):
                let fine = flags & KeyDecisionSnapshot.option != 0 && flags & KeyDecisionSnapshot.shift != 0
                let skipSync = flags & KeyDecisionSnapshot.shift != 0 && flags & (KeyDecisionSnapshot.command | KeyDecisionSnapshot.option) == 0
                if skipSync { context.brightness.suppressSyncUntil = ProcessInfo.processInfo.systemUptime + 0.5 }
                let step = context.config.value.keys.step(fine: fine) * (up ? 1 : -1)
                for k in keys { adjustBrightness(k, by: step) }
            }
        case .volumeUp, .volumeDown:
            let fine = flags & KeyDecisionSnapshot.option != 0 && flags & KeyDecisionSnapshot.shift != 0
            let step = context.config.value.keys.step(fine: fine) * (key == .volumeUp ? 1 : -1)
            let action = DDCController.volumeAction(up: step > 0, fine: fine)
            for k in KeyDecisionSnapshot.volumeTargets(state, at: location) { context.actions.perform(action, on: .display(k)) }
        case .mute:
            guard !isRepeat else { return }
            for k in KeyDecisionSnapshot.volumeTargets(state, at: location) {
                context.actions.perform(DDCController.muteAction, on: .display(k))
            }
        }
    }

    /// One brightness step with the XDR detent at 100% (hysteresis: a second press within 1 s).
    func adjustBrightness(_ key: DisplayKey, by delta: Double) {
        guard let context, let current = context.brightness.value(for: key), let display = context.registry.info(for: key)
        else { return }
        var next = current + delta
        if context.config.value.brightness.xdrDetent, context.brightness.range(for: key).upperBound > 1 {
            let now = ProcessInfo.processInfo.systemUptime
            let armed = detentArmed[key].map { now - $0 < 1 } ?? false
            let result = CombinedScale.applyDetent(from: current, to: next, armed: armed || current == 1)
            next = result.value
            if result.armDetent { detentArmed[key] = now } else if abs(current - 1) > 0.0001 { detentArmed[key] = nil }
        }
        context.brightness.set(next, for: key, source: .keys)
        Feedback.brightness(context, display)
    }

    // MARK: Shortcuts

    private func registerHotkeys() {
        hotkeyLifetime?.end()
        hotkeyLifetime = nil
        hotkeyProblems = [:]
        guard let context, let lifetime else { return }
        let life = lifetime.child()
        hotkeyLifetime = life
        let config = context.config.value.keys
        let menu = context.config.value.menu
        if effective.contains(.shortcuts) {
            for (id, combo) in config.shortcuts.values.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                // 0.3 step-0 interim (lead): migration M4 copies the panel and Identify shortcuts here while
                // OverviewController still registers them from MenuConfig; skip the same combo so it isn't
                // registered twice. Removed when OverviewController moves to these ids (F, step 1).
                if (id == .fShowPanel && combo == menu.showPanelShortcut) || (id == .fIdentify && combo == menu.identifyShortcut) {
                    continue
                }
                let title = context.actions.action(id)?.title ?? id.rawValue
                if let problem = PerDisplayEdit.registerHotkey(context, combo, owner: title, lifetime: life, action: { [weak self] in
                    guard let ctx = self?.context else { return }
                    // A registered action whose feature is off: the registry refuses it and shows its own toast.
                    guard ctx.actions.action(id) != nil else {
                        ctx.toasts.show(L("“\(title)” isn't available right now."), lifetime: self?.lifetime)
                        return
                    }
                    ctx.actions.perform(id, on: DisplayTargets.keyTarget(ctx))
                }) {
                    hotkeyProblems[id] = problem
                    EventLog.shared.record(.keys, "Shortcut not registered: \(problem)")
                }
            }
        }
        if effective.contains(.brightnessKeys), config.alternateKeys {
            // F14 / F15 as brightness down / up (Carbon hotkeys, never the tap).
            for (code, up) in [(UInt32(107), false), (UInt32(113), true)] {
                _ = PerDisplayEdit.registerHotkey(context, HotkeyCombo(keyCode: code, carbonModifiers: 0),
                                                  owner: up ? L("Brightness up (F15)") : L("Brightness down (F14)"),
                                                  lifetime: life) { [weak self] in
                    guard let self, let ctx = self.context else { return }
                    let step = ctx.config.value.keys.step(fine: false) * (up ? 1 : -1)
                    for d in DisplayTargets.resolve(DisplayTargets.keyTarget(ctx), ctx) { self.adjustBrightness(d.key, by: step) }
                }
            }
        }
    }

    /// Saves a shortcut for an action (nil removes it).
    func setShortcut(_ combo: HotkeyCombo?, for id: DisplayActionID) {
        guard let context else { return }
        context.config.value.keys.shortcuts[id] = combo
    }

    // MARK: Audio output

    static func defaultOutput() -> (name: String?, hasVolume: Bool) {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return (nil, true) }
        var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var result: String?
        if AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name) == noErr, let cf = name {
            result = TextSanitizer.clean(cf.takeRetainedValue() as String, maxScalars: 64)
        }
        var hasVolume = false
        for element in [kAudioObjectPropertyElementMain, 1] {
            var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                           mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var settable: DarwinBoolean = false
            if AudioObjectHasProperty(device, &volumeAddress) == true,
               AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr, settable.boolValue {
                hasVolume = true
                break
            }
        }
        return (result, hasVolume)
    }

    // MARK: Diagnostics (no key codes, no device names)

    func diagnostics() -> [(String, String)] {
        guard let context else { return [] }
        let state = snapshot.current
        let matched = !KeyDecisionSnapshot.volumeTargets(state, at: Self.cgPointer()).isEmpty
        return [
            ("Media key tap", tapRunning ? "running" : "stopped"),
            ("Accessibility", context.mediaKeys.isTrusted ? "granted" : "not granted"),
            ("Shortcuts registered", String(context.config.value.keys.shortcuts.values.count - hotkeyProblems.count)),
            ("Shortcut problems", String(hotkeyProblems.count)),
            ("Sound output has volume", output.hasVolume ? "yes" : "no"),
            ("Volume keys target a display now", matched ? "yes" : "no"),
        ]
    }
}
