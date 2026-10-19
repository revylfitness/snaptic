import SwiftUI
import SnapticKit

/// A module's on/off row, as a card: icon tile, name, what it does, and a switch (General's module chooser while
/// every module is off, and onboarding's Choose modules step). A module turned off by `Modules.disable.<id>` shows
/// its switch off and disabled, with `DefaultsLock.text` and an (i) naming the command that turns it back on.
struct ModuleSwitchRow: View {
    let id: ModuleID
    let title: String
    let isOn: Binding<Bool>
    let blocked: Bool
    let anchor: ControlID?

    init(_ id: ModuleID, title: String, isOn: Binding<Bool>, blocked: Bool, anchor: ControlID? = nil) {
        self.id = id
        self.title = title
        self.isOn = isOn
        self.blocked = blocked
        self.anchor = anchor
    }

    /// One line on what each module does (user words, PLAN 0.3 §4.7, design m11).
    static func summary(_ id: ModuleID) -> String {
        switch id {
        case .windowSwitcher: return L("Switch between windows, not just apps, with ⌥⇥.")
        case .displays: return L("Brightness, resolution, and arrangement for every display.")
        case .awake: return L("Keep your Mac awake for a while. Its icon appears while your Mac is being kept awake.")
        }
    }

    var body: some View {
        let style = SettingsShell.sidebarStyle[id.rawValue] ?? (symbol: "app", tint: SettingsTint.gray)
        HStack(alignment: .center, spacing: 12) {
            SettingsIcon(style.symbol, tint: style.tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(blocked ? DefaultsLock.text : Self.summary(id))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if blocked {
                InfoButton(L("How to turn it back on"),
                           message: DefaultsLock.details(domain: ConfigStore<ModulesConfig>.persistentDomainName,
                                                         key: ModuleHost.disableKey(id)))
            }
            Toggle(title, isOn: blocked ? .constant(false) : isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(blocked)
                .accessibilityLabel(L("Use \(title)"))
                .accessibilityHint(blocked ? DefaultsLock.text : Self.summary(id))
        }
        .padding(.vertical, 2)
        .modifier(OptionalSettingsAnchor(anchor))
    }
}
