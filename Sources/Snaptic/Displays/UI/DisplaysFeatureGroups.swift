import SwiftUI
import SnapticKit

// Displays › Advanced › Use Snaptic for and Experimental (owner F; PLAN 0.3 §4.3, §4.8 "Displays: feature
// switches"), and the feature-switch logic every Displays page with a feature switch shares: turning a feature on
// turns on what it needs and asks for missing permissions; turning it off also turns off what depends on it, after
// saying so.

// MARK: - Switch logic

@MainActor final class DisplaysFeatureSwitcher: ObservableObject {
    /// A turn-off that also stops other features, waiting for the person to confirm.
    struct PendingOff: Identifiable {
        let title: String
        let features: [DisplayFeature]
        let dependents: [DisplayFeature]
        var id: String { title }
    }

    @Published var pendingOff: PendingOff?
    /// "Turning on X also turned on: …", shown under the group that did it.
    @Published private(set) var notice: String?

    let env: DisplaysPageEnvironment

    init(env: DisplaysPageEnvironment) { self.env = env }

    func binding(_ item: DisplayFeatureSwitch) -> Binding<Bool> {
        binding(item.features, title: item.title)
    }

    /// A switch over `features` (the first one is its state).
    func binding(_ features: [DisplayFeature], title: String) -> Binding<Bool> {
        Binding(get: { [weak self] in
            guard let self, let first = features.first else { return false }
            return FeatureGraph.rawState(first, in: self.env.config.value.rawFeatures)
        }, set: { [weak self] on in
            guard let self else { return }
            if on { self.turnOn(features, title: title) } else { self.requestOff(features, title: title) }
        })
    }

    /// Why the switch can't be turned on here, or nil.
    func unavailableReason(_ features: [DisplayFeature]) -> String? {
        for f in features {
            if case .unavailable(let reason)? = env.runtime.availability[f] { return reason }
        }
        return nil
    }

    /// The first of `features` that a `Displays.disable.<feature>` defaults key turns off (the module reports it as
    /// unavailable with `DefaultsLock.text`), for its DefaultsLockRow and the command that turns it back on.
    func lockedFeature(_ features: [DisplayFeature]) -> DisplayFeature? {
        features.first { feature in
            if case .unavailable(let reason)? = env.runtime.availability[feature] { return reason == DefaultsLock.text }
            return false
        }
    }

    private func turnOn(_ features: [DisplayFeature], title: String) {
        let before = env.config.value.rawFeatures
        let available = Set(DisplayFeature.allCases.filter { env.runtime.availability[$0]?.isAvailable ?? true })
        var after = before
        for f in features {
            for (g, on) in FeatureGraph.enabling(f, raw: after, available: available) { after[g] = on }
        }
        let added = DisplayFeature.allCases.filter {
            !features.contains($0) && after[$0] == true && !FeatureGraph.rawState($0, in: before)
        }
        for f in features { env.enableFeature(f) }
        notice = added.isEmpty ? nil
            : L("Also turned on: \(added.map(DisplaysUIText.title).joined(separator: ", ")).")
        // The person asked for it: show the permission guide now, not the once-per-launch request.
        guard let ctx = env.context else { return }
        let needs = features.reduce(into: Set<Permission>()) { $0.formUnion(FeatureGraph.permissions($1)) }
        for permission in Permission.allCases where needs.contains(permission)
            && ctx.permissions.state(permission) != .granted {
            ctx.permissions.presentGuide(permission, reason: title)
        }
    }

    private func requestOff(_ features: [DisplayFeature], title: String) {
        let raw = env.config.value.rawFeatures
        var dependents: [DisplayFeature] = []
        for f in features {
            for d in FeatureTurnOff.dependents(of: f, raw: raw, effective: env.runtime.effectiveFeatures)
            where !features.contains(d) && !dependents.contains(d) {
                dependents.append(d)
            }
        }
        if dependents.isEmpty {
            turnOff(features, dependents: [])
        } else {
            pendingOff = PendingOff(title: title, features: features, dependents: dependents)
        }
    }

    func confirmOff() {
        guard let pending = pendingOff else { return }
        pendingOff = nil
        turnOff(pending.features, dependents: pending.dependents)
    }

    /// One config write: the features and the dependents the alert named.
    private func turnOff(_ features: [DisplayFeature], dependents: [DisplayFeature]) {
        var value = env.config.value
        for f in features {
            for (g, on) in FeatureTurnOff.changes(f, dependents: dependents) { value.features[g] = on }
        }
        env.config.value = value
        notice = nil
    }
}

/// The confirmation for a turn-off that stops other features too.
struct DisplaysFeatureOffAlert: ViewModifier {
    @ObservedObject var switcher: DisplaysFeatureSwitcher

    func body(content: Content) -> some View {
        content.alert(L("Turn off \(switcher.pendingOff?.title ?? "")?"),
                      isPresented: Binding(get: { switcher.pendingOff != nil },
                                           set: { if !$0 { switcher.pendingOff = nil } })) {
            Button(L("Turn Off"), role: .destructive) { switcher.confirmOff() }
            Button(L("Cancel"), role: .cancel) { switcher.pendingOff = nil }
        } message: {
            let names = (switcher.pendingOff?.dependents ?? []).map(DisplaysUIText.title).joined(separator: ", ")
            Text(L("This also turns off \(names)."))
        }
    }
}

// MARK: - Groups

/// "Use Snaptic for" and "Experimental" as two form sections (the Advanced sheet and the Display Features page).
struct DisplaysFeatureGroups: View, ControlDeclaring {
    typealias Controls = DisplaysAdvancedSheetControls

    @ObservedObject var switcher: DisplaysFeatureSwitcher
    /// Re-renders when a feature's availability or effective state changes.
    @ObservedObject var runtime: DisplaysRuntimeState
    /// Re-renders when a switch is written (only the features, not every config change).
    @ObservedObject var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>

    var body: some View {
        Section {
            row(DisplaysFeatureGroupsModel.useSnapticFor[0], ControlID("displays.advanced.useFor.brightness"))
            row(DisplaysFeatureGroupsModel.useSnapticFor[1], ControlID("displays.advanced.useFor.resolution"))
            row(DisplaysFeatureGroupsModel.useSnapticFor[2], ControlID("displays.advanced.useFor.arrangement"))
            row(DisplaysFeatureGroupsModel.useSnapticFor[3], ControlID("displays.advanced.useFor.rotation"))
            row(DisplaysFeatureGroupsModel.useSnapticFor[4], ControlID("displays.advanced.useFor.shortcuts"))
            row(DisplaysFeatureGroupsModel.useSnapticFor[5], ControlID("displays.advanced.useFor.indicator"))
            row(DisplaysFeatureGroupsModel.useSnapticFor[6], ControlID("displays.advanced.useFor.disconnect"))
        } header: {
            Text(L("Use Snaptic for"))
        } footer: {
            if let notice = switcher.notice {
                Text(notice)
            } else {
                Text(L("Color, hardware controls, saved layouts, virtual displays, and Picture in Picture have their switch on their own page."))
            }
        }
        Section {
            row(DisplaysFeatureGroupsModel.experimental[0], ControlID("displays.advanced.experimental.hdr"))
            row(DisplaysFeatureGroupsModel.experimental[1], ControlID("displays.advanced.experimental.underscan"))
            row(DisplaysFeatureGroupsModel.experimental[2], ControlID("displays.advanced.experimental.autoBrightness"))
            row(DisplaysFeatureGroupsModel.experimental[3], ControlID("displays.advanced.experimental.broadcast"))
            if runtime.isEffective(.osdBroadcast) {
                LabeledContent(L("Notification name")) {
                    Text(OSDPresenter.broadcastName.rawValue)
                        .monospaced()
                        .textSelection(.enabled)
                }
                .padding(.leading, 20)
            }
            row(DisplaysFeatureGroupsModel.experimental[4], ControlID("displays.advanced.experimental.allResolutions"))
        } header: {
            Text(L("Experimental"))
        } footer: {
            Text(L("Experimental features may not work on every display."))
        }
    }

    @ViewBuilder private func row(_ item: DisplayFeatureSwitch, _ anchor: ControlID) -> some View {
        let reason = switcher.unavailableReason(item.features)
        let isOn = item.isOn(raw: features.value)
        // A kill switch says so once, in its DefaultsLockRow with how to turn it back on (ux round 2 Nit 1, review
        // round 3 ui N1); any other reason is the switch's note.
        let killed = reason == DefaultsLock.text
        ToggleSetting(item.title, help: help(item), isOn: switcher.binding(item), anchor: anchor,
                      badge: badge(item), disabledReason: isOn || killed ? nil : reason)
            .disabled(!isOn && killed)
        if let locked = switcher.lockedFeature(item.features) {
            DefaultsLockRow(key: KillSwitches.key(prefix: "Displays", id: locked.rawValue))
                .padding(.leading, 20)
        }
    }

    private func help(_ item: DisplayFeatureSwitch) -> String {
        if item.isMixed(raw: features.value) { return item.help + " " + L("Some parts are off.") }
        if item.shown == .disconnect, let note = PowerController.disconnectNote { return item.help + " " + note }
        return item.help
    }

    private func badge(_ item: DisplayFeatureSwitch) -> SettingsBadge? {
        if item.shown == .disconnect && PowerController.disconnectIsExperimental { return .experimental }
        switch item.badge {
        case .beta?: return .beta
        case .experimental?: return .experimental
        case nil: return nil
        }
    }
}
