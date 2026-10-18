import SwiftUI
import SnapticKit

/// Display Features (PLAN §2.1): every DisplayFeature grouped by its settings page, with
/// its switch, Beta/Experimental labels, why it is unavailable or inactive, what it
/// needs, and what else turns off with it. Turning on goes through `env.enableFeature`
/// (the feature plus everything it requires); turning off clears only that flag.
struct FeaturesPage: View {
    @ObservedObject private var env: DisplaysPageEnvironment
    @State private var pendingOff: PendingOff?
    @State private var notice: String?

    struct PendingOff: Identifiable {
        let feature: DisplayFeature
        let dependents: [DisplayFeature]
        var id: DisplayFeature { feature }
    }

    init(env: DisplaysPageEnvironment) {
        _env = ObservedObject(wrappedValue: env)
    }

    var body: some View {
        Form {
            DisplaysStatusSection(env: env)
            Section {
                Text(L("A feature that is off costs nothing: no timers, helpers, private APIs or permission prompts."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if env.context == nil {
                    Text(L("Displays is off. Features you choose here start when you turn Displays on."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let notice {
                    Label(notice, systemImage: "info.circle")
                        .font(.callout)
                }
            }
            ForEach(DisplaysUIText.pageOrder, id: \.self) { page in
                let features = DisplayFeature.allCases.filter { FeatureGraph.spec($0).page == page }
                if !features.isEmpty {
                    Section(DisplaysUIText.pageTitle(page)) {
                        ForEach(features, id: \.self) { feature in
                            FeatureRow(feature: feature, env: env, turnOn: { turnOn(feature) }, turnOff: { requestOff(feature) })
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert(item: $pendingOff) { pending in
            Alert(title: Text(L("Turn off \(DisplaysUIText.title(pending.feature))?")),
                  message: Text(L("Also turns off: \(pending.dependents.map(DisplaysUIText.title).joined(separator: ", ")).")),
                  primaryButton: .destructive(Text(L("Turn Off"))) { turnOff(pending.feature) },
                  secondaryButton: .cancel())
        }
    }

    private func turnOn(_ feature: DisplayFeature) {
        let raw = env.config.value.rawFeatures
        let available = Set(DisplayFeature.allCases.filter { env.runtime.availability[$0]?.isAvailable ?? true })
        let after = FeatureGraph.enabling(feature, raw: raw, available: available)
        let added = DisplayFeature.allCases.filter {
            $0 != feature && after[$0] == true && !FeatureGraph.rawState($0, in: raw)
        }
        env.enableFeature(feature)
        notice = added.isEmpty ? nil
            : L("Turning on \(DisplaysUIText.title(feature)) also turned on: \(added.map(DisplaysUIText.title).joined(separator: ", ")).")
        let needs = FeatureGraph.permissions(feature)
        if let ctx = env.context {
            for permission in needs where ctx.permissions.state(permission) != .granted {
                ctx.permissions.request(permission, reason: DisplaysUIText.title(feature), lifetime: ctx.lifetime)
            }
        }
    }

    private func requestOff(_ feature: DisplayFeature) {
        let dependents = FeatureGraph.dependents(of: feature, effective: env.runtime.effectiveFeatures)
        if dependents.isEmpty {
            turnOff(feature)
        } else {
            pendingOff = PendingOff(feature: feature, dependents: DisplayFeature.allCases.filter { dependents.contains($0) })
        }
    }

    private func turnOff(_ feature: DisplayFeature) {
        guard FeatureGraph.spec(feature).defaultState != .always else { return }
        env.config.value.features[feature] = false
        notice = nil
    }
}

private struct FeatureRow: View {
    let feature: DisplayFeature
    @ObservedObject var env: DisplaysPageEnvironment
    let turnOn: () -> Void
    let turnOff: () -> Void

    private var spec: FeatureSpec { FeatureGraph.spec(feature) }
    private var isAlways: Bool { spec.defaultState == .always }
    private var isOn: Bool { FeatureGraph.rawState(feature, in: env.config.value.rawFeatures) }
    private var isEffective: Bool { env.runtime.isEffective(feature) }
    private var unavailableReason: String? {
        if case .unavailable(let reason)? = env.runtime.availability[feature] { return reason }
        return nil
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(DisplaysUIText.title(feature))
                    if spec.beta { DisplaysBadge(text: L("Beta"), tint: .orange) }
                    if spec.defaultState == .experimental { DisplaysBadge(text: L("Experimental"), tint: .purple) }
                    if isAlways { DisplaysBadge(text: L("Always on")) }
                }
                Text(DisplaysUIText.summary(feature))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(statusLines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                permissionRows
            }
            Spacer(minLength: 8)
            if !isAlways {
                Toggle(isOn: Binding(get: { isOn }, set: { $0 ? turnOn() : turnOff() })) {
                    Text(DisplaysUIText.title(feature))
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!isOn && unavailableReason != nil)
                .accessibilityLabel(DisplaysUIText.title(feature))
                .accessibilityHint(DisplaysUIText.summary(feature))
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Why the feature is unavailable, or on but not effective (PLAN §2.1 "Needs X").
    private var statusLines: [String] {
        if let reason = unavailableReason { return [L("Unavailable: \(reason)")] }
        guard isOn, !isEffective, let ctx = env.context else { return [] }
        if let reason = ctx.otherApps.pauseReason(for: feature) { return [reason] }
        if ctx.safeMode.isActive && FeatureGraph.safeModeRemoves.contains(feature) { return [L("Paused in Safe Mode")] }
        if ctx.panic.isLatched && FeatureGraph.panicLatchRemoves.contains(feature) {
            return [L("Paused until you resume display automation")]
        }
        var lines: [String] = []
        let missingAll = spec.requiresAll.filter { !env.runtime.isEffective($0) }
        if !missingAll.isEmpty { lines.append(L("Needs \(missingAll.map(DisplaysUIText.title).joined(separator: ", "))")) }
        if !spec.requiresAny.isEmpty, !spec.requiresAny.contains(where: { env.runtime.isEffective($0) }) {
            if feature == .brightness {
                lines.append(L("Choose a brightness method"))
            } else {
                lines.append(L("Needs one of: \(spec.requiresAny.map(DisplaysUIText.title).joined(separator: ", "))"))
            }
        }
        if lines.isEmpty, ctx.runtime.moduleState == .running { lines.append(L("Not active")) }
        return lines
    }

    @ViewBuilder
    private var permissionRows: some View {
        let needs = Permission.allCases.filter { spec.permissions.contains($0) }
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        ForEach(needs, id: \.self) { permission in
            HStack(spacing: 6) {
                let state = env.context?.permissions.state(permission) ?? .unknown
                Image(systemName: state == .granted ? "checkmark.shield" : "lock.shield")
                    .accessibilityHidden(true)
                Text(state == .granted
                     ? L("Uses \(DisplaysUIText.permissionName(permission, osMajor: osMajor))")
                     : L("Needs \(DisplaysUIText.permissionName(permission, osMajor: osMajor))"))
                if state != .granted, isOn, let ctx = env.context {
                    Button(L("Grant…")) {
                        ctx.permissions.request(permission, reason: DisplaysUIText.title(feature), lifetime: ctx.lifetime)
                    }
                    .controlSize(.small)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
