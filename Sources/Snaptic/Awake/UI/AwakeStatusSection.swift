import AppKit
import SwiftUI
import SnapticKit

/// The Awake page's status row (owner: G; PLAN 0.3 §4.3 "Status", R5-9, R5-10, R5-11): what keeps the Mac awake now,
/// and buttons that reach every session kind when the status items are hidden (26/27). Idle: [Pause Rules ▾]
/// [Keep Awake ▾] (a click starts the default session; ▾ lists the presets, While an App Is Running ▸ and Custom…).
/// Active: [Pause Rules ▾] [Options ▾] [Turn Off]; holds only: [Keep Awake ▾] [Turn Off] (a start joins the holds). Buttons only, no switch (N5), none a
/// default button (r3 security L8). Every start is a `.settings` UI start and first asks `SettingsShell.mayStart()`
/// (R5-8): right after an external open of the window it does nothing. 0.3.1 B1: both pull-downs gain the lid-closed
/// items of the Awake menu, with its titles (the idle one lists the presets); a lid request is a `.settings` UI start
/// and LidClosedController checks the focus guard.
struct AwakeStatusSection: View, ControlDeclaring {
    typealias Controls = AwakePageControls

    let env: AwakePageEnvironment
    let context: AwakeContext
    @ObservedObject private var runtime: AwakeRuntimeState
    @StateObject private var sessions: ConfigSlice<AwakeConfig, AwakeSessionsConfig>
    @StateObject private var triggers: ConfigSlice<AwakeConfig, AwakeTriggersConfig>
    @StateObject private var indicator: ConfigSlice<AwakeConfig, AwakeIndicatorConfig>

    init(env: AwakePageEnvironment, context: AwakeContext) {
        self.env = env
        self.context = context
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _sessions = StateObject(wrappedValue: ConfigSlice(env.config, \.sessions))
        _triggers = StateObject(wrappedValue: ConfigSlice(env.config, \.triggers))
        _indicator = StateObject(wrappedValue: ConfigSlice(env.config, \.indicator))
    }

    var body: some View {
        let input = AwakeMenuRows.detailInput(context)
        let paused = pausedUntilClock
        let facts = AwakeStatusRowFacts(governing: runtime.governing, holdsExist: !runtime.holds.isEmpty,
                                     rulesExist: runtime.isEffective(.triggers) && !triggers.value.triggers.isEmpty,
                                     rulesPaused: paused != nil)
        let primary = AwakeStatusText.primary(input)
        let details = AwakeStatusText.details(input, pausedUntilClock: paused)
        Section {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    statusText(primary: primary, details: details)
                    Spacer(minLength: 8)
                    buttons(facts)
                }
                VStack(alignment: .leading, spacing: 8) {
                    statusText(primary: primary, details: details)
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        buttons(facts)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Text

    private func statusText(primary: String, details: [String]) -> some View {
        let active = runtime.governing.isActive
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: active ? indicator.value.glyph.active : indicator.value.glyph.idle)
                .foregroundStyle(active ? Color.orange : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "4:00 PM" while rules are paused.
    private var pausedUntilClock: String? {
        guard let until = runtime.pausedUntil, until > Date() else { return nil }
        return AwakeFormat.clock(until.timeIntervalSince1970)
    }

    // MARK: Buttons

    @ViewBuilder private func buttons(_ facts: AwakeStatusRowFacts) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(AwakeStatusPlan.buttons(facts).enumerated()), id: \.offset) { _, button in
                self.button(button, facts: facts)
            }
        }
        .fixedSize()
    }

    @ViewBuilder private func button(_ kind: AwakeStatusButton, facts: AwakeStatusRowFacts) -> some View {
        switch kind {
        case .pauseRules:
            ActionMenuButton(L("Pause Rules"), items: [
                ActionMenuItem(id: "hour", title: L("For 1 Hour")) { [weak triggers = context.triggers] in
                    triggers?.pause(seconds: 3_600)
                },
                ActionMenuItem(id: "tomorrow", title: L("Until Tomorrow")) { [weak triggers = context.triggers] in
                    triggers?.pauseUntilTomorrow()
                },
            ], primaryAction: nil, control: ControlID("awake.page.status.pauseRules"))
            .help(L("Rules don’t start sessions until you resume them or the time is up."))
        case .resumeRules:
            Button(L("Resume")) { [weak triggers = context.triggers] in triggers?.resume() }
                .help(L("Lets rules start sessions again."))
                .modifier(SettingsAnchor(ControlID("awake.page.status.resume")))
        case .keepAwake:
            ActionMenuButton(L("Keep Awake"), items: startItems(replacing: false), primaryAction: startDefault,
                             control: ControlID("awake.page.status.keepAwake"))
                .help(L("Click to start your default session, or choose another."))
        case .options:
            ActionMenuButton(L("Options"), items: optionItems(facts), primaryAction: nil,
                             control: ControlID("awake.page.status.options"))
        case .turnOff:
            Button(L("Turn Off")) { [weak sessions = context.sessions] in sessions?.turnOff(source: .settings) }
                .modifier(SettingsAnchor(ControlID("awake.page.status.turnOff")))
        }
    }

    // MARK: Actions

    private var startDefault: @MainActor () -> Void {
        { [weak sessions = context.sessions] in
            guard SettingsShell.shared.mayStart() else { return }
            _ = sessions?.startDefault(source: .settings)
        }
    }

    /// The Keep Awake list (R5-9): presets in order (their non-verb titles), ─, While an App Is Running ▸, Custom….
    /// The same list is Options ▾ › Replace With ▸, where the running preset is not offered again.
    private func startItems(replacing: Bool) -> [ActionMenuItem] {
        let running: StableID?
        if replacing, case .manual(let s) = runtime.governing { running = s.presetID } else { running = nil }
        var items: [ActionMenuItem] = sessions.value.presets.filter { $0.id != running }.map { (preset: AwakePreset) -> ActionMenuItem in
            let id = preset.id
            return ActionMenuItem(id: "preset." + id.rawValue, title: preset.title(AwakeFormat.text),
                                  control: ControlID("awake.page.status.keepAwakeMenu")) { [weak sessions = context.sessions] in
                guard SettingsShell.shared.mayStart() else { return }
                _ = sessions?.startPreset(id, source: .settings)
            }
        }
        items.append(.separator("apps.separator"))
        let apps = AwakeFormat.runningApps(recent: sessions.value.recentApps)
        var appItems: [ActionMenuItem] = apps.map { (app: (bundleID: String, name: String)) -> ActionMenuItem in
            let bundleID = app.bundleID
            return ActionMenuItem(id: "app." + bundleID, title: app.name) { [weak sessions = context.sessions] in
                guard SettingsShell.shared.mayStart() else { return }
                _ = sessions?.start(.whileApp(bundleID: bundleID, maxSeconds: nil), options: nil, presetID: nil,
                                    source: .settings, overrideGuards: false)
            }
        }
        if appItems.isEmpty {
            appItems = [ActionMenuItem(id: "app.none", title: L("No Apps Are Running"), enabled: false) {}]
        }
        if !replacing {
            let lid = lidItems()
            if !lid.isEmpty { items += [.separator("lid.separator")] + lid }
        }
        items.append(ActionMenuItem(id: "apps", title: L("While an App Is Running"), children: appItems))
        items.append(ActionMenuItem(id: "custom", title: L("Custom…")) { [weak env = self.env] in
            guard SettingsShell.shared.mayStart() else { return }
            env?.presentCustom(.start)
        })
        return items
    }

    /// Options ▾ (AwakeStatusPlan): Add 15 Minutes, Add 1 Hour, Add Time…, ✓ Keep Display On (as in the menus),
    /// End Command-Line Holds, Replace With ▸.
    private func optionItems(_ facts: AwakeStatusRowFacts) -> [ActionMenuItem] {
        var items: [ActionMenuItem] = []
        for (index, item) in AwakeStatusPlan.options(facts).enumerated() {
            switch item {
            case .addTime(let seconds):
                let title = seconds < 3_600 ? L("Add 15 Minutes") : L("Add 1 Hour")
                items.append(ActionMenuItem(id: "add.\(seconds)", title: title) { [weak sessions = context.sessions] in
                    // Same focus guard as the Custom panel's Add Time (security S2-3).
                    guard SettingsShell.shared.mayStart() else { return }
                    _ = sessions?.extend(by: seconds, source: .settings)
                })
            case .addTimeCustom:
                items.append(ActionMenuItem(id: "addTime", title: L("Add Time…")) { [weak env = self.env] in
                    guard SettingsShell.shared.mayStart() else { return }
                    env?.presentCustom(.extend)
                })
            case .separator:
                items.append(.separator("separator.\(index)"))
            case .keepDisplayOn:
                items.append(ActionMenuItem(id: "display", title: L("Keep Display On"),
                                            checked: context.sessions.keepsDisplayOn) {
                    [weak sessions = context.sessions] in
                    guard let sessions else { return }
                    sessions.setKeepDisplayOn(!sessions.keepsDisplayOn)
                })
                // B1: directly after Keep Display On, as in the menu.
                items += lidItems()
            case .endHolds:
                items.append(ActionMenuItem(id: "endHolds", title: L("End Command-Line Holds")) {
                    [weak sessions = context.sessions] in
                    sessions?.endAllHolds(.user)
                })
            case .replaceWith:
                items.append(ActionMenuItem(id: "replace", title: L("Replace With"), children: startItems(replacing: true),
                                            control: ControlID("awake.page.status.replaceWith")))
            }
        }
        return items
    }

    /// The lid-closed items for the current state (AwakeMenuRows decides which, for the menus too).
    private func lidItems() -> [ActionMenuItem] {
        guard let row = AwakeMenuRows.lidRow(context) else { return [] }
        let control = ControlID("awake.page.status.lidClosed")
        let lid = context.lid
        switch row {
        case .lidSubmenu(let ids):
            let presets = sessions.value.presets
            let children = ids.compactMap { id in presets.first { $0.id == id } }.map { (preset: AwakePreset) -> ActionMenuItem in
                let id = preset.id
                return ActionMenuItem(id: "lid." + id.rawValue, title: preset.title(AwakeFormat.text) + "…",
                                      control: ControlID("awake.page.status.lidPreset")) { [weak lid] in
                    lid?.request(.preset(id), source: .settings)
                }
            }
            return [ActionMenuItem(id: "lid", title: L("Keep Awake with the Lid Closed"), children: children,
                                   control: control)]
        case .lidClosed(.off):
            return [ActionMenuItem(id: "lid", title: L("Keep Awake with the Lid Closed…"), control: control) { [weak lid] in
                lid?.request(.add, source: .settings)
            }]
        case .lidClosed(.on):
            return [ActionMenuItem(id: "lid", title: L("Keep Awake with the Lid Closed"), checked: true,
                                   control: control) { [weak lid] in
                lid?.turnOff()
            }]
        case .lidClosed(let state):
            return [ActionMenuItem(id: "lid", title: Self.pendingTitle(state), enabled: false, control: control) {}]
        default:
            return []
        }
    }

    /// B0's pending rows.
    private static func pendingTitle(_ state: LidRowState) -> String {
        switch state {
        case .authorizing: return L("Waiting for Password…")
        case .verifying: return L("Turning On…")
        case .stopping: return L("Turning Off…")
        case .finishingEarlier: return L("Finishing Earlier Session…")
        case .off, .on: return L("Keep Awake with the Lid Closed")
        }
    }
}
