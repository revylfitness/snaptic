import SwiftUI
import SnapticKit

/// Dock Previews › Advanced (lead; PLAN 0.5 §4.18, §4.5, §4.10, §4.15, §4.16, A7): sort, keys, apps with no open
/// windows, other Dock preview apps, VoiceOver, the Privacy section shared with the Window Switcher, the Dock-only
/// hidden apps list, and Diagnostics with the live `Dock.disable.*` and `Windows.disable.*` keys as read-only
/// `DefaultsLockRow`s. Footer: the sheet's own Restore Defaults, which never touches the shared privacy settings.
struct DockAdvancedSheet: View, ControlDeclaring {
    typealias Controls = DockAdvancedSheetControls

    let module: DockPreviewsModule
    @ObservedObject private var config: ConfigStore<DockConfig>
    /// The switcher's store: “Protect private windows” and its app list live there, for both modules (§4.10).
    @ObservedObject private var settings: AppSettings

    init(module: DockPreviewsModule) {
        self.module = module
        _config = ObservedObject(wrappedValue: module.config)
        _settings = ObservedObject(wrappedValue: AppSettings.shared)
    }

    var body: some View {
        AdvancedSheet(L("Dock Previews Advanced Settings"), restoreDefaults: restore,
                      restoreControl: ControlID("dock.advanced.restore")) {
            behaviourSection
            privacySection
            AppListEditor(L("Apps hidden from Dock previews"),
                          help: L("Pointing at these apps in the Dock shows nothing. The Window Switcher isn’t affected."),
                          bundleIDs: SettingsBinding.store(config, \.hiddenBundleIDs),
                          anchor: ControlID("dock.advanced.hiddenApps"))
            diagnosticsSection
        }
    }

    // MARK: Rows

    @ViewBuilder private var behaviourSection: some View {
        // Read live, like the page's click actions lock: the tap reads the key when it starts.
        let keysKilled = DockPreviewsModule.readKillSwitches(.standard).contains(.keys)
        Section {
            PickerSetting(L("Sort windows by"), selection: SettingsBinding.store(config, \.sort),
                          options: [PickerOption(DockSort.recentlyUsed, L("Recently Used")),
                                    PickerOption(DockSort.minimizedAndHiddenLast, L("Minimized and Hidden Last")),
                                    PickerOption(DockSort.title, L("Title"))],
                          style: .popUp, defaultValue: DockConfig().sort, anchor: ControlID("dock.advanced.sort"))
            ToggleSetting(L("Keyboard shortcuts in previews"),
                          help: L("Press ⌘W to close, ⌘M to minimize, ⌘H to hide, or ⌘Q to quit what’s under the pointer. Esc dismisses the preview."),
                          isOn: SettingsBinding.store(config, \.keys), anchor: ControlID("dock.advanced.keys"))
                .disabled(keysKilled)
            if keysKilled {
                DefaultsLockRow(key: KillSwitches.key(prefix: "Dock", id: DockFeature.keys.rawValue))
            }
            ToggleSetting(L("Apps with no open windows"),
                          help: L("Pointing at the app shows a small card instead of nothing."),
                          isOn: SettingsBinding.store(config, \.windowlessApps),
                          anchor: ControlID("dock.advanced.windowlessApps"))
            PickerSetting(L("When another app shows Dock previews"),
                          selection: SettingsBinding.store(config, \.runAlongsideOtherTools),
                          options: [PickerOption(false, L("Pause Dock Previews")),
                                    PickerOption(true, L("Run Both Anyway"))],
                          style: .popUp, defaultValue: DockConfig().runAlongsideOtherTools,
                          anchor: ControlID("dock.advanced.otherTools"))
            if config.value.runAlongsideOtherTools {
                footnote(L("Both apps show a preview when you point at the Dock, and the previews may cover each other."))
            }
            ToggleSetting(L("Show previews while VoiceOver is on"),
                          help: L("Previews appear as VoiceOver moves through the Dock."),
                          isOn: SettingsBinding.store(config, \.showWithVoiceOver),
                          anchor: ControlID("dock.advanced.voiceOver"))
        }
    }

    /// The switcher sheet's two rows, on the same store, so a change on one sheet shows on the other (§4.10).
    @ViewBuilder private var privacySection: some View {
        Section {
            ToggleSetting(L("Protect private windows"),
                          help: L("Password managers and private browsing windows show their app icon instead."),
                          isOn: SwitcherBinding.config(settings, \.protectPrivateWindows),
                          anchor: ControlID("dock.advanced.protectPrivate"))
        } header: {
            Text(L("Privacy"))
        } footer: {
            Text(L("Thumbnails stay in memory and are never saved. They’re cleared after 30 minutes, and when your Mac locks or sleeps. These settings also apply to the Window Switcher."))
                .foregroundStyle(.secondary)
        }
        if settings.config.protectPrivateWindows {
            AppListEditor(L("Never show thumbnails for"),
                          help: L("These apps show their icon and name instead of a picture or window title, in the Window Switcher and Dock Previews."),
                          bundleIDs: SwitcherBinding.config(settings, \.privateBundleIDs),
                          anchor: ControlID("dock.advanced.privateApps"))
        }
    }

    /// `Dock.disable.*` and `Windows.disable.*` only (G2-6): row 1 shows `Modules.disable.dockPreviews`, and the sheet
    /// can't open then. Read without logging; the Windows keys live in the app's domain.
    @ViewBuilder private var diagnosticsSection: some View {
        let defaults = UserDefaults.standard
        let dock = DockPreviewsModule.readKillSwitches(defaults).sorted { $0.rawValue < $1.rawValue }
        let windows = KillSwitches.read(defaults.persistentDomain(forName: ConfigStore<DockConfig>.persistentDomainName),
                                        prefix: "Windows", as: WindowFeature.self).sorted { $0.rawValue < $1.rawValue }
        let keys = dock.map { KillSwitches.key(prefix: "Dock", id: $0.rawValue) } + windows.map(\.killSwitchKey)
        if !keys.isEmpty {
            Section {
                ForEach(keys, id: \.self) { key in
                    DefaultsLockRow(key: key)
                        .modifier(SettingsAnchor(ControlID("dock.advanced.killSwitch")))
                }
            } header: {
                Text(L("Diagnostics"))
            }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 20)
    }

    /// The sheet's rows only; never the shared privacy settings (§4.10, §4.18).
    private var restore: RestoreDefaults {
        let config = self.config
        return RestoreDefaults(title: L("Restore Defaults…"),
                               question: L("Restore Dock Previews’ Advanced settings to their defaults?"),
                               message: L("Advanced settings go back to their defaults. Protect private windows and its app list stay as they are, because the Window Switcher uses them too."),
                               button: L("Restore Defaults"), destructive: false) {
            config.value = config.value.restoringAdvancedDefaults()
        }
    }
}
