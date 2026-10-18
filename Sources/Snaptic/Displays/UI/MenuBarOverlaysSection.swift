import SwiftUI
import SnapticKit

/// Display Details… › **Menu bar overlays** (owner: C; PLAN 0.3 §4.3 Display Details sheet): the group switch
/// (`menuBarOverlays`), then for this display the black strip behind the menu bar and the top and bottom corner
/// radius. One section for a grouped `Form`: F's Details sheet composes it as `MenuBarOverlaysSection(key:)` (or
/// `MenuBarOverlaysSection(env:key:)`). Config through `ConfigSlice`s; MenuBarOverlaysController's revision marks
/// changes the controller made (Restore All Displays holds the overlays).
struct MenuBarOverlaysSection: View, ControlDeclaring {
    typealias Controls = MenuBarOverlaysSectionControls

    private let env: DisplaysPageEnvironment?
    let key: DisplayKey?

    /// The Displays module's page environment, found through the Settings shell.
    init(key: DisplayKey?) {
        env = CDisplays.environment
        self.key = key
    }

    init(env: DisplaysPageEnvironment, key: DisplayKey?) {
        self.env = env
        self.key = key
    }

    var body: some View {
        if let env, let key {
            MenuBarOverlaysContent(env: env, key: key)
        }
    }
}

private struct MenuBarOverlaysContent: View {
    let env: DisplaysPageEnvironment
    let key: DisplayKey
    @ObservedObject private var runtime: DisplaysRuntimeState
    @ObservedObject private var revision: ControllerRevision
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var perDisplay: ConfigSlice<DisplaysConfig, LossyMap<DisplayKey, PerDisplayConfig>>
    @StateObject private var switcher: DisplaysFeatureSwitcher

    init(env: DisplaysPageEnvironment, key: DisplayKey) {
        self.env = env
        self.key = key
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _revision = ObservedObject(wrappedValue: env.runtime.revision(.menuBarOverlays))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
        _perDisplay = StateObject(wrappedValue: ConfigSlice(env.config, \.perDisplay))
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
    }

    var body: some View {
        let display = runtime.displays.first { $0.key == key }
        let on = FeatureGraph.rawState(.menuBarOverlays, in: features.value)
        Section {
            ToggleSetting(L("Menu bar overlays"), help: L("A black menu bar background and rounded screen corners."),
                          isOn: switcher.binding([.menuBarOverlays], title: L("Menu bar overlays")),
                          anchor: ControlID("displays.overlays.enabled"),
                          disabledReason: switcher.unavailableReason([.menuBarOverlays]))
            if on {
                if display?.mirrorOf != nil {
                    SettingsRowNote(L("A mirrored display shows the overlays of the display it mirrors."))
                        .padding(.leading, 20)
                } else {
                    ToggleSetting(L("Black strip behind the menu bar"),
                                  help: (display?.notchInset ?? 0) > 0 ? L("Also hides the notch.") : nil,
                                  isOn: CBind.display(env.config, key, \.color.menuBarStrip), subordinate: true,
                                  anchor: ControlID("displays.overlays.strip"))
                    SliderSetting(L("Top corner radius"),
                                  value: CBind.display(env.config, key, \.color.cornerRadiusTop),
                                  in: PerDisplayColor.cornerRange, step: 0.0003, defaultValue: PerDisplayColor().cornerRadiusTop,
                                  format: .percent(of: PerDisplayColor.cornerRange.upperBound),
                                  anchor: ControlID("displays.overlays.topRadius"), subordinate: true)
                    SliderSetting(L("Bottom corner radius"),
                                  value: CBind.display(env.config, key, \.color.cornerRadiusBottom),
                                  in: PerDisplayColor.cornerRange, step: 0.0003,
                                  defaultValue: PerDisplayColor().cornerRadiusBottom,
                                  format: .percent(of: PerDisplayColor.cornerRange.upperBound),
                                  anchor: ControlID("displays.overlays.bottomRadius"), subordinate: true)
                }
            }
        } header: {
            Text(L("Menu bar overlays"))
        } footer: {
            if on {
                Text(L("Overlays don’t show in screenshots or screen sharing, and Restore All Displays removes them."))
            }
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
    }
}
