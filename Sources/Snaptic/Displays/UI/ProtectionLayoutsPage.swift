import SwiftUI
import SnapticKit

/// Protection & Layouts (PLAN §9.6, §9.7): configuration protection per display set, and
/// saved layouts with trust and auto-apply.
struct ProtectionLayoutsPage: View {
    @ObservedObject var env: DisplaysPageEnvironment

    var body: some View {
        Form {
            DisplaysStatusSection(env: env)
            ProtectionSection(env: env)
            LayoutsSection(env: env)
        }
        .formStyle(.grouped)
    }
}

private struct ProtectionSection: View {
    @ObservedObject var env: DisplaysPageEnvironment

    private var controller: ProtectionController? { env.context?.connectPlanner.protection }

    var body: some View {
        Section {
            ManagementFeatureNotice(env: env, feature: .protection, title: L("Configuration protection"))
            if env.runtime.isEffective(.protection), let c = controller {
                Toggle(L("Protect the current arrangement"), isOn: Binding(get: { c.isProtectingCurrent }, set: { on in
                    if on { c.captureCurrent() } else { c.removeCurrent() }
                }))
                Button(L("Save Current State as Protected")) { c.captureCurrent() }
                    .disabled(!c.isProtectingCurrent)
                fieldToggle(L("Resolution and refresh rate"), \.mode, feature: .resolution)
                fieldToggle(L("Position"), \.origin, feature: .arrangement)
                fieldToggle(L("Main display"), \.main, feature: .mainDisplay)
                fieldToggle(L("Mirroring"), \.mirror, feature: .mirroring)
                fieldToggle(L("Rotation"), \.rotation, feature: .rotation)
                let count = env.config.value.management.protection.values.count
                HStack {
                    Text(L("Protected display sets: \(count)"))
                    Spacer()
                    Button(L("Forget All"), role: .destructive) { env.config.value.management.protection = LossyMap() }
                        .disabled(count == 0)
                }
            }
        } header: {
            Text(L("Protection"))
        } footer: {
            ManagementNote(L("When macOS or another app changes a protected arrangement, Snaptic puts it back. Changes you make in Snaptic become the new protected state. If macOS keeps changing it, protection pauses for that set."))
        }
    }

    private func fieldToggle(_ title: String, _ path: WritableKeyPath<ProtectedFields, Bool>, feature: DisplayFeature) -> some View {
        let binding = ManagementBindings.config(env, (\DisplaysConfig.management.protectionFields).appending(path: path))
        return VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: binding)
            if !env.runtime.isEffective(feature) { ManagementNote(L("Skipped: needs \(title.lowercased()) to be on")) }
        }
    }
}

private struct LayoutsSection: View {
    @ObservedObject var env: DisplaysPageEnvironment
    @State private var newName = ""
    @State private var renaming: StableID?
    @State private var renameText = ""

    private var controller: LayoutsController? { env.context?.connectPlanner.layouts }

    var body: some View {
        Section {
            ManagementFeatureNotice(env: env, feature: .layouts, title: L("Layouts"))
            if env.runtime.isEffective(.layouts), let c = controller {
                HStack {
                    TextField(L("New layout name"), text: $newName)
                    Button(L("Save Current Layout")) {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        _ = c.captureCurrent(name: name.isEmpty ? nil : name)
                        newName = ""
                    }
                }
                Toggle(L("Offer Undo after an automatic apply"), isOn: ManagementBindings.config(env, \.layouts.undoToast))
                ForEach(Array(c.layouts.enumerated()), id: \.element.id) { index, l in
                    LayoutRow(env: env, controller: c, layout: l, index: index)
                }
            }
        } header: {
            Text(L("Layouts"))
        } footer: {
            ManagementNote(L("A layout applies automatically only after you applied it once and chose Keep for automatic use. Trust checks the layout hasn't changed and the displays are the same ones (by serial number); it isn't a password."))
        }
    }
}

private struct LayoutRow: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let controller: LayoutsController
    let layout: SavedLayout
    let index: Int
    @State private var name: String = ""

    var body: some View {
        let matches = controller.matches(layout)
        let trusted = controller.isTrusted(layout)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(L("Name"), text: Binding(get: { name.isEmpty ? layout.name : name }, set: { name = $0 }))
                    .onSubmit { commitName() }
                    .accessibilityLabel(L("Name of layout \(index + 1)"))
                if index < 9 { Text(L("Action \(index + 1)")).font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing: 8) {
                Label(matches == nil ? L("Doesn't match") : (matches!.exact ? L("Matches") : L("Matches (more displays connected)")),
                      systemImage: matches == nil ? "xmark.circle" : "checkmark.circle")
                    .font(.caption)
                if matches?.usesTier2 == true { Label(L("No serial number"), systemImage: "exclamationmark.triangle").font(.caption) }
                Label(trusted ? L("Trusted") : L("Not trusted"), systemImage: trusted ? "lock.fill" : "lock.open").font(.caption)
                Spacer()
            }
            .foregroundStyle(.secondary)
            Picker(L("Apply automatically"), selection: Binding(get: { layout.autoApply }, set: { v in
                controller.edit(layout.id) { $0.autoApply = v }
            })) {
                Text(L("Never")).tag(LayoutAutoApply.never)
                Text(L("When exactly these displays are connected")).tag(LayoutAutoApply.whenExactly)
                Text(L("When these displays are connected")).tag(LayoutAutoApply.whenIncludes)
            }
            Stepper(L("Priority: \(layout.priority)"), value: Binding(get: { layout.priority }, set: { v in
                controller.edit(layout.id) { $0.priority = v }
            }), in: -100...100)
            HStack {
                Button(L("Apply")) { controller.apply(layout.id) }.disabled(matches == nil)
                if trusted {
                    Button(L("Stop Trusting")) { controller.untrust(layout.id) }
                }
                Button(L("Update to Current")) { replaceWithCurrent() }.disabled(matches == nil)
                Spacer()
                Button(L("Move Up")) { controller.move(layout.id, by: -1) }.disabled(index == 0)
                Button(L("Move Down")) { controller.move(layout.id, by: 1) }
                Button(L("Delete"), role: .destructive) { controller.delete(layout.id) }
            }
        }
        .padding(.vertical, 2)
    }

    private func commitName() {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != layout.name else { return }
        // Renaming doesn't change content, so trust stays.
        controller.edit(layout.id) { $0.name = clean }
        name = ""
    }

    /// Re-captures the layout's content from the current state (clears trust).
    private func replaceWithCurrent() {
        guard let fresh = controller.captureCurrent(name: layout.name) else { return }
        controller.edit(layout.id) { l in
            l.displays = fresh.displays
            l.virtualScreens = fresh.virtualScreens
        }
        controller.delete(fresh.id)
    }
}
