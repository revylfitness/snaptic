import SwiftUI
import SnapticKit

/// Displays › Brightness and Dimming (owner: C; PLAN 0.3 §4.3 sub-page table, route `displays.brightness`): the
/// display tiles for the per-display rows, then `BrightnessSections` (restore, smooth transitions, nits, sync,
/// extra brightness, dimming) and the footer (Advanced… · ?). The header shows the selected display's brightness,
/// in nits where they're known. No feature switch of its own: Brightness control is in Displays › Advanced.
///
/// Live updates (§4.5): config through `ConfigSlice`s, live values through `DisplayRuntime` and the controllers'
/// revisions, so a slider elsewhere doesn't re-render the page.
struct BrightnessSubpage: View, ControlDeclaring {
    typealias Controls = BrightnessSubpageControls

    static let title = L("Brightness and Dimming")
    static let summary = L("Restore, dim, sync, and extra brightness for every display.")
    static let symbol = "sun.max.fill"
    static let tint = SettingsTint.blue

    private let env: DisplaysPageEnvironment?

    /// The Displays module's page environment, found through the Settings shell.
    init() {
        env = CDisplays.environment
    }

    init(env: DisplaysPageEnvironment) {
        self.env = env
    }

    var body: some View {
        if let env, let host = SettingsShell.shared.host {
            BrightnessSubpageContent(env: env, host: host)
        } else {
            UnavailablePage()
        }
    }
}

private struct BrightnessSubpageContent: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var switcher: DisplaysFeatureSwitcher

    init(env: DisplaysPageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
    }

    var body: some View {
        let context = host.isRunning(.displays) ? env.context : nil
        let displays = context == nil ? [] : CDisplays.online(runtime)
        let display = CDisplays.selected(displays, shell.selectedDisplay)
        SettingsPageScaffold(route: SettingsRoute(BrightnessSubpageControls.surface)) {
            if let context, let display, runtime.isEffective(.brightness) {
                BrightnessHeader(display: display, live: runtime.runtime(for: display.key), context: context,
                                 showNits: runtime.isEffective(.nits))
            } else {
                SettingsPageHeader(BrightnessSubpage.title, summary: BrightnessSubpage.summary,
                                   symbol: BrightnessSubpage.symbol, tint: BrightnessSubpage.tint)
            }
            if let context {
                if !runtime.isEffective(.brightness) {
                    CFeatureOffSection(title: L("Brightness control"), feature: .brightness,
                                       isOn: FeatureGraph.rawState(.brightness, in: features.value), context: context,
                                       switcher: switcher)
                } else {
                    if displays.count > 1 {
                        Section {
                            PerDisplayPicker(CDisplays.tiles(displays), selection: $shell.selectedDisplay)
                                .modifier(SettingsAnchor(ControlID("displays.brightness.display")))
                        }
                    }
                    BrightnessSections(env: env, context: context, displays: displays, display: display,
                                       switcher: switcher, features: features.value)
                }
            } else {
                CDisplaysOffSection(runtime: runtime, running: host.isRunning(.displays))
            }
            PageFooterButtons(advanced: { shell.openSheet = BrightnessAdvancedSheetControls.sheet },
                              help: SettingsRoute(BrightnessSubpageControls.surface),
                              advancedControl: ControlID("displays.brightness.advancedButton"))
        }
        .sheet(isPresented: shell.sheetBinding(BrightnessAdvancedSheetControls.sheet)) {
            BrightnessAdvancedSheet(env: env)
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
    }
}

/// The page header with the selected display's brightness now ("Studio Display: 70% · ≈350 nits"); it alone
/// re-renders when the brightness changes.
private struct BrightnessHeader: View {
    let display: DisplayInfo
    @ObservedObject var live: DisplayRuntime
    let context: DisplaysContext
    let showNits: Bool

    var body: some View {
        SettingsPageHeader(BrightnessSubpage.title, summary: BrightnessSubpage.summary, symbol: BrightnessSubpage.symbol,
                           tint: BrightnessSubpage.tint, status: status)
    }

    private var status: String? {
        guard let value = live.brightnessPosition ?? live.brightness else { return nil }
        var text = CDisplays.name(display) + ": " + SettingsFormat.text(value, .percent(of: 1))
        if showNits, let nits = context.brightness.nits(for: display.key) {
            text += " · " + NitsModel.label(nits.value, estimate: nits.estimate)
        }
        return text
    }
}
