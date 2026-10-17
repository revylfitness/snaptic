import SwiftUI
import SnapticKit

/// Resolution (PLAN §9.1): modes with filters and markers, slider settings, favorites,
/// HiDPI/native/default/halved, undo/redo, notch, range limits, persisted choice, "Show
/// all" (hidden modes) and Match UI size.
struct ResolutionPage: View {
    @ObservedObject var env: DisplaysPageEnvironment

    private var controller: ResolutionController? { env.context?.connectPlanner.resolution }
    private var displays: [DisplayInfo] { env.runtime.displays.filter { $0.isActive && $0.mirrorOf == nil } }

    var body: some View {
        Form {
            DisplaysStatusSection(env: env)
            Section {
                ManagementFeatureNotice(env: env, feature: .resolution, title: L("Resolution"))
                Picker(L("Confirm resolution changes"), selection: ManagementBindings.config(env, \.resolution.confirm)) {
                    Text(L("New modes only")).tag(ResolutionConfirmPolicy.newModesOnly)
                    Text(L("Always")).tag(ResolutionConfirmPolicy.always)
                    Text(L("Never for public modes")).tag(ResolutionConfirmPolicy.neverForPublicModes)
                }
                Toggle(L("Offer modes below 720p"), isOn: ManagementBindings.config(env, \.resolution.allowBelow720p))
                Toggle(L("Remember my choice and restore it when macOS doesn't"),
                       isOn: ManagementBindings.config(env, \.resolution.persistedChoice))
            } header: {
                Text(L("Resolution"))
            } footer: {
                ManagementNote(L("Unfamiliar modes are applied as a trial: Snaptic reverts them after 15 seconds unless you keep them."))
            }
            Section(L("Slider")) {
                Picker(L("Show values as"), selection: ManagementBindings.config(env, \.resolution.sliderLabel)) {
                    Text(L("Size")).tag(SliderLabelStyle.size)
                    Text(L("Percent of default")).tag(SliderLabelStyle.percent)
                }
                Toggle(L("Snap to favorites, current, default and native (hold ⌥ to skip)"),
                       isOn: ManagementBindings.config(env, \.resolution.sliderSnapping))
                Toggle(L("Only the display's native aspect ratio"), isOn: ManagementBindings.config(env, \.resolution.sliderNativeAspectOnly))
            }
            if env.context == nil {
                Section { ManagementOffNotice() }
            } else if let c = controller {
                ForEach(displays, id: \.key) { d in
                    ResolutionDisplaySection(env: env, controller: c, display: d)
                }
                if env.runtime.isEffective(.hiddenModes) || env.runtime.availability[.hiddenModes]?.isAvailable == true {
                    HiddenModesSection(env: env, controller: c, displays: displays)
                }
                ScaleMatchSection(env: env, controller: c, displays: displays)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ResolutionDisplaySection: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let controller: ResolutionController
    let display: DisplayInfo

    private var key: DisplayKey { display.key }
    private var current: ModeRef? { controller.currentMode(display) }

    var body: some View {
        Section {
            modePicker
            HStack {
                quick(L("HiDPI"), controller.hiDPIToggleTarget(key))
                quick(L("Native"), controller.native(key))
                quick(L("Default"), controller.defaultMode(key))
                quick(L("Native ÷ 2"), controller.nativeHalved(key))
                if let notch = controller.notchToggleTarget(key) { quick(L("Notch"), notch) }
            }
            HStack {
                Button(L("Undo")) { controller.undo(key) }.disabled(!controller.canUndo(key))
                Button(L("Redo")) { controller.redo(key) }.disabled(!controller.canRedo(key))
                Spacer()
                if let current, !controller.favorites(key).contains(FavoriteMode(current)) {
                    Button(L("Add to Favorites")) { controller.saveFavorite(current, on: key) }
                }
            }
            favorites
            filters
            if let p = env.config.value.perDisplay[key]?.resolution.persisted {
                HStack {
                    ManagementNote(L("Remembered choice: \(ManagementText.mode(p.mode))"))
                    Spacer()
                    Button(L("Forget")) {
                        ManagementBindings.perDisplay(env, key, \.resolution.persisted).wrappedValue = nil
                    }
                }
            }
        } header: {
            Text(display.name)
        }
    }

    private var modePicker: some View {
        let modes = controller.modes(for: key)
        return Picker(L("Mode"), selection: Binding<ModeRef?>(get: { current }, set: { m in if let m { controller.apply(m, to: key) } })) {
            if current == nil { Text(L("Unknown")).tag(ModeRef?.none) }
            ForEach(modes, id: \.ref) { m in
                Text(controller.label(m.ref, key: key)).tag(Optional(m.ref))
            }
        }
        .accessibilityLabel(L("Resolution of \(display.name)"))
    }

    private func quick(_ title: String, _ target: ModeRef?) -> some View {
        Button(title) { if let target { controller.apply(target, to: key) } }
            .disabled(target == nil || target == current)
    }

    @ViewBuilder private var favorites: some View {
        let favs = controller.favorites(key)
        if !favs.isEmpty {
            ForEach(Array(favs.enumerated()), id: \.element) { i, f in
                HStack {
                    Text(L("Favorite \(i + 1): \(f.label)"))
                    Spacer()
                    Button(L("Apply")) { controller.applyFavorite(i, on: key) }
                    Button(L("Remove")) { controller.removeFavorite(f, on: key) }
                        .accessibilityLabel(L("Remove favorite \(i + 1)"))
                }
            }
        }
    }

    @ViewBuilder private var filters: some View {
        Picker(L("Show"), selection: ManagementBindings.perDisplay(env, key, \.resolution.dpiFilter)) {
            Text(L("HiDPI and standard")).tag(ModeDPIFilter.all)
            Text(L("HiDPI only")).tag(ModeDPIFilter.hiDPIOnly)
            Text(L("Standard only")).tag(ModeDPIFilter.loDPIOnly)
        }
        let rates = Array(Set(ManagedModes.modes(for: display.desktopID).map { $0.ref.refreshMilliHz / 1000 * 1000 })).sorted()
        if rates.count > 1 {
            Picker(L("Refresh rate"), selection: ManagementBindings.perDisplay(env, key, \.resolution.refreshFilter)) {
                Text(L("All")).tag(Int?.none)
                ForEach(rates, id: \.self) { r in Text("\(r / 1000) Hz").tag(Optional(r)) }
            }
        }
        RangeLimitRow(env: env, key: key)
        Toggle(L("Include in Match UI Size"), isOn: ManagementBindings.perDisplay(env, key, \.resolution.matchUIScale))
    }
}

private struct RangeLimitRow: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let key: DisplayKey

    var body: some View {
        let minW = ManagementBindings.perDisplay(env, key, \.resolution.minWidth)
        let maxW = ManagementBindings.perDisplay(env, key, \.resolution.maxWidth)
        HStack {
            Text(L("Width limit"))
            Spacer()
            TextField(L("Min"), value: minW, format: .number).frame(width: 70).accessibilityLabel(L("Minimum width"))
            Text("–")
            TextField(L("Max"), value: maxW, format: .number).frame(width: 70).accessibilityLabel(L("Maximum width"))
            Button(L("Clear")) { minW.wrappedValue = nil; maxW.wrappedValue = nil }
                .disabled(minW.wrappedValue == nil && maxW.wrappedValue == nil)
        }
    }
}

/// "Show all modes" (CGS, Experimental): modes macOS hides. Always applied as a trial.
private struct HiddenModesSection: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let controller: ResolutionController
    let displays: [DisplayInfo]
    @State private var shownFor: DisplayKey?

    var body: some View {
        Section {
            ManagementFeatureNotice(env: env, feature: .hiddenModes, title: L("Show all modes"))
            if env.runtime.isEffective(.hiddenModes), let ctx = env.context {
                Picker(L("Display"), selection: $shownFor) {
                    Text(L("Choose…")).tag(DisplayKey?.none)
                    ForEach(displays, id: \.key) { d in Text(d.name).tag(Optional(d.key)) }
                }
                if let key = shownFor, let d = displays.first(where: { $0.key == key }) {
                    let publicModes = Set(ManagedModes.modes(for: d.desktopID).map(\.ref))
                    let hidden = (DisplayModes.hiddenList(d.desktopID, api: ctx.privateAPI) ?? []).filter { !publicModes.contains($0.ref) }
                    if hidden.isEmpty {
                        ManagementNote(L("No extra modes."))
                    }
                    ForEach(hidden.prefix(80), id: \.ref) { m in
                        HStack {
                            Text(ManagementText.mode(m.ref))
                            Spacer()
                            Button(L("Try")) {
                                ManagedTransactions.submit(ctx, TransactionRequest(label: L("Try hidden mode"), risk: .trial,
                                                                                   changes: [.mode(d.desktopID, m.ref)]),
                                                           lifetime: ctx.lifetime)
                            }
                        }
                    }
                }
            }
        } header: {
            Text(L("Show all modes"))
        } footer: {
            ManagementNote(L("Hidden modes can blank a display. They always run as a 15-second trial."))
        }
    }
}

/// Match UI size (parity §7.3): preview, then one trial for all displays.
private struct ScaleMatchSection: View {
    @ObservedObject var env: DisplaysPageEnvironment
    let controller: ResolutionController
    let displays: [DisplayInfo]
    @State private var preview: [ScaleMatchProposal] = []

    var body: some View {
        Section {
            ManagementFeatureNotice(env: env, feature: .scaleMatch, title: L("Match UI size"))
            if env.runtime.isEffective(.scaleMatch) {
                Picker(L("Reference display"), selection: ManagementBindings.config(env, \.resolution.scaleMatchReference)) {
                    Text(L("Main display")).tag(DisplayKey?.none)
                    ForEach(displays, id: \.key) { d in Text(d.name).tag(Optional(d.key)) }
                }
                HStack {
                    Text(L("Tolerance"))
                    Slider(value: ManagementBindings.config(env, \.resolution.scaleMatchTolerance), in: 0.01...0.5)
                    Text(String(format: "%.0f%%", env.config.value.resolution.scaleMatchTolerance * 100)).monospacedDigit()
                }
                Button(L("Preview")) { preview = controller.scaleMatchProposals() }
                if !preview.isEmpty {
                    ForEach(preview, id: \.key) { p in
                        Text("\(displays.first { $0.key == p.key }?.name ?? "") → \(ManagementText.mode(p.to))")
                    }
                    Button(L("Apply (trial)")) {
                        controller.applyScaleMatch(preview)
                        preview = []
                    }
                }
            }
        } header: {
            Text(L("Match UI size"))
        } footer: {
            ManagementNote(L("Uses each display's physical size so text looks the same size everywhere."))
        }
    }
}
