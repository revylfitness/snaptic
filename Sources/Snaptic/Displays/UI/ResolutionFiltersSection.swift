import SwiftUI
import SnapticKit

/// Displays › Advanced › **Resolution filters** (owner D; PLAN 0.3 §4.3 Advanced group 4): which modes the pop-ups,
/// the menu and the slider offer, and how the slider reads. A section for F's Advanced sheet:
/// `ResolutionFiltersSection(env:)`. The per-display filters are a disclosure for the display the shared tiles
/// selected ("Filters for DELL U2720Q").
struct ResolutionFiltersSection: View, ControlDeclaring {
    typealias Controls = ResolutionSectionsControls

    private let env: DisplaysPageEnvironment?

    init() {
        env = DisplaysSettingsLookup.environment()
    }

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        if let env {
            ResolutionFiltersContent(env: env)
        } else {
            Section(L("Resolution filters")) {
                StatusRow(L("Displays settings aren’t available right now."), style: .warning)
            }
        }
    }
}

private struct ResolutionFiltersContent: View {
    typealias Controls = ResolutionSectionsControls

    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var shell: SettingsShell
    @StateObject private var settings: ConfigSlice<DisplaysConfig, ResolutionConfig>
    @State private var expanded = false

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _settings = StateObject(wrappedValue: ConfigSlice(env.config, \.resolution))
    }

    private var defaults: ResolutionConfig { ResolutionConfig() }

    var body: some View {
        Section {
            ToggleSetting(L("Offer resolutions below 720p"),
                          help: L("Lists very small sizes too, for testing and older software."),
                          isOn: SettingsBinding.store(env.config, \.resolution.allowBelow720p),
                          anchor: ControlID("displays.resolution.filters.below720p"))
            ToggleSetting(L("Remember my choice"),
                          help: L("Restores the resolution you kept when macOS picks another one."),
                          isOn: SettingsBinding.store(env.config, \.resolution.persistedChoice),
                          anchor: ControlID("displays.resolution.filters.remember"))
            ToggleSetting(L("Only the native aspect ratio on the slider"),
                          help: L("Skips sizes that would stretch or letterbox the picture."),
                          isOn: SettingsBinding.store(env.config, \.resolution.sliderNativeAspectOnly),
                          anchor: ControlID("displays.resolution.filters.nativeAspect"))
            PickerSetting(L("Show slider values as"),
                          selection: SettingsBinding.store(env.config, \.resolution.sliderLabel),
                          options: [
                              PickerOption(SliderLabelStyle.size, L("Size")),
                              PickerOption(SliderLabelStyle.percent, L("Percent of Default")),
                          ],
                          style: .popUp, defaultValue: defaults.sliderLabel,
                          anchor: ControlID("displays.resolution.filters.valueStyle"))
            ToggleSetting(L("Snap to favorites"),
                          help: L("The slider stops at a favorite, the default, or native size next to it. Hold ⌥ to skip."),
                          isOn: SettingsBinding.store(env.config, \.resolution.sliderSnapping),
                          anchor: ControlID("displays.resolution.filters.snap"))
            if let display = selectedDisplay {
                DisclosureGroup(isExpanded: $expanded) {
                    ResolutionDisplayFilters(env: env, display: display)
                } label: {
                    Text(L("Filters for \(display.name)"))
                }
                .modifier(SettingsAnchor(ControlID("displays.resolution.filters.display")))
                .modifier(SettingsRevealExpansion([ControlID("displays.resolution.filters.dpi"),
                                                   ControlID("displays.resolution.filters.width"),
                                                   ControlID("displays.resolution.filters.refresh")],
                                                  isExpanded: $expanded))
            }
        } header: {
            Text(L("Resolution filters"))
        }
    }

    private var selectedDisplay: DisplayInfo? {
        DisplaysSettingsLookup.selected(runtime.displays.filter(\.isOnline)) { $0.isActive && $0.mirrorOf == nil }
    }
}

/// One display's filters: HiDPI or standard sizes, width limits and refresh rate.
private struct ResolutionDisplayFilters: View {
    typealias Controls = ResolutionSectionsControls

    let env: DisplaysPageEnvironment
    let display: DisplayInfo
    /// Re-renders when this display's filters change elsewhere (an import, the CLI).
    @StateObject private var perDisplay: ConfigSlice<DisplaysConfig, LossyMap<DisplayKey, PerDisplayConfig>>

    init(env: DisplaysPageEnvironment, display: DisplayInfo) {
        self.env = env
        self.display = display
        _perDisplay = StateObject(wrappedValue: ConfigSlice(env.config, \.perDisplay))
    }

    private func binding<V: Equatable>(_ path: WritableKeyPath<PerDisplayResolution, V>) -> Binding<V> {
        SettingsBinding.lossyEntry(env.config, \.perDisplay, display.key, fallback: { PerDisplayConfig() },
                                   (\PerDisplayConfig.resolution).appending(path: path))
    }

    var body: some View {
        PickerSetting(L("Show"),
                      selection: binding(\.dpiFilter),
                      options: [
                          PickerOption(ModeDPIFilter.all, L("HiDPI and Standard Sizes")),
                          PickerOption(ModeDPIFilter.hiDPIOnly, L("HiDPI Sizes Only")),
                          PickerOption(ModeDPIFilter.loDPIOnly, L("Standard Sizes Only")),
                      ],
                      style: .popUp, defaultValue: ModeDPIFilter.all,
                      anchor: ControlID("displays.resolution.filters.dpi"))
        widthRow
        refreshRow
    }

    private var widthRow: some View {
        let minWidth = binding(\.minWidth)
        let maxWidth = binding(\.maxWidth)
        let isDefault = minWidth.wrappedValue == nil && maxWidth.wrappedValue == nil
        return SettingRow(L("Widths"), help: L("Leave a field empty for no limit."),
                          anchor: ControlID("displays.resolution.filters.width"), isDefault: isDefault,
                          reset: { minWidth.wrappedValue = nil; maxWidth.wrappedValue = nil }) {
            HStack(spacing: 4) {
                TextField(L("Smallest"), value: minWidth, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .accessibilityLabel(L("Smallest width"))
                Text(verbatim: "–").accessibilityHidden(true)
                TextField(L("Largest"), value: maxWidth, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .accessibilityLabel(L("Largest width"))
                Text(L("pt")).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var refreshRow: some View {
        let rates = refreshRates
        if rates.count > 1 {
            PickerSetting(L("Refresh rate"),
                          selection: binding(\.refreshFilter),
                          options: [PickerOption(Int?.none, L("All Rates"))]
                              + rates.map { PickerOption(Optional($0), L("\($0 / 1000) Hz")) },
                          style: .popUp, defaultValue: Int?.none,
                          anchor: ControlID("displays.resolution.filters.refresh"))
        }
    }

    /// The display's whole-hertz rates (millihertz), before filtering.
    private var refreshRates: [Int] {
        guard let c = env.context?.connectPlanner.resolution else { return [] }
        return Array(Set(c.allModes(display).map { $0.ref.refreshMilliHz / 1000 * 1000 }.filter { $0 > 0 })).sorted()
    }
}
