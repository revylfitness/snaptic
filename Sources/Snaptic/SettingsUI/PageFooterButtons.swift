import AppKit
import SwiftUI
import SnapticKit

/// "Restore <scope> Defaults…" ("Restore Awake Defaults…"); the confirmation names the scope too ("Restore Awake
/// settings to their defaults?"). Reset All Settings… uses the custom-title init.
struct RestoreDefaults {
    let scopeName: String
    let destructive: Bool
    let action: @MainActor () -> Void
    private let customTitle: String?
    private let customQuestion: String?
    private let customMessage: String?
    private let customButton: String?

    init(scopeName: String, destructive: Bool, action: @escaping @MainActor () -> Void) {
        self.scopeName = scopeName
        self.destructive = destructive
        self.action = action
        customTitle = nil
        customQuestion = nil
        customMessage = nil
        customButton = nil
    }

    /// Own wording, e.g. "Reset All Settings…" / "Reset all Snaptic settings?" / [Reset].
    init(title: String, question: String, message: String, button: String, destructive: Bool,
         action: @escaping @MainActor () -> Void) {
        scopeName = ""
        self.destructive = destructive
        self.action = action
        customTitle = title
        customQuestion = question
        customMessage = message
        customButton = button
    }

    var title: String { customTitle ?? L("Restore \(scopeName) Defaults…") }
    var question: String { customQuestion ?? L("Restore \(scopeName) settings to their defaults?") }
    var message: String { customMessage ?? L("Your other Snaptic settings stay as they are.") }
    var button: String { customButton ?? L("Restore Defaults") }
}

/// The confirmation alert of a `RestoreDefaults` button.
struct RestoreDefaultsConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let restore: RestoreDefaults?

    func body(content: Content) -> some View {
        content.alert(restore?.question ?? "", isPresented: $isPresented) {
            if let restore {
                Button(restore.button, role: restore.destructive ? .destructive : nil) { restore.action() }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(restore?.message ?? "")
        }
    }
}

/// Where (?) leads: Snaptic's help (the project README, opened in the browser). Routes are checked so a malformed
/// id never reaches the URL.
enum SettingsHelp {
    static let base = "https://github.com/revylfitness/snaptic#readme"

    @MainActor static func open(_ route: SettingsRoute) {
        guard SettingsLocation.isValidID(route.id), let url = URL(string: base) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Page footer: trailing `Advanced…` and (?) only (design M5); `restoreDefaults` leading, only on pages without an
/// Advanced sheet. Lives in a section of its own with only a footer, so it sits below the last group.
struct PageFooterButtons: View {
    let advanced: (() -> Void)?
    let help: SettingsRoute?
    let restoreDefaults: RestoreDefaults?
    /// R5-13.
    let advancedControl: ControlID?
    let restoreControl: ControlID?
    @State private var confirming = false

    init(advanced: (() -> Void)?, help: SettingsRoute?, restoreDefaults: RestoreDefaults? = nil,
         advancedControl: ControlID? = nil, restoreControl: ControlID? = nil) {
        self.advanced = advanced
        self.help = help
        self.restoreDefaults = restoreDefaults
        self.advancedControl = advancedControl
        self.restoreControl = restoreControl
    }

    var body: some View {
        Section {
        } footer: {
            HStack(spacing: 8) {
                if let restoreDefaults {
                    Button(restoreDefaults.title) { confirming = true }
                        .modifier(OptionalSettingsAnchor(restoreControl))
                }
                Spacer(minLength: 8)
                if let advanced {
                    Button(L("Advanced…")) { advanced() }
                        .modifier(OptionalSettingsAnchor(advancedControl))
                }
                if let help {
                    HelpLink { SettingsHelp.open(help) }
                        .help(L("Snaptic Help"))
                }
            }
            .padding(.top, 4)
            .modifier(RestoreDefaultsConfirmation(isPresented: $confirming, restore: restoreDefaults))
        }
    }
}
