import SwiftUI
import SnapticKit

/// Hidden Icons › Advanced (lead; PLAN 0.4 §4.9, §4.5, §4.7, §4.10, §4.2.5, A7, R3-90): Show icons on hover, New
/// apps’ icons and Keep camera and microphone dots visible (macOS 27), When another menu bar app hides icons, Use the full menu bar while icons are shown, Reset Arrow
/// Position… (an alert, since this sheet never presents another), and Diagnostics with the active kill switches as
/// read-only `DefaultsLockRow`s. Footer: Restore Hidden Icons Defaults… resets this sheet's rows only.
struct IconsAdvancedSheet: View, ControlDeclaring {
    typealias Controls = IconsAdvancedSheetControls

    let module: IconsModule
    @ObservedObject private var config: ConfigStore<IconsConfig>
    @State private var confirmReset = false

    init(module: IconsModule) {
        self.module = module
        _config = ObservedObject(wrappedValue: module.config)
    }

    var body: some View {
        AdvancedSheet(L("Hidden Icons Advanced Settings"), restoreDefaults: restore,
                      restoreControl: ControlID("icons.advanced.restore")) {
            behaviourSection
            Section {
                ButtonRow(L("Reset Arrow Position…"),
                          help: L("Puts the arrow and dividers back next to the Snaptic icon if you can’t find them."),
                          control: ControlID("icons.advanced.resetArrow")) {
                    confirmReset = true
                }
            }
            diagnosticsSection
        }
        .alert(IconsPageRules.resetArrowTitle, isPresented: $confirmReset) {
            Button(L("Reset Position")) { module.resetArrowPosition() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(IconsPageRules.resetArrowMessage)
        }
    }

    // MARK: Rows

    @ViewBuilder private var behaviourSection: some View {
        let native = module.engineKind == .native
        Section {
            ToggleSetting(L("Show icons on hover"), help: IconsPageRules.hoverHelp,
                          isOn: SettingsBinding.store(config, \.hover), anchor: ControlID("icons.advanced.hover"))
            if native {
                PickerSetting(L("New apps’ icons"), help: IconsPageRules.newAppsHelp,
                              selection: SettingsBinding.store(config, \.newApps),
                              options: [PickerOption(IconsNewAppPolicy.show, L("Show")),
                                        PickerOption(IconsNewAppPolicy.hide, L("Hide"))],
                              style: .popUp, defaultValue: IconsConfig().newApps,
                              anchor: ControlID("icons.advanced.newApps"))
                    .disabled(module.accessState.needsPermission)
                ToggleSetting(L("Keep camera and microphone dots visible"), help: IconsPageRules.captureHelp,
                              isOn: SettingsBinding.store(config, \.showDuringCapture),
                              anchor: ControlID("icons.advanced.capture"))
                if !config.value.showDuringCapture {
                    footnote(IconsPageRules.captureOffFootnote)
                }
            }
            PickerSetting(L("When another menu bar app hides icons"),
                          selection: SettingsBinding.store(config, \.otherHiders),
                          options: [PickerOption(IconsOtherHiderPolicy.pause, L("Pause Hidden Icons")),
                                    PickerOption(IconsOtherHiderPolicy.runBoth, L("Run Both Anyway"))],
                          style: .popUp, defaultValue: IconsConfig().otherHiders,
                          anchor: ControlID("icons.advanced.otherHiders"))
            if config.value.otherHiders == .runBoth, native {
                footnote(IconsPageRules.otherHidersFootnote)
            }
            ToggleSetting(L("Use the full menu bar while icons are shown"), help: IconsPageRules.fullBarHelp,
                          isOn: SettingsBinding.store(config, \.fullBarOnExpand),
                          anchor: ControlID("icons.advanced.fullBar"))
            if config.value.fullBarOnExpand {
                footnote(IconsPageRules.fullBarFootnote)
            }
        }
    }

    @ViewBuilder private var diagnosticsSection: some View {
        let switches = module.killSwitches.sorted { $0.rawValue < $1.rawValue }
        Section {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(module.diagnosticsLines().enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .modifier(SettingsAnchor(ControlID("icons.advanced.diagnostics")))
            ForEach(switches, id: \.self) { feature in
                DefaultsLockRow(key: KillSwitches.key(prefix: IconsFeature.prefix, id: feature.rawValue))
                    .modifier(SettingsAnchor(ControlID("icons.advanced.killSwitch")))
            }
        } header: {
            Text(L("Diagnostics"))
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 20)
    }

    private var restore: RestoreDefaults {
        let config = self.config
        return RestoreDefaults(scopeName: L("Hidden Icons"), destructive: false) {
            config.value = config.value.restoringAdvancedDefaults()
        }
    }
}
