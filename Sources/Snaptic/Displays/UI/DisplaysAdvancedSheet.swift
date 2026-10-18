import SwiftUI
import SnapticKit

/// Displays › Advanced (owner F; PLAN 0.3 §4.3): the cross-cutting groups. "Use Snaptic for" and "Experimental"
/// (`DisplaysFeatureGroups`), the permissions those features need, and the settings whose 0.3 sections land in step 3
/// (confirm display changes, resolution options, display names), reached by closing the sheet and opening their page
/// (a sheet never presents another one). Footer: Restore Displays Defaults… · Done.
struct DisplaysAdvancedSheet: View, ControlDeclaring {
    typealias Controls = DisplaysAdvancedSheetControls

    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @Environment(\.dismiss) private var dismiss

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
    }

    var body: some View {
        AdvancedSheet(L("Displays Advanced Settings"), restoreDefaults: restore) {
            DisplaysFeatureGroups(switcher: switcher, runtime: runtime, features: features)
            permissions
            Section {
                link(L("Confirm Display Changes"), help: L("Ask before keeping a new resolution, and how to undo it."),
                     page: "displays.safety")
                link(L("Resolution Options"), help: L("Favorites, filters, and the resolution slider."),
                     page: "displays.resolution")
                link(L("Remembered Displays"), help: L("Displays Snaptic keeps settings for, and their names."),
                     page: "displays.identity")
            } header: {
                Text(L("More settings"))
            }
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
    }

    /// Features that are on but wait for a permission: one status row per permission, with its fix.
    @ViewBuilder private var permissions: some View {
        let missing = missingPermissions
        if !missing.isEmpty, let ctx = env.context {
            let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            Section {
                ForEach(missing, id: \.self) { permission in
                    let name = DisplaysUIText.permissionName(permission, osMajor: osMajor)
                    StatusRow(L("Some features need \(name)."), style: .warning, actions: [
                        StatusAction(title: L("Open \(name) Settings…"),
                                     control: ControlID("displays.advanced.permissions")) {
                            ctx.permissions.presentGuide(permission, reason: L("Displays"))
                        },
                    ])
                }
            } header: {
                Text(L("Permissions"))
            }
        }
    }

    private var missingPermissions: [Permission] {
        guard let ctx = env.context else { return [] }
        let raw = features.value
        let needed = DisplayFeature.allCases.filter { FeatureGraph.rawState($0, in: raw) }
            .reduce(into: Set<Permission>()) { $0.formUnion(FeatureGraph.permissions($1)) }
        return Permission.allCases.filter { needed.contains($0) && ctx.permissions.state($0) != .granted }
    }

    /// Closes the sheet, then opens the page on the next turn (the shell pushes it).
    private func link(_ title: String, help: String, page: String) -> some View {
        LabeledContent {
            Button(L("Open…")) {
                dismiss()
                let env = env
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { env.context?.openSettings(page) }
                }
            }
            .disabled(env.context == nil)
        } label: {
            Text(title)
            Text(help)
        }
    }

    private var restore: RestoreDefaults {
        let config = env.config
        return RestoreDefaults(scopeName: L("Displays"), destructive: true) {
            config.value = config.value.restoringDefaults(scope: .all)
            EventLog.shared.record(.modules, "Displays settings restored to their defaults")
        }
    }
}
