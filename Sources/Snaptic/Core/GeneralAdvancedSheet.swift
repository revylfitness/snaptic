import AppKit
import SwiftUI
import SnapticKit

/// General › Advanced… (H; PLAN 0.3 §4.3; 4 controls): Commands can skip confirmation, exit codes ((i)), Restart
/// in Safe Mode… / Leave Safe Mode…; footer leading Reset All Settings… (destructive; the host's own alert asks).
struct GeneralAdvancedSheet: View, ControlDeclaring {
    typealias Controls = GeneralAdvancedSheetControls
    let host: ModuleHost
    @ObservedObject var modules: ConfigStore<ModulesConfig>
    @State private var confirmingSafeMode = false

    var body: some View {
        AdvancedSheet(L("General"),
                      restoreDefaults: RestoreDefaults(title: L("Reset All Settings…"), destructive: true,
                                                       confirmsItself: { [weak host] in host?.resetAllSettings() }),
                      restoreControl: ControlID("general.advanced.resetAll")) {
            Section {
                ToggleSetting(L("Commands can skip confirmation"),
                              help: L("A display change sent with --yes applies without asking first."),
                              isOn: SettingsBinding.store(modules, \.commandLine.maySkipConfirmation),
                              anchor: ControlID("general.advanced.skipConfirmation"),
                              disabledReason: modules.value.commandLine.enabled
                                  ? nil : L("Turn on Command-line control to use this."))
                LabeledContent {
                    InfoButton(L("Exit codes"), message: SettingsText.exitCodes)
                } label: {
                    Text(L("Exit codes"))
                    Text(L("What the snaptic command reports when it finishes."))
                }
                .modifier(SettingsAnchor(ControlID("general.advanced.exitCodes")))
            } header: {
                Text(L("Command line"))
            }
            Section {
                if host.safeMode.isActive {
                    StatusRow(host.safeMode.reason ?? L("Snaptic is running in Safe Mode."), style: .warning)
                    ButtonRow(L("Leave Safe Mode…"), help: L("Restarts Snaptic with all of your settings."),
                              control: ControlID("general.advanced.safeMode")) {
                        confirmingSafeMode = true
                    }
                } else {
                    ButtonRow(L("Restart in Safe Mode…"),
                              help: L("Starts Snaptic without anything that changes your displays by itself."),
                              control: ControlID("general.advanced.safeMode")) {
                        confirmingSafeMode = true
                    }
                }
            } header: {
                HStack {
                    Text(L("Safe Mode"))
                    Spacer()
                    InfoButton(L("Safe Mode"), message: Self.safeModeDetails)
                }
            } footer: {
                Text(L("Safe Mode also starts by itself after two quick unexpected quits, or when you hold Shift while opening Snaptic."))
                    .foregroundStyle(.secondary)
            }
        }
        .alert(host.safeMode.isActive ? L("Leave Safe Mode?") : L("Restart in Safe Mode?"),
               isPresented: $confirmingSafeMode) {
            Button(L("Restart")) {
                if host.safeMode.isActive {
                    host.relauncher.relaunch(reason: "leave safe mode")
                } else {
                    host.relauncher.relaunch(reason: "enter safe mode", safeMode: true)
                }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(host.safeMode.isActive ? L("Snaptic restarts with all of your settings.")
                 : L("Snaptic quits and opens again in Safe Mode. Your settings stay as they are."))
        }
    }

    private static var safeModeDetails: String {
        L("Safe Mode turns off:") + "\n" + SafeMode.skipped.map { "• " + $0 }.joined(separator: "\n") + "\n\n"
            + L("Still on:") + "\n" + SafeMode.stillRuns.map { "• " + $0 }.joined(separator: "\n")
    }
}
