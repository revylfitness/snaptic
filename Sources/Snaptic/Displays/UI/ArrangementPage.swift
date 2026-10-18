import SwiftUI
import SnapticKit

/// Arrangement (PLAN §9.6): canvas, Position/Align (16 placements), main display,
/// mirroring, rotation/underscan/HDR, disconnect and auto-disconnect, sleep prevention.
struct ArrangementPage: View {
    @ObservedObject var env: DisplaysPageEnvironment

    private var planner: ConnectPlanner? { env.context?.connectPlanner }
    private var displays: [DisplayInfo] { env.runtime.displays }
    private var active: [DisplayInfo] { displays.filter { $0.isActive && $0.mirrorOf == nil } }

    var body: some View {
        Form {
            DisplaysStatusSection(env: env)
            if env.context == nil {
                Section { ManagementOffNotice() }
            } else {
                arrangementSection
                mainSection
                mirroringSection
                PanelPropsSection(env: env, displays: displays)
                PowerSection(env: env, displays: displays)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var arrangementSection: some View {
        Section {
            ManagementFeatureNotice(env: env, feature: .arrangement, title: L("Arrangement"))
            if env.runtime.isEffective(.arrangement), planner?.arrangement != nil {
                ArrangementCanvas(env: env)
                Toggle(L("Snap to edges while dragging"), isOn: ManagementBindings.config(env, \.management.snapArrangement))
                PositionAlignForm(env: env, displays: active)
            }
        } header: {
            Text(L("Arrangement"))
        } footer: {
            ManagementNote(L("Moving displays is applied right away; macOS keeps it."))
        }
    }

    @ViewBuilder private var mainSection: some View {
        Section {
            ManagementFeatureNotice(env: env, feature: .mainDisplay, title: L("Main display"))
            if env.runtime.isEffective(.mainDisplay), let c = planner?.arrangement {
                Picker(L("Main display"), selection: Binding<DisplayKey?>(
                    get: { displays.first(where: \.isMain)?.key },
                    set: { k in if let k { c.setMain(k) } })) {
                    ForEach(active, id: \.key) { d in
                        Text(d.name).tag(Optional(d.key))
                    }
                }
                ManagementNote(L("The main display has the menu bar. It must be a visible physical display."))
            }
        } header: {
            Text(L("Main display"))
        }
    }

    @ViewBuilder private var mirroringSection: some View {
        Section {
            ManagementFeatureNotice(env: env, feature: .mirroring, title: L("Mirroring"))
            if env.runtime.isEffective(.mirroring), let c = planner?.arrangement {
                ForEach(displays.filter(\.isActive), id: \.key) { d in
                    Picker(d.name, selection: Binding<DisplayKey?>(
                        get: { d.mirrorOf.flatMap { src in displays.first { $0.desktopID == src || $0.hardwareID == src }?.key } },
                        set: { c.mirror(d.key, of: $0) })) {
                        Text(L("Not mirroring")).tag(DisplayKey?.none)
                        ForEach(active.filter { $0.key != d.key }, id: \.key) { other in
                            Text(L("Mirror \(other.name)")).tag(Optional(other.key))
                        }
                    }
                }
                ManagementNote(L("Mirroring is a trial: it reverts after 15 seconds unless you keep it."))
            }
        } header: {
            Text(L("Mirroring"))
        }
    }
}

/// Position/Align: 16 placements relative to another display (keyboard-friendly arranging).
private struct PositionAlignForm: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let displays: [DisplayInfo]
    @State private var moving: DisplayKey?
    @State private var reference: DisplayKey?
    @State private var placement: ArrangementPlacement = .rightCenter

    var body: some View {
        Picker(L("Move"), selection: $moving) {
            Text(L("Choose…")).tag(DisplayKey?.none)
            ForEach(displays, id: \.key) { d in Text(d.name).tag(Optional(d.key)) }
        }
        Picker(L("Placement"), selection: $placement) {
            ForEach(ArrangementPlacement.allCases, id: \.self) { p in Text(p.title).tag(p) }
        }
        Picker(L("Relative to"), selection: $reference) {
            Text(L("Choose…")).tag(DisplayKey?.none)
            ForEach(displays.filter { $0.key != moving }, id: \.key) { d in Text(d.name).tag(Optional(d.key)) }
        }
        Button(L("Move Display")) {
            if let m = moving, let r = reference { env.context?.connectPlanner.arrangement?.place(m, placement, relativeTo: r) }
        }
        .disabled(moving == nil || reference == nil || moving == reference)
    }
}

/// Rotation, HDR and underscan (trials; refused when the safety helper can't revert them).
private struct PanelPropsSection: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let displays: [DisplayInfo]
    @State private var underscanDraft: [DisplayKey: Double] = [:]

    private var anyOn: Bool { [.rotation, .underscan, .hdrToggle].contains { env.runtime.isEffective($0) } }

    var body: some View {
        Section {
            ManagementFeatureNotice(env: env, feature: .rotation, title: L("Rotation"))
            ManagementFeatureNotice(env: env, feature: .hdrToggle, title: L("HDR switch"))
            ManagementFeatureNotice(env: env, feature: .underscan, title: L("Underscan"))
            if anyOn, let c = env.context?.connectPlanner.panelProps {
                ForEach(displays.filter(\.isActive), id: \.key) { d in
                    row(d, c)
                }
            }
        } header: {
            Text(L("Rotation, HDR and underscan"))
        } footer: {
            ManagementNote(L("These are trials, reverted after 15 seconds unless you keep them, and can't be used on the only visible display (HDR, underscan)."))
        }
    }

    @ViewBuilder private func row(_ d: DisplayInfo, _ c: PanelPropsController) -> some View {
        if env.runtime.isEffective(.rotation), !d.isBuiltin {
            Picker(L("Rotation of \(d.name)"), selection: Binding(get: { c.rotation(d) }, set: { c.rotate(d.key, to: $0) })) {
                ForEach(PanelPropsController.rotations, id: \.self) { r in Text(r == 0 ? L("Standard") : "\(r)°").tag(r) }
            }
            .disabled(c.refusal(.rotation, for: d) != nil)
        }
        if env.runtime.isEffective(.hdrToggle), d.hdrSupported == true {
            Toggle(L("HDR on \(d.name)"), isOn: Binding(get: { c.hdrEnabled(d) == true }, set: { c.setHDR(d.key, $0) }))
                .disabled(c.refusal(.hdrToggle, for: d) != nil)
        }
        if env.runtime.isEffective(.underscan), c.underscan(d) != nil || !d.isBuiltin {
            HStack {
                Text(L("Underscan \(d.name)"))
                Slider(value: Binding(get: { underscanDraft[d.key] ?? c.underscan(d) ?? 0 }, set: { underscanDraft[d.key] = $0 }), in: 0...1)
                Button(L("Apply")) {
                    if let v = underscanDraft[d.key] { c.setUnderscan(d.key, v) }
                    underscanDraft[d.key] = nil
                }
                .disabled(underscanDraft[d.key] == nil || c.refusal(.underscan, for: d) != nil)
            }
        }
        if let why = [DisplayFeature.rotation, .hdrToggle, .underscan].lazy.compactMap({ c.refusal($0, for: d) }).first,
           why == L("Safety helper can't revert this") {
            ManagementNote(why)
        }
    }
}

/// Disconnect, auto-disconnect of the built-in display, and sleep prevention.
private struct PowerSection: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let displays: [DisplayInfo]

    var body: some View {
        Section {
            ManagementFeatureNotice(env: env, feature: .disconnect, title: L("Disconnect"))
            if env.runtime.isEffective(.disconnect), let c = env.context?.connectPlanner.power {
                ForEach(displays, id: \.key) { d in
                    HStack {
                        Text(d.name)
                        Spacer()
                        Picker(L("Header switch"), selection: ManagementBindings.perDisplay(env, d.key, \.management.powerSwitch)) {
                            Text(L("None")).tag(HeaderPowerSwitch.none)
                            Text(L("Connect / Disconnect")).tag(HeaderPowerSwitch.disconnect)
                            Text(L("Monitor standby (DDC)")).tag(HeaderPowerSwitch.ddcStandby)
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                        if c.disabledKeys.contains(d.key) || !d.isActive {
                            Button(L("Connect")) { c.connect(d.key) }
                        } else {
                            Button(L("Disconnect")) { c.disconnect(d.key) }
                                .disabled(c.disconnectRefusal(d) != nil)
                                .help(c.disconnectRefusal(d) ?? "")
                        }
                    }
                }
                Button(L("Connect All Displays")) { c.connectAll() }
                    .disabled(c.disabledKeys.isEmpty)
                ManagementNote(L("Disconnecting is a trial and lasts until you reconnect, quit Snaptic or restart."))
            }
            if let note = PowerController.disconnectNote { ManagementNote(note) }
        } header: {
            HStack {
                Text(L("Disconnect"))
                if PowerController.disconnectIsExperimental {
                    DisplaysBadge(text: L("Experimental"), tint: .purple)
                }
            }
        }
        Section {
            ManagementFeatureNotice(env: env, feature: .autoDisconnectBuiltin, title: L("Auto-disconnect built-in display"))
            if env.runtime.isEffective(.autoDisconnectBuiltin) {
                Toggle(L("My monitor has no DDC (allow without a power reading)"),
                       isOn: ManagementBindings.config(env, \.management.autoDisconnectWithoutDDC))
                ForEach(displays.filter(\.isBuiltin), id: \.key) { d in
                    Toggle(L("Never auto-disconnect \(d.name)"),
                           isOn: ManagementBindings.perDisplay(env, d.key, \.management.ignoreForAutoDisconnect))
                }
                ManagementNote(L("Only when the lid is open and the external display is visible and reports \"on\" over DDC (or is an Apple display). This avoids blacking out with a dummy plug."))
            }
        } header: {
            Text(L("Auto-disconnect"))
        }
        Section {
            ManagementFeatureNotice(env: env, feature: .sleepPrevention, title: L("Prevent display sleep"))
            if env.runtime.isEffective(.sleepPrevention) {
                ForEach(displays, id: \.key) { d in
                    Toggle(L("Prevent display sleep while \(d.name) is connected"),
                           isOn: ManagementBindings.perDisplay(env, d.key, \.management.preventSleep))
                }
                ManagementNote(L("This also prevents the automatic screen lock."))
            }
        } header: {
            Text(L("Sleep"))
        }
    }
}
