import AppKit
import Combine
import SnapticKit

// The one row set of the Awake menu and the compact section in the Snaptic menu (owner: G; PLAN 0.3 §5.3, §5.4,
// design M1/M2, R5-10, R5-11). Kit's AwakeMenuModel decides which rows exist; this builder turns them into MenuKit
// items and keeps the switch header's state and detail current while a menu is open (N15). Every item has a native
// path (the switch header is mouse-only; Keep Awake / Turn Off Keep Awake are its keyboard and VoiceOver twins).
// The section uses no images except the app rows of "While an App Is Running", which are their own group.
// 0.3.1 A4, B1: the same rows in Awake's tab of the Snaptic menu (style `tab`), and the lid-closed rows in all three
// styles (a lid request starts only from these clicks, N19).

@MainActor final class AwakeMenuRows {
    typealias Controls = AwakeMenuRowsControls

    weak var context: AwakeContext?
    /// "Custom…" and "Add Time…".
    let custom = CustomSessionWindow()
    /// Header items of menus built since they last closed, updated in place.
    private var headers: [(item: NSMenuItem, lines: Int)] = []
    private var sinks: [AnyCancellable] = []

    init() {}

    init(context: AwakeContext) {
        self.context = context
        custom.context = context
        observe(context.runtime)
    }

    /// Attaches to a (new) context: the rows read and act on it.
    func attach(_ context: AwakeContext?) {
        self.context = context
        custom.context = context
        if context == nil { custom.close() }
        sinks.removeAll()
        headers = []
        if let context { observe(context.runtime) }
    }

    // MARK: Building

    /// The rows for the Awake menu (`compact == false`) or the compact section. `footer`: the Snaptic item is
    /// absent, so the own menu ends with Recent Notices › and Quit Snaptic (§5.2).
    func items(compact: Bool, footer: Bool = false) -> [NSMenuItem] {
        items(style: compact ? .compact : .own, footer: footer)
    }

    /// The rows in `style` (0.3.1 A4). `footerExtras` (the shared footer's Update Available row, E1) open the own
    /// menu's footer group.
    func items(style: AwakeMenuStyle, footer: Bool = false, footerExtras: [NSMenuItem] = []) -> [NSMenuItem] {
        headers.removeAll { $0.item.menu == nil }
        guard let ctx = context else { return [] }
        let rt = ctx.runtime
        let facts = AwakeMenuFacts(governing: rt.governing, holdsExist: !rt.holds.isEmpty,
                                   rulesShown: rulesShown(ctx), style: style)
        var out: [NSMenuItem] = []
        for row in Self.rows(facts, lid: Self.lidRow(ctx)) {
            switch row {
            case .header: out.append(header(ctx))
            case .startDefault: out.append(startDefault(ctx))
            case .turnOff:
                out.append(MenuKit.action(L("Turn Off Keep Awake"), control: ControlID("menu.awake.turnOff")) { [weak self] in
                    self?.context?.sessions.turnOff(source: .menu)
                })
            case .addTime(let seconds):
                out += addTime(seconds, ctx)
            case .keepDisplayOn:
                out.append(MenuKit.toggle(L("Keep Display On"), isOn: ctx.sessions.keepsDisplayOn,
                                          control: ControlID("menu.awake.keepDisplayOn")) { [weak self] in
                    // Read at the click, not when the menu was built (ui F2).
                    guard let sessions = self?.context?.sessions else { return }
                    sessions.setKeepDisplayOn(!sessions.keepsDisplayOn)
                })
            case .endHolds:
                out.append(MenuKit.action(L("End Command-Line Holds"), control: ControlID("menu.awake.endHolds")) { [weak self] in
                    self?.context?.sessions.endAllHolds(.user)
                })
            case .startSession: out.append(startSession(ctx))
            case .whileApp: out.append(whileApp(ctx))
            case .rules: out.append(rules(ctx))
            case .settings:
                out.append(MenuKit.settings(L("Awake Settings…"), control: ControlID("menu.awake.settings")) { [weak self] in
                    self?.context?.host.openSettings(SettingsRoute("awake"))
                })
            case .separator: out.append(MenuKit.separator())
            case .lidClosed(let state): out.append(lidItem(state))
            case .lidSubmenu(let ids): out.append(lidSubmenu(ids, ctx))
            }
        }
        if footer && style == .own { out += footerItems(ctx, extras: footerExtras) }
        return out
    }

    // MARK: Lid-closed mode (0.3.1 B1)

    /// The model's rows, then the `tab` style without Awake Settings… and the lid row where B1 puts it (directly after
    /// ✓ Keep Display On, or after the start-default row when idle), unless the model placed one itself.
    static func rows(_ facts: AwakeMenuFacts, lid: AwakeMenuRow?) -> [AwakeMenuRow] {
        var rows = AwakeMenuModel.rows(facts)
        if facts.style == .tab, let settings = rows.lastIndex(of: .settings) {
            rows.remove(at: settings)
            if settings > 0, rows[settings - 1] == .separator { rows.remove(at: settings - 1) }
        }
        let placed = rows.contains { row in
            switch row {
            case .lidClosed, .lidSubmenu: return true
            default: return false
            }
        }
        if !placed, let lid, let anchor = rows.lastIndex(of: .keepDisplayOn) ?? rows.lastIndex(of: .startDefault) {
            rows.insert(lid, at: anchor + 1)
        }
        return rows
    }

    /// Which lid row shows (B1, B3.0, B3.4): none unless the feature is effective (on, available, not killed, not in
    /// Safe Mode); a pending row while a request runs or an earlier journal is pending; ✓ while on; "…" in a session
    /// started from the menu or Settings; otherwise the idle submenu (hotkey, command-line, launch or restored
    /// sessions, rules and holds included: choosing a preset there replaces what runs once the mode is on).
    static func lidRow(_ ctx: AwakeContext) -> AwakeMenuRow? {
        let rt = ctx.runtime
        guard rt.isEffective(.lidClosed) else { return nil }
        if let state = ctx.lid.rowState { return .lidClosed(state) }
        if ctx.host.lidRecovery?.recovery == .pending { return .lidClosed(.finishingEarlier) }
        if case .manual(let s) = rt.governing, s.source == .menu || s.source == .settings { return .lidClosed(.off) }
        return .lidSubmenu(ctx.config.value.sessions.presets.map(\.id))
    }

    /// The B0 titles; pending rows are disabled.
    private func lidItem(_ state: LidRowState) -> NSMenuItem {
        let control = ControlID("menu.awake.lidClosed")
        switch state {
        case .off:
            return MenuKit.action(L("Keep Awake with the Lid Closed…"), control: control) { [weak self] in
                self?.context?.lid.request(.add, source: .menu)
            }
        case .on:
            // No ellipsis: turning it off asks nothing.
            return MenuKit.toggle(L("Keep Awake with the Lid Closed"), isOn: true, control: control) { [weak self] in
                self?.context?.lid.turnOff()
            }
        case .authorizing:
            return MenuKit.action(L("Waiting for Password…"), enabled: false, control: control) {}
        case .verifying:
            return MenuKit.action(L("Turning On…"), enabled: false, control: control) {}
        case .stopping:
            return MenuKit.action(L("Turning Off…"), enabled: false, control: control) {}
        case .finishingEarlier:
            return MenuKit.action(L("Finishing Earlier Session…"), enabled: false, control: control) {}
        }
    }

    /// "Keep Awake with the Lid Closed ›": every preset in order, each with "…" (each asks for the password), then
    /// Custom… with the panel's lid-closed switch turned on.
    private func lidSubmenu(_ ids: [StableID], _ ctx: AwakeContext) -> NSMenuItem {
        let presets = ctx.config.value.sessions.presets
        var rows: [NSMenuItem] = ids.compactMap { id in presets.first { $0.id == id } }.map { preset in
            let id = preset.id
            return MenuKit.action(preset.title(AwakeFormat.text) + "…", control: ControlID("menu.awake.lidPreset")) {
                [weak self] in
                self?.context?.lid.request(.preset(id), source: .menu)
            }
        }
        rows.append(MenuKit.separator())
        rows.append(MenuKit.action(L("Custom…"), control: ControlID("menu.awake.lidCustom")) { [weak self] in
            self?.custom.present(.start, lidClosed: true)
        })
        return MenuKit.submenu(L("Keep Awake with the Lid Closed"), control: ControlID("menu.awake.lidSubmenu"), rows)
    }

    /// Rules › exists while ≥ 1 rule exists and `triggers` is effective (lead r4, r3 product M2).
    private func rulesShown(_ ctx: AwakeContext) -> Bool {
        ctx.runtime.isEffective(.triggers) && !ctx.config.value.triggers.triggers.isEmpty
    }

    private func header(_ ctx: AwakeContext) -> NSMenuItem {
        let lines = detailLines(ctx)
        weak var built: NSMenuItem?
        let item = MenuKit.switchHeader(L("Keep Awake"), isOn: ctx.runtime.governing.isActive, detail: lines,
                                        control: ControlID("menu.awake.header")) { [weak self] on in
            guard let sessions = self?.context?.sessions else { return }
            if on { _ = sessions.startDefault(source: .menu) } else { sessions.turnOff(source: .menu) }
            // The switch is the whole task (like choosing an item): close the menu, so the rows below it are never
            // left showing the other state (ux m17); it is rebuilt when it next opens.
            var root = built?.menu
            while let parent = root?.supermenu { root = parent }
            root?.cancelTracking()
        }
        built = item
        headers.append((item, lines.count))
        return item
    }

    private func startDefault(_ ctx: AwakeContext) -> NSMenuItem {
        let preset = ctx.config.value.sessions.defaultPreset
        return MenuKit.action(preset.verbTitle(AwakeFormat.text), control: ControlID("menu.awake.startDefault")) { [weak self] in
            _ = self?.context?.sessions.startDefault(source: .menu)
        }
    }

    private func addTime(_ seconds: Int, _ ctx: AwakeContext) -> [NSMenuItem] {
        let extend: @MainActor () -> Void = { [weak self] in _ = self?.context?.sessions.extend(by: seconds, source: .menu) }
        if seconds < 3_600 {
            return [MenuKit.action(L("Add 15 Minutes"), control: ControlID("menu.awake.add15"), extend)]
        }
        let hour = MenuKit.action(L("Add 1 Hour"), control: ControlID("menu.awake.addHour"), extend)
        let more = MenuKit.alternate(of: hour, title: L("Add Time…"), control: ControlID("menu.awake.addTime")) { [weak self] in
            self?.custom.present(.extend)
        }
        return [hour, more]
    }

    /// Start Session ›: every preset in order (✓ only on the running one), then Custom….
    private func startSession(_ ctx: AwakeContext) -> NSMenuItem {
        let running: StableID?
        if case .manual(let s) = ctx.runtime.governing { running = s.presetID } else { running = nil }
        var rows: [NSMenuItem] = ctx.config.value.sessions.presets.map { preset in
            let id = preset.id
            return MenuKit.toggle(preset.title(AwakeFormat.text), isOn: id == running,
                                  control: ControlID("menu.awake.preset")) { [weak self] in
                _ = self?.context?.sessions.startPreset(id, source: .menu)
            }
        }
        rows.append(MenuKit.separator())
        rows.append(MenuKit.action(L("Custom…"), control: ControlID("menu.awake.custom")) { [weak self] in
            self?.custom.present(.start)
        })
        return MenuKit.submenu(L("Start Session"), control: ControlID("menu.awake.startSession"), rows)
    }

    /// While an App Is Running ›: running regular apps, recent first, ≤ 12, with their icons (their own group).
    private func whileApp(_ ctx: AwakeContext) -> NSMenuItem {
        var runningBundle: String?
        if case .manual(let s) = ctx.runtime.governing, case .whileApp(let b, _) = s.kind { runningBundle = b }
        let apps = AwakeFormat.runningApps(recent: ctx.config.value.sessions.recentApps)
        var rows: [NSMenuItem] = apps.map { app in
            let bundleID = app.bundleID
            let item = MenuKit.toggle(app.name, isOn: bundleID == runningBundle, control: ControlID("menu.awake.app")) { [weak self] in
                _ = self?.context?.sessions.start(.whileApp(bundleID: bundleID, maxSeconds: nil), options: nil,
                                                  presetID: nil, source: .menu, overrideGuards: false)
            }
            item.image = AwakeFormat.appIcon(bundleID)
            return item
        }
        if rows.isEmpty { rows = [MenuKit.status(L("No Apps Are Running"), control: ControlID("menu.awake.noApps"))] }
        return MenuKit.submenu(L("While an App Is Running"), control: ControlID("menu.awake.whileApp"), rows)
    }

    /// Rules ›: active rules + ≤ 4 others (read-only; a click opens the rule in Settings, ⌥ ends an active rule's
    /// session), then Pause Rules for 1 Hour · Pause Rules Until Tomorrow (or Resume Rules) · Edit Rules….
    private func rules(_ ctx: AwakeContext) -> NSMenuItem {
        let rt = ctx.runtime
        let triggers = ctx.config.value.triggers.triggers
        let byID = Dictionary(triggers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rows: [NSMenuItem] = []
        for entry in AwakeRulesMenu.visible(triggers, active: rt.activeTriggerIDs, waiting: rt.waitingTriggerIDs) {
            guard let rule = byID[entry.id] else { continue }
            let name = rule.displayName(AwakeFormat.text)
            let id = entry.id
            let item = MenuKit.action(name, control: ControlID("menu.awake.rule")) { [weak self] in
                guard let host = self?.context?.host else { return }
                AwakeRuleLink.open(rule: id, host: host)
            }
            let subtitle: String?
            switch entry.state {
            case .active: subtitle = L("Active")
            case .waiting: subtitle = L("Waiting")
            case .off: subtitle = L("Off")
            case .idle: subtitle = nil
            }
            rows.append(MenuKit.withSubtitle(item, subtitle))
            if entry.state == .active {
                rows.append(MenuKit.alternate(of: item, title: L("End ") + AwakeDetail.quoted(name) + L(" Session"),
                                              control: ControlID("menu.awake.ruleEnd")) { [weak self] in
                    self?.context?.triggers.manualEnd(id)
                })
            }
        }
        if !rows.isEmpty { rows.append(MenuKit.separator()) }
        if ctx.triggers.isPaused {
            rows.append(MenuKit.action(L("Resume Rules"), control: ControlID("menu.awake.resumeRules")) { [weak self] in
                self?.context?.triggers.resume()
            })
        } else {
            rows.append(MenuKit.action(L("Pause Rules for 1 Hour"), control: ControlID("menu.awake.pauseHour")) { [weak self] in
                self?.context?.triggers.pause(seconds: 3_600)
            })
            rows.append(MenuKit.action(L("Pause Rules Until Tomorrow"), control: ControlID("menu.awake.pauseTomorrow")) { [weak self] in
                self?.context?.triggers.pauseUntilTomorrow()
            })
        }
        rows.append(MenuKit.action(L("Edit Rules…"), control: ControlID("menu.awake.editRules")) { [weak self] in
            guard let host = self?.context?.host else { return }
            AwakeRuleLink.open(rule: nil, host: host)
        })
        let item = MenuKit.submenu(L("Rules"), control: ControlID("menu.awake.rules"), rows)
        return MenuKit.withSubtitle(item, rulesSubtitle(ctx))
    }

    private func rulesSubtitle(_ ctx: AwakeContext) -> String? {
        let rt = ctx.runtime
        let triggers = ctx.config.value.triggers.triggers
        func name(_ id: StableID?) -> String? {
            id.flatMap { id in triggers.first { $0.id == id }?.displayName(AwakeFormat.text) }
        }
        let paused = ctx.triggers.isPaused ? rt.pausedUntil.map { AwakeFormat.clock($0.timeIntervalSince1970) } : nil
        return AwakeRulesMenu.subtitle(pausedUntilClock: paused, activeName: name(rt.activeTriggerIDs.first),
                                       waitingName: name(rt.waitingTriggerIDs.first))
    }

    /// Own menu without the Snaptic item (§5.2): Recent Notices › (when there are some) and Quit Snaptic, after
    /// `extras` (0.3.1 E1: the Update Available row the shared footer carries).
    private func footerItems(_ ctx: AwakeContext, extras: [NSMenuItem]) -> [NSMenuItem] {
        var out: [NSMenuItem] = extras
        let recent = ctx.host.toasts.recent
        if !recent.isEmpty {
            var rows = recent.reversed().map { MenuKit.status($0, control: ControlID("menu.awake.notice")) }
            rows.append(MenuKit.separator())
            rows.append(MenuKit.action(L("Clear Menu"), control: ControlID("menu.awake.clearNotices")) { [weak self] in
                self?.context?.host.toasts.clearRecent()
            })
            out.append(MenuKit.submenu(L("Recent Notices"), control: ControlID("menu.awake.recentNotices"), rows))
        }
        out.append(MenuKit.quit(control: ControlID("menu.awake.quit")))
        return out
    }

    // MARK: Detail and live updates

    /// The header's detail (≤ 2 lines): what governs and the most relevant extra; at rest only a last end or a guard.
    func detailLines(_ ctx: AwakeContext) -> [String] {
        AwakeDetail.lines(Self.detailInput(ctx))
    }

    /// What the switch header and the Settings status row describe (one source for both).
    static func detailInput(_ ctx: AwakeContext) -> AwakeDetailInput {
        let rt = ctx.runtime
        let now = AwakeModule.clockNow()
        let triggers = ctx.config.value.triggers.triggers
        var input = AwakeDetailInput(governing: rt.governing, now: now)
        switch rt.governing {
        case .manual(let s):
            input.endClock = AwakeClock.endWall(s, now: now).map { AwakeFormat.clock($0) }
            if case .whileApp(let bundleID, _) = s.kind { input.appName = AwakeFormat.appName(bundleID) }
            if let next = ctx.triggers.top { input.nextRuleName = triggers.first { $0.id == next.id }?.displayName(AwakeFormat.text) }
            input.quietFor = ctx.sessions.quietFor
        case .trigger(let top):
            input.ruleName = triggers.first { $0.id == top.id }?.displayName(AwakeFormat.text)
        case .holds, .inactive:
            break
        }
        input.holderSummary = rt.holderSummary
        input.activity = rt.activity
        input.activityCapped = rt.activityCapped
        input.stopAfterHours = ctx.config.value.activity.stopAfterHours
        input.lidWarning = rt.governing.isActive && lidWarning(ctx)
        let use = backgroundUse(ctx)
        input.backgroundPaused = rt.power.flatMap { AwakeGuards.backgroundBlock($0, config: ctx.config.value.guards) }
            .flatMap { AwakeBackgroundText.paused($0, activity: use.activity, drives: use.drives) }
        if !rt.governing.isActive {
            let floor = ctx.sessions.floorForText()
            if let hold = rt.guardHold, let text = AwakeEndText.holding(hold, floor: floor) {
                input.idleNote = text
            } else if let end = rt.lastEnd, Date().timeIntervalSince(end.at) < 12 * 3_600 {
                input.idleNote = AwakeEndText.lastEnd(end.reason, clock: AwakeFormat.clock(end.at.timeIntervalSince1970),
                                                      floor: floor,
                                                      lockedHours: ctx.config.value.sessions.behavior.endAfterLockedHours)
            }
        }
        return input
    }

    /// What the guards' background stop affects right now: activity for the governing session, Drive Alive with a
    /// turned-on drive (F2).
    static func backgroundUse(_ ctx: AwakeContext) -> (activity: Bool, drives: Bool) {
        let rt = ctx.runtime
        let activity = rt.isEffective(.activity) && (rt.governing.options.map { $0.activity != .off } ?? false)
        let drives = rt.isEffective(.driveAlive) && !rt.drives.isEmpty
        return (activity, drives)
    }

    /// "Closing the lid will put your Mac to sleep." on battery or without an external display (§2.12, design m5),
    /// only while closing it would sleep the Mac and lid-closed mode is off (0.3.1 B1).
    private static func lidWarning(_ ctx: AwakeContext) -> Bool {
        guard ctx.runtime.lidWillSleep == true, !ctx.runtime.lidMode.isOn else { return false }
        let onBattery = ctx.runtime.power.map { $0.batteryPresent && !$0.onAC } ?? false
        let external = NSScreen.screens.contains { screen in
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(CGDirectDisplayID(n.uint32Value)) == 0
        }
        return onBattery || !external
    }

    private func observe(_ runtime: AwakeRuntimeState) {
        let changes: [AnyPublisher<Void, Never>] = [
            runtime.$governing.map { _ in () }.eraseToAnyPublisher(),
            runtime.$remaining.map { _ in () }.eraseToAnyPublisher(),
            runtime.$holderSummary.map { _ in () }.eraseToAnyPublisher(),
            runtime.$activity.map { _ in () }.eraseToAnyPublisher(),
            runtime.$activityCapped.map { _ in () }.eraseToAnyPublisher(),
            runtime.$lastEnd.map { _ in () }.eraseToAnyPublisher(),
            runtime.$guardHold.map { _ in () }.eraseToAnyPublisher(),
            runtime.$power.map { _ in () }.eraseToAnyPublisher(),
            runtime.$drives.map { _ in () }.eraseToAnyPublisher(),
            // 0.3.1 B1: the lid warning and the lid lines.
            runtime.$lidWillSleep.map { _ in () }.eraseToAnyPublisher(),
            runtime.$lidMode.map { _ in () }.eraseToAnyPublisher(),
            runtime.$lastLidEnd.map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                .receive(on: DispatchQueue.main)
                .map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.refreshHeaders() } }
            .store(in: &sinks)
    }

    /// Updates every open header in place. A changed line count keeps the opened height (MenuKit) and the menu is
    /// rebuilt when it next opens.
    private func refreshHeaders() {
        headers.removeAll { $0.item.menu == nil }
        guard let ctx = context, !headers.isEmpty else { return }
        let lines = detailLines(ctx)
        let on = ctx.runtime.governing.isActive
        for h in headers { MenuKit.update(h.item, isOn: on, detail: lines) }
    }
}
