import AppKit
import SwiftUI
import SnapticKit

/// Resolution for the selected display (owner D; PLAN 0.3 §4.3 "Resolution (selected display)").
///
/// Two placements:
/// - `ResolutionSections(env:display:)`: rows for the Displays root page's Resolution section, after F's Resolution
///   and Refresh rate pop-ups: HDR (`hdrToggle`), Rotation (`rotation`) and the collapsed **Resolution options**
///   disclosure (`ResolutionOptionsSection`).
/// - `ResolutionSections()`: the `displays.resolution` page ("More Resolutions…" in the menu): the same controls for
///   the selected display, the options expanded, and "Show All Resolutions" while the Experimental `hiddenModes` runs.
///
/// Live updates (§4.5): mode lists and undo state come from `revision(.resolution)`, rotation and HDR from
/// `revision(.panelProps)`; config through slices. No `objectWillChange` pokes.
struct ResolutionSections: View, ControlDeclaring {
    typealias Controls = ResolutionSectionsControls

    private enum Placement {
        case page(DisplaysPageEnvironment?)
        case rows(DisplaysPageEnvironment, DisplayInfo)
    }

    private let placement: Placement

    /// The `displays.resolution` page; finds the Displays environment through the Settings shell.
    init() {
        placement = .page(DisplaysSettingsLookup.environment())
    }

    /// The `displays.resolution` page with a known environment.
    init(env: DisplaysPageEnvironment) {
        placement = .page(env)
    }

    /// Rows for the root page's Resolution section (the selected display).
    init(env: DisplaysPageEnvironment, display: DisplayInfo) {
        placement = .rows(env, display)
    }

    var body: some View {
        switch placement {
        case .page(let env?):
            ResolutionPageContent(env: env)
        case .page(nil):
            UnavailablePage()
        case .rows(let env, let display):
            ResolutionRows(env: env, display: display, disclosure: true)
        }
    }
}

/// The Displays module's page environment, found through the Settings shell (D's no-argument initializers, which F
/// uses to route `displays.layouts`, `.virtual`, `.resolution`, `.connection`, `.matchTextSize` and the Arrange sheet).
@MainActor enum DisplaysSettingsLookup {
    static func environment() -> DisplaysPageEnvironment? {
        SettingsShell.shared.host?.displays.pageEnvironment
    }

    /// The display the shared tiles selected, else the first one that `qualifies`.
    static func selected(_ displays: [DisplayInfo], where qualifies: (DisplayInfo) -> Bool) -> DisplayInfo? {
        let eligible = displays.filter(qualifies)
        if let key = SettingsShell.shared.selectedDisplay, let match = eligible.first(where: { $0.key == key }) {
            return match
        }
        return eligible.first(where: \.isMain) ?? eligible.first
    }

    /// A display's name while connected, else the remembered one.
    static func name(_ key: DisplayKey, env: DisplaysPageEnvironment) -> String {
        if let info = env.runtime.displays.first(where: { $0.key == key }) { return info.name }
        let identity = env.config.value.perDisplay[key]?.identity
        return identity?.customName ?? identity?.lastKnownName ?? L("A display that isn’t connected")
    }

    /// Display tiles for `PerDisplayPicker`.
    static func tiles(_ displays: [DisplayInfo]) -> [DisplayTile] {
        displays.map { DisplayTile(id: $0.key, name: $0.name, isBuiltin: $0.isBuiltin, badges: DisplaysLive.badges(for: $0)) }
    }

    /// The Display Tools' trial note, with the user's revert time.
    static func trialNote(_ env: DisplaysPageEnvironment) -> String {
        L("Snaptic asks “Keep this change?” and undoes it after \(env.config.value.safety.confirmSeconds) seconds without an answer.")
    }
}

// MARK: - Rows (root page and page)

/// HDR, Rotation and (on the root page) the Resolution options disclosure for one display.
private struct ResolutionRows: View {
    typealias Controls = ResolutionSectionsControls

    let env: DisplaysPageEnvironment
    let display: DisplayInfo
    let disclosure: Bool
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var panel: ControllerRevision
    @State private var expanded = false

    init(env: DisplaysPageEnvironment, display: DisplayInfo, disclosure: Bool) {
        self.env = env
        self.display = display
        self.disclosure = disclosure
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _panel = ObservedObject(wrappedValue: env.runtime.revision(.panelProps))
    }

    var body: some View {
        if let c = env.context?.connectPlanner.panelProps {
            hdrRow(c)
            rotationRow(c)
        }
        if disclosure, runtime.isEffective(.resolution), display.isActive, display.mirrorOf == nil {
            DisclosureGroup(isExpanded: $expanded) {
                ResolutionOptionsSection(env: env, display: display)
            } label: {
                Text(L("Resolution options"))
            }
            .modifier(SettingsAnchor(ControlID("displays.resolution.options")))
            .modifier(SettingsRevealExpansion([ControlID("displays.resolution.slider"),
                                               ControlID("displays.resolution.quickChanges"),
                                               ControlID("displays.resolution.favorite"),
                                               ControlID("displays.resolution.favorites")], isExpanded: $expanded))
        }
    }

    @ViewBuilder private func hdrRow(_ c: PanelPropsController) -> some View {
        if runtime.isEffective(.hdrToggle), display.hdrSupported == true, display.isActive {
            let refusal = c.refusal(.hdrToggle, for: display)
            ToggleSetting(L("High Dynamic Range"),
                          help: L("Shows HDR photos and videos with more brightness and color."),
                          isOn: Binding(get: { c.hdrEnabled(display) == true }, set: { c.setHDR(display.key, $0) }),
                          anchor: ControlID("displays.resolution.hdr"),
                          disabledReason: refusal)
        }
    }

    @ViewBuilder private func rotationRow(_ c: PanelPropsController) -> some View {
        if runtime.isEffective(.rotation), !display.isBuiltin, display.isActive {
            let refusal = c.refusal(.rotation, for: display)
            PickerSetting(L("Rotation"),
                          selection: Binding(get: { c.rotation(display) }, set: { c.rotate(display.key, to: $0) }),
                          options: PanelPropsController.rotations.map {
                              PickerOption($0, $0 == 0 ? L("Standard") : L("\($0)°"))
                          },
                          style: .popUp, defaultValue: nil, anchor: ControlID("displays.resolution.rotation"))
                .disabled(refusal != nil)
            if let refusal {
                SettingsRowNote(refusal)
            }
        }
    }
}

// MARK: - The displays.resolution page

private struct ResolutionPageContent: View {
    typealias Controls = ResolutionSectionsControls

    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var revision: ControllerRevision
    @StateObject private var models = DisplayLiveModelCache()

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _revision = ObservedObject(wrappedValue: env.runtime.revision(.resolution))
    }

    private static let route = SettingsRoute(ResolutionSectionsControls.surface)

    private var eligible: [DisplayInfo] {
        runtime.displays.filter { $0.isOnline && $0.isActive && $0.mirrorOf == nil }
    }

    var body: some View {
        let displays = eligible
        let display = DisplaysSettingsLookup.selected(displays) { _ in true }
        SettingsPageScaffold(route: Self.route) {
            SettingsPageHeader(L("Resolution"),
                               summary: L("Larger text or more space, refresh rates, and favorite sizes for each display."),
                               symbol: "rectangle.arrowtriangle.2.outward", tint: .blue)
            if let ctx = env.context {
                if !runtime.isEffective(.resolution) {
                    Section {
                        StatusRow(featureOffText, actions: featureOffActions)
                    }
                } else if let display {
                    if displays.count > 1 {
                        Section {
                            PerDisplayPicker(DisplaysSettingsLookup.tiles(displays), selection: $shell.selectedDisplay)
                        }
                    }
                    let model = models.model(display.key, context: ctx)
                    Section {
                        LiveResolutionRow(display: display, anchor: ControlID("displays.resolution.mode"), model: model,
                                          revision: revision)
                        LiveRefreshRow(display: display, anchor: ControlID("displays.resolution.refresh"), model: model,
                                       revision: revision)
                        ResolutionRows(env: env, display: display, disclosure: false)
                    } footer: {
                        Text(DisplaysSettingsLookup.trialNote(env))
                    }
                    Section {
                        ResolutionOptionsSection(env: env, display: display)
                    } header: {
                        Text(L("Resolution options"))
                    }
                    if runtime.isEffective(.hiddenModes), let c = ctx.connectPlanner.resolution {
                        AllResolutionsSection(env: env, controller: c, display: display)
                    }
                } else {
                    Section {
                        StatusRow(L("No display can change its resolution right now."))
                    }
                }
            } else {
                Section {
                    StatusRow(L("Turn on Displays to change resolutions."))
                }
            }
            PageFooterButtons(advanced: nil, help: Self.route)
        }
    }

    private var featureOffText: String {
        if case .unavailable(let reason)? = runtime.availability[.resolution] { return reason }
        return env.context?.otherApps.pauseReason(for: .resolution) ?? L("Resolution control is off.")
    }

    private var featureOffActions: [StatusAction] {
        if case .unavailable? = runtime.availability[.resolution] { return [] }
        if env.context?.otherApps.pauseReason(for: .resolution) != nil { return [] }
        return [StatusAction(title: L("Turn On")) { [env] in env.enableFeature(.resolution) }]
    }
}

/// "Show All Resolutions" (Experimental `hiddenModes`): modes macOS hides for the selected display. Each one is a
/// trial that Snaptic undoes without an answer.
private struct AllResolutionsSection: View {
    let env: DisplaysPageEnvironment
    let controller: ResolutionController
    let display: DisplayInfo
    @State private var shown = false

    var body: some View {
        Section {
            if shown, let ctx = env.context {
                let listed = Set(controller.allModes(display).map(\.ref))
                let hidden = (DisplayModes.hiddenList(display.desktopID, api: ctx.privateAPI) ?? [])
                    .filter { !listed.contains($0.ref) }
                if hidden.isEmpty {
                    StatusRow(L("This display has no hidden resolutions."))
                } else {
                    ForEach(Array(hidden.prefix(80)), id: \.ref) { mode in
                        LabeledContent(ResolutionController.plainLabel(mode.ref)) {
                            Button(L("Try")) { controller.tryHiddenMode(mode.ref, on: display.key) }
                                .accessibilityLabel(L("Try \(ResolutionController.plainLabel(mode.ref))"))
                        }
                    }
                }
            } else {
                ButtonRow(L("Show All Resolutions"),
                          help: L("Lists the resolutions macOS hides for \(display.name)."),
                          control: ControlID("displays.resolution.allModes")) {
                    shown = true
                }
            }
        } header: {
            Text(L("Hidden resolutions"))
        } footer: {
            Text(L("Hidden resolutions can leave a display blank. Each one is a trial that Snaptic undoes unless you keep it."))
        }
    }
}
