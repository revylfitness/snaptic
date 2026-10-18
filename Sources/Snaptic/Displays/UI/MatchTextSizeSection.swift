import SwiftUI
import SnapticKit

/// Display Details › **Match text size** (owner D; PLAN 0.3 §4.3 Display Details, parity §7.3): a disclosure whose
/// label is the `scaleMatch` switch; inside, Include this display, the reference display, the match tolerance and
/// Preview / Apply (one trial for every display it changes).
///
/// `MatchTextSizeSection(env:key:)` is a section for F's Details sheet (left out with one display or when the
/// feature can't run on this Mac). `MatchTextSizeSection()` is the `displays.matchTextSize` page (Display Tools ›
/// "Match Text Size…") for the selected display, expanded.
struct MatchTextSizeSection: View, ControlDeclaring {
    typealias Controls = MatchTextSizeSectionControls

    private let env: DisplaysPageEnvironment?
    private let key: DisplayKey?
    private let isPage: Bool

    init() {
        env = DisplaysSettingsLookup.environment()
        key = nil
        isPage = true
    }

    init(env: DisplaysPageEnvironment, key: DisplayKey) {
        self.env = env
        self.key = key
        isPage = false
    }

    var body: some View {
        if isPage {
            if let env {
                MatchTextSizePage(env: env)
            } else {
                UnavailablePage()
            }
        } else if let env, let key {
            MatchTextSizeRows(env: env, key: key, startsExpanded: false)
        }
    }
}

private struct MatchTextSizePage: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var shell: SettingsShell

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
    }

    private static let route = SettingsRoute(MatchTextSizeSectionControls.surface)

    var body: some View {
        let displays = runtime.displays.filter { $0.isOnline && $0.isActive && $0.mirrorOf == nil }
        let display = DisplaysSettingsLookup.selected(displays) { _ in true }
        SettingsPageScaffold(route: Self.route) {
            SettingsPageHeader(L("Match Text Size"),
                               summary: L("Picks resolutions so text looks the same size on every display."),
                               symbol: "textformat.size", tint: .blue)
            if env.context == nil {
                Section {
                    StatusRow(L("Turn on Displays to match text sizes."))
                }
            } else if displays.count < 2 {
                Section {
                    StatusRow(L("Connect another display to match text sizes."))
                }
            } else if let display {
                Section {
                    PerDisplayPicker(DisplaysSettingsLookup.tiles(displays), selection: $shell.selectedDisplay)
                }
                MatchTextSizeRows(env: env, key: display.key, startsExpanded: true)
            }
            PageFooterButtons(advanced: nil, help: Self.route)
        }
    }
}

private struct MatchTextSizeRows: View {
    typealias Controls = MatchTextSizeSectionControls

    let env: DisplaysPageEnvironment
    let key: DisplayKey
    let startsExpanded: Bool
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var revision: ControllerRevision
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @StateObject private var settings: ConfigSlice<DisplaysConfig, ResolutionConfig>
    @StateObject private var perDisplay: ConfigSlice<DisplaysConfig, LossyMap<DisplayKey, PerDisplayConfig>>
    @State private var expanded: Bool?
    @State private var proposals: [ScaleMatchProposal] = []

    init(env: DisplaysPageEnvironment, key: DisplayKey, startsExpanded: Bool) {
        self.env = env
        self.key = key
        self.startsExpanded = startsExpanded
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _revision = ObservedObject(wrappedValue: env.runtime.revision(.resolution))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
        _settings = StateObject(wrappedValue: ConfigSlice(env.config, \.resolution))
        _perDisplay = StateObject(wrappedValue: ConfigSlice(env.config, \.perDisplay))
    }

    private var active: [DisplayInfo] { runtime.displays.filter { $0.isActive && $0.mirrorOf == nil } }

    private var available: Bool {
        if case .unavailable? = runtime.availability[.scaleMatch] { return false }
        return true
    }

    private var isExpanded: Binding<Bool> {
        Binding(get: { expanded ?? startsExpanded }, set: { expanded = $0 })
    }

    var body: some View {
        if available, active.count >= 2, active.contains(where: { $0.key == key }) {
            Section {
                DisclosureGroup(isExpanded: isExpanded) {
                    if runtime.isEffective(.scaleMatch), let c = env.context?.connectPlanner.resolution {
                        options(c)
                    } else if let paused = env.context?.otherApps.pauseReason(for: .scaleMatch) {
                        SettingsRowNote(paused)
                    }
                } label: {
                    ToggleSetting(L("Match text size"),
                                  help: L("Picks resolutions so text looks the same size on every display."),
                                  isOn: switcher.binding([.scaleMatch], title: L("Match text size")),
                                  anchor: ControlID("displays.matchTextSize.enabled"))
                }
                .modifier(SettingsRevealExpansion([ControlID("displays.matchTextSize.include"),
                                                   ControlID("displays.matchTextSize.reference"),
                                                   ControlID("displays.matchTextSize.tolerance"),
                                                   ControlID("displays.matchTextSize.preview"),
                                                   ControlID("displays.matchTextSize.apply")], isExpanded: isExpanded))
            }
            .modifier(DisplaysFeatureOffAlert(switcher: switcher))
        }
    }

    @ViewBuilder private func options(_ c: ResolutionController) -> some View {
        let referenceKey = settings.value.scaleMatchReference ?? active.first(where: \.isMain)?.key
        if referenceKey != key {
            ToggleSetting(L("Include this display"),
                          help: L("Changes this display’s resolution to match the reference display."),
                          isOn: SettingsBinding.lossyEntry(env.config, \.perDisplay, key, fallback: { PerDisplayConfig() },
                                                           \.resolution.matchUIScale),
                          anchor: ControlID("displays.matchTextSize.include"))
        }
        PickerSetting(L("Reference display"),
                      help: L("The display whose text size the others match."),
                      selection: SettingsBinding.store(env.config, \.resolution.scaleMatchReference),
                      options: [PickerOption(DisplayKey?.none, L("Main display"))]
                          + active.map { PickerOption(Optional($0.key), $0.name) },
                      style: .popUp, defaultValue: DisplayKey?.none,
                      anchor: ControlID("displays.matchTextSize.reference"))
        SliderSetting(L("Match tolerance"),
                      help: L("How far apart text sizes may be before Snaptic changes a resolution."),
                      value: SettingsBinding.store(env.config, \.resolution.scaleMatchTolerance),
                      in: ResolutionConfig.scaleMatchToleranceRange, step: 0.01,
                      defaultValue: ResolutionConfig().scaleMatchTolerance, format: .percent(of: 1),
                      anchor: ControlID("displays.matchTextSize.tolerance"))
        if proposals.isEmpty {
            ButtonRow(L("Preview"), help: L("Shows the resolutions that would change."),
                      control: ControlID("displays.matchTextSize.preview")) {
                FocusedField.commit()
                preview = nil
                proposals = c.scaleMatchProposals()
                if proposals.isEmpty {
                    preview = L("Text already looks the same size on every included display.")
                }
            }
            if let preview {
                SettingsRowNote(preview)
            }
        } else {
            ForEach(proposals, id: \.key) { p in
                LabeledContent(DisplaysSettingsLookup.name(p.key, env: env)) {
                    Text(L("\(ResolutionController.plainLabel(p.from)) → \(ResolutionController.plainLabel(p.to))"))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(L("Cancel")) { proposals = [] }
                Spacer()
                Button(L("Apply")) {
                    c.applyScaleMatch(proposals)
                    proposals = []
                }
                .modifier(SettingsAnchor(ControlID("displays.matchTextSize.apply")))
            }
        }
    }

    @State private var preview: String?
}
