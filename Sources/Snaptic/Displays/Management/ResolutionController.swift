import AppKit
import Combine
import SnapticKit

/// Resolution, "Show all modes" and "Match UI size" (PLAN §9.1, R5.3, R5.4).
@MainActor final class ResolutionController: DisplayFeatureController, PanicParticipant, SessionParticipant,
    DiagnosticsContributor {
    static var id: DisplayControllerID { .resolution }
    static var privateSymbols: [PrivateSymbol] { [] }
    /// Resolution settings and each display's filters, favorites and remembered choice (0.3 §4.5).
    static var observedSections: Set<DisplaysConfigSection> { [.resolution, .perDisplayResolution] }
    /// Weak: controllers outlive module restarts; never keep the context strongly.
    weak var context: DisplaysContext?

    private struct History {
        var undo: [ModeRef] = []
        var redo: [ModeRef] = []
    }

    private enum HistoryMove { case normal, undo, redo }

    private var lifetime: Lifetime?
    private(set) var effective: Set<DisplayFeature> = []
    private var menu: ResolutionMenuItems?
    private var history: [DisplayKey: History] = [:]
    /// When Snaptic last set each display's mode. Panic forgets the persisted choice of the
    /// ones set in the last 60 s; B's queue reverts the modes themselves (`panicRevert`).
    private var recent: [DisplayKey: Double] = [:]
    /// Mode changes seen before this uptime are panic's revert, not the user's: never learned.
    private var ignoreChangesUntil: Double = 0
    /// Our own changes in flight, so learning ignores them.
    private var expected: [DisplayKey: (mode: ModeRef, at: Double)] = [:]
    private var lastSeen: [DisplayKey: ModeRef] = [:]
    private var learning: [DisplayKey: DispatchWorkItem] = [:]
    private var sinks: [AnyCancellable] = []
    private var learnedCount = 0
    private var paused = false
    /// Public mode lists per display id; CGDisplayCopyAllDisplayModes is too slow to call per
    /// menu item. Cleared on every registry change (reconfiguration, hot-plug).
    private var modeCache: [UInt32: [DisplayModeDescriptor]] = [:]

    init() {}

    func availability(of feature: DisplayFeature, context: DisplaysContext) -> FeatureAvailability {
        // Hidden modes depend on private CGS symbols; PrivateDisplayAPI's probe makes the
        // feature unavailable when they're missing (B registers them).
        .available
    }

    func start(_ context: DisplaysContext, lifetime: Lifetime, effective: Set<DisplayFeature>) {
        guard self.lifetime !== lifetime else { return }
        if self.lifetime != nil { stop() }
        self.context = context
        self.lifetime = lifetime
        self.effective = effective
        let items = ResolutionMenuItems(context: context)
        items.controller = self
        menu = items
        context.menus.register(items, lifetime: lifetime)
        context.registerPanic(self, lifetime: lifetime)
        context.registerSession(self, lifetime: lifetime)
        context.diagnostics.register(self, section: L("Resolution"), lifetime: lifetime)
        context.connectPlanner.attach(self, lifetime: lifetime)
        registerActions(context, lifetime: lifetime)
        registerCommands(context, lifetime: lifetime)
        for d in context.registry.displays { if let m = currentMode(d) { lastSeen[d.key] = m } }
        context.registry.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] displays in MainActor.assumeIsolated { self?.observe(displays) } }
            .store(in: &sinks)
        // Every Snaptic transaction's mode changes are ours: learning ignores them (R5.3).
        context.transactions.observe(lifetime: lifetime) { [weak self] report in
            guard let self, let ctx = self.context, report.outcome == .applied || report.outcome == .kept else { return }
            for change in report.changes {
                guard case .mode(let id, let ref) = change, let key = ctx.registry.key(forDisplayID: id) else { continue }
                self.expected[key] = (ref, report.at)
                self.learning[key]?.cancel()
                self.learning[key] = nil
            }
        }
    }

    func effectiveFeaturesDidChange(_ effective: Set<DisplayFeature>) {
        self.effective = effective
        changed()
    }

    func configDidChange(from old: DisplaysConfig, to new: DisplaysConfig) {
        if old.resolution != new.resolution || old.perDisplay != new.perDisplay { changed() }
    }

    /// Page-visible state changed (mode lists, undo and redo, favorites): one revision bump and a menu rebuild.
    private func changed() {
        context?.runtime.revision(Self.id).bump()
        context?.requestMenuRebuild()
    }

    func stop() {
        sinks.removeAll()
        learning.values.forEach { $0.cancel() }
        learning = [:]
        expected = [:]
        modeCache = [:]
        ignoreChangesUntil = 0
        menu = nil
        lifetime = nil
        context = nil
        effective = []
    }

    // MARK: Session / panic

    func sessionDidPause() {
        paused = true
        learning.values.forEach { $0.cancel() }
        learning = [:]
    }

    func sessionDidResume() { paused = false }

    /// R5.3/R5.4 row: forget the persisted choice of modes Snaptic set in the last 60 s, so
    /// the next connect doesn't re-apply what panic just undid. The revert itself is the
    /// queue's (`DisplayTransactionQueue.panicRevert`), which runs before the participants.
    func panicRestore() {
        let now = managementUptime()
        for (key, at) in recent where now - at <= 60 {
            updatePerDisplay(key) { $0.persisted = nil }
        }
        recent = [:]
        // Panic's revert is a Snaptic change too; learning must not record it.
        learning.values.forEach { $0.cancel() }
        learning = [:]
        ignoreChangesUntil = now + 5
    }

    // MARK: Mode lists

    func info(_ key: DisplayKey) -> DisplayInfo? { context.flatMap { ManagedDisplays.info($0, key: key) } }

    func currentMode(_ d: DisplayInfo) -> ModeRef? { d.currentMode?.ref ?? ManagedModes.current(for: d.desktopID)?.ref }

    /// Every desktop-usable public mode of a display, largest first (cached).
    func allModes(_ d: DisplayInfo) -> [DisplayModeDescriptor] { allModes(displayID: d.desktopID) }

    func allModes(displayID: UInt32) -> [DisplayModeDescriptor] {
        if let cached = modeCache[displayID] { return cached }
        let list = ManagedModes.modes(for: displayID)
        if displayID != 0 && !list.isEmpty { modeCache[displayID] = list }
        return list
    }

    private func perDisplay(_ key: DisplayKey) -> PerDisplayResolution {
        context?.config.value.perDisplay[key]?.resolution ?? PerDisplayResolution()
    }

    private func updatePerDisplay(_ key: DisplayKey, _ change: (inout PerDisplayResolution) -> Void) {
        guard let ctx = context else { return }
        var value = ctx.config.value
        var pd = value.perDisplay[key] ?? PerDisplayConfig()
        change(&pd.resolution)
        pd.resolution = pd.resolution.sanitized()
        value.perDisplay[key] = pd
        ctx.config.value = value
    }

    /// Every public, desktop-usable mode for the menu and page, filtered by the display's
    /// filters and range limit and the 720p rule. The current mode is always included.
    func modes(for key: DisplayKey) -> [DisplayModeDescriptor] {
        guard let ctx = context, let d = info(key) else { return [] }
        let all = allModes(d)
        let settings = ctx.config.value.resolution
        let pd = perDisplay(key)
        let current = currentMode(d)
        return all.filter { m in
            if m.ref == current { return true }
            if !settings.allowBelow720p && min(m.ref.pointHeight, m.ref.pointWidth) < 720 && !m.isNative { return false }
            switch pd.dpiFilter {
            case .all: break
            case .hiDPIOnly: if !m.isHiDPI { return false }
            case .loDPIOnly: if m.isHiDPI { return false }
            }
            if let r = pd.refreshFilter, abs(m.ref.refreshMilliHz - r) > 500 { return false }
            return pd.inRange(m.ref)
        }
    }

    /// Slider stops: same HiDPI class and refresh as the current mode, native aspect if set,
    /// smallest first (parity §2.2).
    func sliderModes(for key: DisplayKey) -> [ModeRef] {
        guard let ctx = context, let d = info(key), let current = currentMode(d) else { return [] }
        var list = modes(for: key)
        if ctx.config.value.resolution.sliderNativeAspectOnly { list = ManagedModes.nativeAspect(list) }
        var stops: [Int: ModeRef] = [:]
        for m in list where m.isHiDPI == current.isHiDPI {
            let existing = stops[m.ref.pointWidth]
            if existing == nil || abs(m.ref.refreshMilliHz - current.refreshMilliHz) < abs(existing!.refreshMilliHz - current.refreshMilliHz) {
                stops[m.ref.pointWidth] = m.ref
            }
        }
        stops[current.pointWidth] = current
        return stops.keys.sorted().compactMap { stops[$0] }
    }

    func label(_ m: ModeRef, markers: Bool = true, key: DisplayKey? = nil) -> String {
        if markers, let key, let d = info(key), let descriptor = allModes(d).first(where: { $0.ref == m }) {
            return label(descriptor)
        }
        return Self.plainLabel(m)
    }

    /// Size, HiDPI, refresh, bit depth (when not 8) and the native/default markers.
    func label(_ d: DisplayModeDescriptor) -> String {
        var text = Self.plainLabel(d.ref)
        if d.bitDepth > 8 { text += " · " + L("\(d.bitDepth)-bit") }
        if d.isNative { text += " · " + L("Native") }
        if d.isDefault { text += " · " + L("Default") }
        return text
    }

    static func plainLabel(_ m: ModeRef) -> String {
        var text = "\(m.pointWidth) × \(m.pointHeight)"
        if m.isHiDPI { text += " HiDPI" }
        if m.refreshMilliHz > 0 { text += String(format: " · %.0f Hz", Double(m.refreshMilliHz) / 1000) }
        return text
    }

    /// The slider's value text: the size, or the percent of the default mode's width.
    func sliderValueText(_ m: ModeRef, key: DisplayKey) -> String {
        guard context?.config.value.resolution.sliderLabel == .percent, let def = defaultMode(key), def.pointWidth > 0 else {
            return Self.plainLabel(m)
        }
        return String(format: "%.0f%%", Double(m.pointWidth) / Double(def.pointWidth) * 100)
    }

    /// Slider snapping (parity §2.2): a stop next to a favorite, the current, default or native
    /// mode lands on it. ⌥ (or the setting) bypasses.
    func snappedStop(_ index: Int, in stops: [ModeRef], key: DisplayKey, bypass: Bool) -> Int {
        guard !bypass, context?.config.value.resolution.sliderSnapping == true, stops.indices.contains(index),
              let d = info(key) else { return index }
        let all = allModes(d).map(\.ref)
        var targets = Set(favorites(key).compactMap { $0.resolve(in: all) })
        [currentMode(d), defaultMode(key), native(key)].compactMap { $0 }.forEach { targets.insert($0) }
        if targets.contains(stops[index]) { return index }
        for j in [index - 1, index + 1] where stops.indices.contains(j) && targets.contains(stops[j]) { return j }
        return index
    }

    // MARK: Changes

    /// Applies a mode through the transaction queue (known-good rules decide low vs trial).
    func apply(_ mode: ModeRef, to key: DisplayKey, label text: String? = nil) {
        apply(mode, to: key, label: text, move: .normal)
    }

    private func apply(_ mode: ModeRef, to key: DisplayKey, label text: String?, move: HistoryMove) {
        guard let ctx = context, let lifetime, effective.contains(.resolution), let d = info(key) else { return }
        let before = currentMode(d)
        guard mode != before else { return }
        // The queue's classifier raises this to a trial per "Confirm resolution changes" (B).
        let request = TransactionRequest(label: text ?? L("Change resolution"), risk: .low,
                                         changes: [.mode(d.desktopID, mode)], finalScope: .permanently)
        ctx.connectPlanner.beginUserChange()
        expected[key] = (mode, managementUptime())
        ManagedTransactions.submit(ctx, request, lifetime: lifetime) { [weak self] outcome in
            guard let self else { return }
            let ok = outcome == .applied || outcome == .kept
            self.context?.connectPlanner.endUserChange(changed: ok)
            guard ok else { return }
            self.recorded(key, applied: mode, before: before, move: move)
        }
    }

    private func recorded(_ key: DisplayKey, applied: ModeRef, before: ModeRef?, move: HistoryMove) {
        guard let ctx = context else { return }
        if let before {
            var h = history[key] ?? History()
            switch move {
            case .normal:
                h.undo.append(before)
                h.redo = []
            case .undo:
                h.redo.append(before)
            case .redo:
                h.undo.append(before)
            }
            if h.undo.count > ResolutionConfig.maxUndo { h.undo.removeFirst(h.undo.count - ResolutionConfig.maxUndo) }
            if h.redo.count > ResolutionConfig.maxUndo { h.redo.removeFirst(h.redo.count - ResolutionConfig.maxUndo) }
            history[key] = h
            recent[key] = managementUptime()
            if !ctx.safeMode.isActive && ctx.config.value.resolution.persistedChoice {
                updatePerDisplay(key) {
                    $0.persisted = PersistedModeChoice(mode: applied, preKeepMode: before, recordedAt: managementWallClock())
                }
            }
        }
        lastSeen[key] = applied
        if let d = info(key) { ctx.osd.show(.resolution, text: label(applied, markers: false), on: d.desktopID) }
        changed()
    }

    /// "Show all modes": a hidden (CGS) mode, always a trial, never persisted or learned.
    func tryHiddenMode(_ mode: ModeRef, on key: DisplayKey) {
        guard let ctx = context, let lifetime, effective.contains(.hiddenModes), let d = info(key) else { return }
        ctx.connectPlanner.beginUserChange()
        expected[key] = (mode, managementUptime())
        ManagedTransactions.submit(ctx, TransactionRequest(label: L("Try hidden mode"), risk: .trial, changes: [.mode(d.desktopID, mode)]),
                                   lifetime: lifetime) { [weak self] outcome in
            self?.context?.connectPlanner.endUserChange(changed: outcome == .applied || outcome == .kept)
        }
    }

    func canUndo(_ key: DisplayKey) -> Bool { !(history[key]?.undo.isEmpty ?? true) }
    func canRedo(_ key: DisplayKey) -> Bool { !(history[key]?.redo.isEmpty ?? true) }

    func undo(_ key: DisplayKey) {
        guard var h = history[key], let target = h.undo.popLast() else { return }
        history[key] = h
        changed()
        apply(target, to: key, label: L("Undo resolution change"), move: .undo)
    }

    func redo(_ key: DisplayKey) {
        guard var h = history[key], let target = h.redo.popLast() else { return }
        history[key] = h
        changed()
        apply(target, to: key, label: L("Redo resolution change"), move: .redo)
    }

    func step(_ key: DisplayKey, by delta: Int) {
        guard let d = info(key), let current = currentMode(d) else { return }
        let stops = sliderModes(for: key)
        guard let i = stops.firstIndex(of: current) else { return }
        let j = min(stops.count - 1, max(0, i + delta))
        if j != i { apply(stops[j], to: key) }
    }

    func native(_ key: DisplayKey) -> ModeRef? {
        guard let d = info(key) else { return nil }
        let all = allModes(d)
        guard let n = ManagedModes.native(in: all) else { return nil }
        // The 1:1 mode: points == pixels at the native pixel size, else the native-flagged one.
        return all.first { $0.ref.pointWidth == n.ref.pixelWidth && $0.ref.pixelWidth == n.ref.pixelWidth && !$0.isHiDPI }?.ref ?? n.ref
    }

    func defaultMode(_ key: DisplayKey) -> ModeRef? {
        guard let d = info(key) else { return nil }
        return allModes(d).first(where: \.isDefault)?.ref
    }

    /// Native pixels at 2× (the "native-halved HiDPI" mode).
    func nativeHalved(_ key: DisplayKey) -> ModeRef? {
        guard let d = info(key), let n = native(key) else { return nil }
        return allModes(d).first {
            $0.isHiDPI && $0.ref.pixelWidth == n.pixelWidth && $0.ref.pointWidth * 2 == n.pixelWidth
        }?.ref
    }

    func hiDPIToggleTarget(_ key: DisplayKey) -> ModeRef? {
        guard let d = info(key), let current = currentMode(d) else { return nil }
        let other = allModes(d).map(\.ref).filter { $0.isHiDPI != current.isHiDPI }
        let same = other.filter { $0.pointWidth == current.pointWidth && $0.pointHeight == current.pointHeight }
        let pool = same.isEmpty ? other : same
        return pool.min { a, b in
            (abs(a.pointWidth - current.pointWidth), abs(a.refreshMilliHz - current.refreshMilliHz))
                < (abs(b.pointWidth - current.pointWidth), abs(b.refreshMilliHz - current.refreshMilliHz))
        }
    }

    /// The notched/notch-free counterpart on displays with a camera housing (§14 of the API notes).
    func notchToggleTarget(_ key: DisplayKey) -> ModeRef? {
        guard let d = info(key), d.notchInset > 0, let current = currentMode(d) else { return nil }
        let inset = Int(d.notchInset.rounded())
        return allModes(d).map(\.ref).first { m in
            m.pointWidth == current.pointWidth && m.isHiDPI == current.isHiDPI && m.refreshMilliHz == current.refreshMilliHz
                && m.pointHeight != current.pointHeight && abs(abs(m.pointHeight - current.pointHeight) - inset) <= 6
        }
    }

    func favorites(_ key: DisplayKey) -> [FavoriteMode] { perDisplay(key).favorites }

    func applyFavorite(_ index: Int, on key: DisplayKey) {
        let favs = favorites(key)
        guard favs.indices.contains(index), let d = info(key) else { return }
        guard let ref = favs[index].resolve(in: allModes(d).map(\.ref)) else {
            context?.toasts.show(L("Favorite \(index + 1) isn't available on this display"), lifetime: lifetime)
            return
        }
        apply(ref, to: key, label: L("Apply favorite resolution"))
    }

    func saveFavorite(_ mode: ModeRef, on key: DisplayKey) {
        updatePerDisplay(key) { pd in
            let f = FavoriteMode(mode)
            guard !pd.favorites.contains(f) else { return }
            if pd.favorites.count >= PerDisplayResolution.maxFavorites { pd.favorites.removeFirst() }
            pd.favorites.append(f)
        }
    }

    func removeFavorite(_ f: FavoriteMode, on key: DisplayKey) {
        updatePerDisplay(key) { $0.favorites.removeAll { $0 == f } }
    }

    // MARK: Match UI size

    func scaleMatchProposals() -> [ScaleMatchProposal] {
        guard let ctx = context else { return [] }
        let displays = ctx.registry.displays.filter { $0.isActive && $0.mirrorOf == nil }
        func entry(_ d: DisplayInfo) -> ScaleMatchDisplay? {
            guard let current = currentMode(d) else { return nil }
            let rotated = d.rotation == 90 || d.rotation == 270
            let widthMM = Double(rotated ? d.physicalSizeMM.height : d.physicalSizeMM.width)
            return ScaleMatchDisplay(key: d.key, widthMM: widthMM, current: current, candidates: modes(for: d.key).map(\.ref))
        }
        let refKey = ctx.config.value.resolution.scaleMatchReference ?? displays.first(where: \.isMain)?.key
        guard let refDisplay = displays.first(where: { $0.key == refKey }), let reference = entry(refDisplay) else { return [] }
        let targets = displays.filter { $0.key != refDisplay.key && perDisplay($0.key).matchUIScale }.compactMap(entry)
        return ScaleMatch.plan(reference: reference, targets: targets, tolerance: ctx.config.value.resolution.scaleMatchTolerance)
    }

    /// Applies once: a preview toast, then one trial for all proposals (R5.4).
    func matchUIScale() {
        guard let ctx = context, let lifetime, effective.contains(.scaleMatch) else { return }
        let proposals = scaleMatchProposals()
        guard !proposals.isEmpty else {
            ctx.toasts.show(L("Text already looks the same size on every display"), lifetime: lifetime)
            return
        }
        let summary = proposals.compactMap { p in info(p.key).map { "\($0.name): \(label(p.to, markers: false))" } }.joined(separator: "; ")
        ctx.toasts.show(L("Match text size: \(summary)"), action: ToastAction(title: L("Apply")) { [weak self] in
            self?.applyScaleMatch(proposals)
        }, lifetime: lifetime)
    }

    func applyScaleMatch(_ proposals: [ScaleMatchProposal]) {
        guard context != nil, let lifetime else { return }
        lifetime.spawn { [weak self] in
            guard let self else { return }
            let outcome = await self.applyScaleMatchAwaiting(proposals)
            if let text = ManagedTransactions.message(outcome), !lifetime.isEnded, let ctx = self.context {
                ctx.toasts.show(text, lifetime: lifetime)
            }
        }
    }

    /// One trial for all proposals, awaited. `skipConfirmation`: `--yes` the user allowed.
    private func applyScaleMatchAwaiting(_ proposals: [ScaleMatchProposal], skipConfirmation: Bool = false) async -> TransactionOutcome {
        guard let ctx = context else { return .failed(L("Resolution is off")) }
        let changes: [DisplayChange] = proposals.compactMap { p in info(p.key).map { .mode($0.desktopID, p.to) } }
        guard !changes.isEmpty else { return .applied }
        var before: [DisplayKey: ModeRef] = [:]
        for p in proposals { if let d = info(p.key), let m = currentMode(d) { before[p.key] = m } }
        ctx.connectPlanner.beginUserChange()
        let outcome = await ManagedTransactions.run(ctx, TransactionRequest(label: L("Match text size"), risk: .trial, changes: changes,
                                                                           skipConfirmation: skipConfirmation))
        let ok = outcome == .applied || outcome == .kept
        ctx.connectPlanner.endUserChange(changed: ok)
        if ok, context === ctx {
            for p in proposals { recorded(p.key, applied: p.to, before: before[p.key], move: .normal) }
        }
        return outcome
    }

    // MARK: Persisted choice (ConnectPlanner step 4)

    func contribute(to inputs: inout ConnectInputs) {
        guard let ctx = context, ctx.config.value.resolution.persistedChoice, !managementAutomationPaused(ctx) else { return }
        inputs.persisted = ctx.registry.displays.compactMap { d in
            guard let p = perDisplay(d.key).persisted else { return nil }
            return PlanPersistedChoice(key: d.key, mode: p.mode, preKeepMode: p.preKeepMode)
        }
    }

    func restorePersisted(_ key: DisplayKey, mode: ModeRef) async {
        guard let ctx = context, let d = info(key) else { return }
        expected[key] = (mode, managementUptime())
        let outcome = await ManagedTransactions.run(ctx, TransactionRequest(label: L("Restore resolution"), risk: .restore,
                                                                           changes: [.mode(d.desktopID, mode)], automatic: true))
        if outcome == .applied || outcome == .kept { lastSeen[key] = mode }
    }

    func promptRestorePersisted(_ key: DisplayKey, mode: ModeRef) {
        guard let ctx = context, let lifetime, let d = info(key) else { return }
        ctx.toasts.show(L("Restore \(label(mode, markers: false)) on \(d.name)?"),
                        action: ToastAction(title: L("Restore")) { [weak self] in
                            guard let self, let ctx = self.context, let lifetime = self.lifetime, let d = self.info(key) else { return }
                            self.expected[key] = (mode, managementUptime())
                            ManagedTransactions.submit(ctx, TransactionRequest(label: L("Restore resolution"), risk: .trial,
                                                                               changes: [.mode(d.desktopID, mode)]),
                                                       lifetime: lifetime)
                        }, lifetime: lifetime)
    }

    // MARK: Learning (R5.3)

    private func observe(_ displays: [DisplayInfo]) {
        guard let ctx = context else { return }
        modeCache = [:]
        // Mode lists, the current mode and what Undo would do may all have changed.
        ctx.runtime.revision(Self.id).bump()
        let now = managementUptime()
        for d in displays where d.isActive {
            guard let m = currentMode(d) else { continue }
            let previous = lastSeen[d.key]
            lastSeen[d.key] = m
            guard let previous, previous != m, now >= ignoreChangesUntil else { continue }
            if let e = expected[d.key], now - e.at < 30 {
                if e.mode == m { expected[d.key] = nil }
                continue
            }
            guard !paused, !ctx.safeMode.isActive, ctx.config.value.resolution.persistedChoice else { continue }
            scheduleLearning(d.key, mode: m, previous: previous, changedAt: now)
        }
    }

    private func scheduleLearning(_ key: DisplayKey, mode: ModeRef, previous: ModeRef, changedAt: Double) {
        learning[key]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.learn(key, mode: mode, previous: previous, changedAt: changedAt) }
        }
        learning[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PersistedChoiceLearning.settleSeconds + 0.2, execute: work)
    }

    private func learn(_ key: DisplayKey, mode: ModeRef, previous: ModeRef, changedAt: Double) {
        learning[key] = nil
        guard let ctx = context, let d = info(key), currentMode(d) == mode,
              PersistedChoiceLearning.shouldLearn(changedAt: changedAt, now: managementUptime(),
                                                  lastConnectOrWake: ctx.connectPlanner.lastConnectOrWake,
                                                  causedBySnaptic: false) else { return }
        learnedCount += 1
        updatePerDisplay(key) { $0.persisted = PersistedModeChoice(mode: mode, preKeepMode: previous, recordedAt: managementWallClock()) }
        EventLog.shared.record(.resolution, "Learned a resolution choice made outside Snaptic")
    }

    // MARK: Actions and CLI

    private func registerActions(_ ctx: DisplaysContext, lifetime: Lifetime) {
        func add(_ id: DisplayActionID, _ title: String, _ feature: DisplayFeature = .resolution,
                 _ run: @escaping @MainActor (ResolutionController, DisplayKey) -> Void) {
            ctx.actions.register(Action(id: id, title: title, feature: feature, cliAllowed: true) { [weak self] target in
                guard let self, let ctx = self.context else { return }
                for d in ManagedDisplays.resolve(ctx, target) { run(self, d.key) }
            }, lifetime: lifetime)
        }
        add(.dResolutionUp, L("Increase Resolution")) { $0.step($1, by: 1) }
        add(.dResolutionDown, L("Decrease Resolution")) { $0.step($1, by: -1) }
        add(.dHiDPIToggle, ManagementText.hiDPIOnOff) { c, k in if let m = c.hiDPIToggleTarget(k) { c.apply(m, to: k) } }
        add(.dNativeMode, L("Native Resolution")) { c, k in if let m = c.native(k) { c.apply(m, to: k) } }
        add(.dDefaultMode, L("Default Resolution")) { c, k in if let m = c.defaultMode(k) { c.apply(m, to: k) } }
        add(.dNativeHalved, ManagementText.halfOfNativeResolution) { c, k in if let m = c.nativeHalved(k) { c.apply(m, to: k) } }
        add(.dResolutionUndo, L("Undo Resolution Change")) { $0.undo($1) }
        add(.dResolutionRedo, L("Redo Resolution Change")) { $0.redo($1) }
        add(.dNotchToggle, ManagementText.notchAreaOnOff) { c, k in if let m = c.notchToggleTarget(k) { c.apply(m, to: k) } }
        for n in 1...PerDisplayResolution.maxFavorites {
            add(.dFavorite(n), L("Favorite Resolution \(n)")) { $0.applyFavorite(n - 1, on: $1) }
        }
        ctx.actions.register(Action(id: .dMatchUI, title: ManagementText.matchTextSize, feature: .scaleMatch, cliAllowed: true) { [weak self] _ in
            self?.matchUIScale()
        }, lifetime: lifetime)
    }

    private func registerCommands(_ ctx: DisplaysContext, lifetime: Lifetime) {
        ctx.commands.register("mode", policy: .trial, offOnly: false, cliAllowed: true,
                              summary: L("mode list|up|down|hidpi|native|default|halved|undo|redo|notch [display] | mode set <display> WxH[@Hz] [hidpi|lodpi] | mode favorite N [display]"),
                              lifetime: lifetime) { [weak self] request, _ in
            guard let self else { return .failure(ControlExit.unavailable, L("Resolution is off")) }
            return await self.handleMode(request)
        }
        ctx.commands.register("match-ui", policy: .trial, offOnly: false, cliAllowed: true, summary: L("Match text size across displays"),
                              lifetime: lifetime) { [weak self] request, _ in
            guard let self, self.effective.contains(.scaleMatch) else { return .failure(ControlExit.unavailable, L("Match text size is off")) }
            let proposals = self.scaleMatchProposals()
            guard !proposals.isEmpty else { return .ok(L("Text already looks the same size on every display")) }
            // Awaited like `mode`: 0 kept, 6 declined or timed out.
            let outcome = await self.applyScaleMatchAwaiting(proposals, skipConfirmation: request.skipConfirmation)
            guard outcome == .applied || outcome == .kept else { return ManagedTransactions.response(outcome) }
            if request.json {
                let rows: [[String: Any]] = proposals.map {
                    ["key": $0.key.rawValue, "mode": Self.modeJSON($0.to, label: self.label($0.to, markers: false))]
                }
                return .ok(KitControl.jsonText(rows) ?? "[]")
            }
            return .ok(proposals.map { "\($0.key.rawValue) \(self.label($0.to, markers: false))" }.joined(separator: "\n"))
        }
    }

    /// `mode …` (README, FIXES-R3 10): `mode list|up|down|hidpi|native|default|halved|undo|redo|notch
    /// [display]`, `mode set <display> WxH[@Hz] [hidpi|lodpi]`, `mode favorite N [display]`.
    /// Every changing subcommand awaits its outcome: 0 applied or kept, 6 declined or timed out.
    private func handleMode(_ request: ControlRequest) async -> ControlResponse {
        guard let ctx = context else { return .failure(ControlExit.unavailable, L("Resolution is off")) }
        let args = request.arguments
        guard let sub = args.first?.lowercased() else { return .failure(ControlExit.usage, L("Usage: mode <subcommand> <display>")) }
        var favorite: Int?
        let selector: String
        if sub == "favorite" {
            guard args.count > 1, let n = Int(args[1]), (1...PerDisplayResolution.maxFavorites).contains(n), args.count <= 3 else {
                return .failure(ControlExit.usage, L("Usage: mode favorite <1-\(PerDisplayResolution.maxFavorites)> [display]"))
            }
            favorite = n
            selector = args.count > 2 ? args[2] : "main"
        } else {
            selector = args.count > 1 ? args[1] : "main"
        }
        let picked = ManagedDisplays.cliSelect(ctx, selector)
        if let error = picked.error { return error }
        let targets = picked.displays
        switch sub {
        case "list":
            if request.json { return .ok(KitControl.jsonText(listJSON(targets, ctx)) ?? "[]") }
            return .ok(targets.map { d in
                let current = currentMode(d)
                let lines = modes(for: d.key).map { (($0.ref == current) ? "* " : "  ") + label($0.ref, key: d.key) }
                return "\(d.name) [\(d.key.rawValue)]\n" + lines.joined(separator: "\n")
            }.joined(separator: "\n\n"))
        case "set":
            guard args.count > 2, let spec = Self.parseMode(Array(args.dropFirst(2))) else {
                return .failure(ControlExit.usage, L("Usage: mode set <display> WxH[@Hz] [hidpi|lodpi]"))
            }
            var picks: [(DisplayInfo, ModeRef)] = []
            for d in targets {
                let matches = allModes(d).map(\.ref).filter { m in
                    m.pointWidth == spec.width && m.pointHeight == spec.height && (spec.hiDPI.map { $0 == m.isHiDPI } ?? true)
                        && (spec.hz.map { abs(m.refreshMilliHz - $0) < 500 } ?? true)
                }
                guard let current = currentMode(d),
                      let pick = matches.min(by: { abs($0.refreshMilliHz - current.refreshMilliHz) < abs($1.refreshMilliHz - current.refreshMilliHz) })
                else { return .failure(ControlExit.notFound, L("No such mode on \(d.name)")) }
                picks.append((d, pick))
            }
            return await applyAll(picks.map { ($0.0, $0.1, L("Change resolution"), HistoryMove.normal) }, request: request, ctx)
        case "up", "down", "hidpi", "native", "default", "halved", "undo", "redo", "notch", "favorite":
            var plan: [(DisplayInfo, ModeRef, String, HistoryMove)] = []
            for d in targets {
                if let n = favorite {
                    let favs = favorites(d.key)
                    guard favs.indices.contains(n - 1), let ref = favs[n - 1].resolve(in: allModes(d).map(\.ref)) else {
                        return .failure(ControlExit.notFound, L("Favorite \(n) isn't available on \(d.name)"))
                    }
                    plan.append((d, ref, L("Apply favorite resolution"), .normal))
                } else if let t = cliTarget(sub, d) {
                    plan.append((d, t.mode, t.label, t.move))
                }
            }
            guard !plan.isEmpty else {
                return request.json ? .ok("[]") : .ok(L("Nothing to change"))
            }
            return await applyAll(plan, request: request, ctx)
        default:
            return .failure(ControlExit.usage, L("Unknown mode subcommand"))
        }
    }

    /// The mode a CLI subcommand moves `d` to; undo/redo take it off the history.
    private func cliTarget(_ sub: String, _ d: DisplayInfo) -> (mode: ModeRef, label: String, move: HistoryMove)? {
        let key = d.key
        let change = L("Change resolution")
        switch sub {
        case "up", "down":
            guard let current = currentMode(d) else { return nil }
            let stops = sliderModes(for: key)
            guard let i = stops.firstIndex(of: current) else { return nil }
            let j = min(stops.count - 1, max(0, i + (sub == "up" ? 1 : -1)))
            return j == i ? nil : (stops[j], change, .normal)
        case "hidpi": return hiDPIToggleTarget(key).map { ($0, change, .normal) }
        case "native": return native(key).map { ($0, change, .normal) }
        case "default": return defaultMode(key).map { ($0, change, .normal) }
        case "halved": return nativeHalved(key).map { ($0, change, .normal) }
        case "notch": return notchToggleTarget(key).map { ($0, change, .normal) }
        case "undo":
            guard var h = history[key], let target = h.undo.popLast() else { return nil }
            history[key] = h
            return (target, L("Undo resolution change"), .undo)
        case "redo":
            guard var h = history[key], let target = h.redo.popLast() else { return nil }
            history[key] = h
            return (target, L("Redo resolution change"), .redo)
        default: return nil
        }
    }

    /// Applies one mode per display in turn, each awaited; stops at the first that isn't
    /// applied or kept and reports it (6 when the panel was declined or timed out).
    private func applyAll(_ plan: [(DisplayInfo, ModeRef, String, HistoryMove)], request: ControlRequest,
                          _ ctx: DisplaysContext) async -> ControlResponse {
        var lines: [String] = []
        var rows: [[String: Any]] = []
        let order = DisplaySelectorResolver.ordered(ctx).map(\.key)
        for (d, mode, text, move) in plan {
            let outcome = await applyAwaiting(mode, to: d.key, label: text, move: move, skipConfirmation: request.skipConfirmation)
            guard outcome == .applied || outcome == .kept else { return ManagedTransactions.response(outcome) }
            lines.append("\(d.name): \(label(mode, markers: false))")
            rows.append(["display": (order.firstIndex(of: d.key) ?? -1) + 1, "name": TextSanitizer.clean(d.name, maxScalars: 64),
                         "key": d.key.rawValue, "mode": Self.modeJSON(mode, label: label(mode, markers: false)),
                         "outcome": ManagedTransactions.outcomeName(outcome)])
        }
        return request.json ? .ok(KitControl.jsonText(rows) ?? "[]") : .ok(lines.joined(separator: "\n"))
    }

    private func listJSON(_ targets: [DisplayInfo], _ ctx: DisplaysContext) -> [[String: Any]] {
        let order = DisplaySelectorResolver.ordered(ctx).map(\.key)
        return targets.map { d in
            let current = currentMode(d)
            let list: [[String: Any]] = modes(for: d.key).map { m in
                var o = Self.modeJSON(m.ref, label: label(m.ref, markers: false))
                o["current"] = m.ref == current
                return o
            }
            return ["display": (order.firstIndex(of: d.key) ?? -1) + 1, "name": TextSanitizer.clean(d.name, maxScalars: 64),
                    "key": d.key.rawValue, "modes": list]
        }
    }

    private static func modeJSON(_ m: ModeRef, label: String) -> [String: Any] {
        ["width": m.pointWidth, "height": m.pointHeight, "pixelWidth": m.pixelWidth, "pixelHeight": m.pixelHeight,
         "refreshHz": Double(m.refreshMilliHz) / 1000, "hidpi": m.isHiDPI, "label": label]
    }

    /// Applies and waits for the outcome (CLI). `skipConfirmation`: `--yes` the user allowed.
    private func applyAwaiting(_ mode: ModeRef, to key: DisplayKey, label text: String = L("Change resolution"),
                               move: HistoryMove = .normal, skipConfirmation: Bool = false) async -> TransactionOutcome {
        guard let ctx = context, effective.contains(.resolution), let d = info(key) else { return .failed(L("Display not found")) }
        let before = currentMode(d)
        if mode == before { return .applied }
        ctx.connectPlanner.beginUserChange()
        expected[key] = (mode, managementUptime())
        // The queue's classifier raises this to a trial per "Confirm resolution changes" (B).
        let outcome = await ManagedTransactions.run(ctx, TransactionRequest(label: text, risk: .low,
                                                                           changes: [.mode(d.desktopID, mode)], finalScope: .permanently,
                                                                           skipConfirmation: skipConfirmation))
        let ok = outcome == .applied || outcome == .kept
        ctx.connectPlanner.endUserChange(changed: ok)
        if ok { recorded(key, applied: mode, before: before, move: move) }
        return outcome
    }

    /// "2560x1440@60 hidpi" → size, optional refresh (milli-Hz) and optional HiDPI class.
    static func parseMode(_ args: [String]) -> (width: Int, height: Int, hz: Int?, hiDPI: Bool?)? {
        guard let first = args.first?.lowercased() else { return nil }
        let parts = first.split(separator: "@", maxSplits: 1).map(String.init)
        let size = parts[0].split(whereSeparator: { $0 == "x" || $0 == "×" }).map(String.init)
        guard size.count == 2, let w = Int(size[0]), let h = Int(size[1]), w > 0, h > 0, w <= 16384, h <= 16384 else { return nil }
        var hz: Int?
        if parts.count == 2 {
            guard let v = Double(parts[1]), v > 0, v <= 1000 else { return nil }
            hz = Int((v * 1000).rounded())
        }
        var hiDPI: Bool?
        for a in args.dropFirst() {
            switch a.lowercased() {
            case "hidpi": hiDPI = true
            case "lodpi": hiDPI = false
            default: return nil
            }
        }
        return (w, h, hz, hiDPI)
    }

    // MARK: Diagnostics

    func diagnostics() -> [(String, String)] {
        guard let ctx = context else { return [] }
        var rows: [(String, String)] = [(L("Features"), effective.map(\.rawValue).sorted().joined(separator: ", "))]
        for d in ctx.registry.displays {
            let current = currentMode(d).map { label($0, markers: false) } ?? L("unknown")
            let pd = perDisplay(d.key)
            rows.append((d.name, "\(current); \(modes(for: d.key).count) modes; favorites \(pd.favorites.count); "
                         + (pd.persisted == nil ? L("no persisted choice") : L("persisted choice"))))
        }
        rows.append((L("Learned choices this session"), String(learnedCount)))
        return rows
    }
}
