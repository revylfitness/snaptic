import SwiftUI
import SnapticKit

/// The 0.2 "Arrangement" page id (`displays.arrangement`), kept only while `DisplaysModule.settingsPages()` lists it
/// and the root page's Arrange Displays… still pushes it (both go in the step-3 coordinated merge). It shows the 0.3
/// pieces: Use as and the arrangement for each display, each display's Connection group, and 0.2's per-display
/// display-sleep switches, which stay until `sleepPrevention` moves to Awake (§2.13, phase 3b).
struct ArrangementPage: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState

    init(env: DisplaysPageEnvironment) {
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
    }

    var body: some View {
        let online = runtime.displays.filter(\.isOnline)
        let active = online.filter { $0.isActive && $0.mirrorOf == nil }
        SettingsPageScaffold(route: SettingsRoute("displays.arrangement")) {
            SettingsPageHeader(L("Arrangement"), summary: L("Where your displays are, which one is main, and mirroring."),
                               symbol: "rectangle.3.group", tint: .indigo)
            if env.context == nil {
                Section {
                    StatusRow(L("Turn on Displays to arrange your displays."))
                }
            } else {
                if online.count > 1 {
                    ForEach(online, id: \.key) { display in
                        Section {
                            ArrangementRows(env: env, display: display, displayCount: online.count,
                                            showsArrangeButton: false)
                        } header: {
                            Text(display.name)
                        }
                    }
                }
                if active.count > 1 {
                    ArrangeContent(env: env)
                }
                ForEach(online, id: \.key) { display in
                    ConnectionSection(env: env, key: display.key)
                }
                if runtime.isEffective(.sleepPrevention) {
                    Section {
                        ForEach(online, id: \.key) { display in
                            ToggleSetting(L("Keep the display awake while “\(display.name)” is connected"),
                                          isOn: SettingsBinding.lossyEntry(env.config, \.perDisplay, display.key,
                                                                           fallback: { PerDisplayConfig() },
                                                                           \.management.preventSleep))
                        }
                    } header: {
                        Text(L("Display sleep"))
                    } footer: {
                        Text(L("This also prevents the automatic screen lock. Awake replaces this setting."))
                    }
                }
            }
        }
    }
}
