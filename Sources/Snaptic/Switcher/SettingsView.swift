import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SnapticKit

struct AppChoice: Hashable {
    let bundleID: String
    let name: String
}

/// Window Switcher › Advanced… (H; PLAN 0.3 §4.3; 19 controls): window thumbnails, the switcher's behavior, keys
/// and pointer, shortcut handling, and the app lists. Other Spaces and windowless apps have no feature switch here:
/// the per-shortcut choices turn them on (review ux M3). Footer: Restore Window Switcher Defaults….
struct SwitcherAdvancedSheet: View, ControlDeclaring {
    typealias Controls = SwitcherAdvancedSheetControls
    @ObservedObject var settings: AppSettings

    private var passthroughOn: Bool { settings.config.isOn(.passthrough) }

    var body: some View {
        AdvancedSheet(L("Window Switcher Advanced Settings"),
                      restoreDefaults: RestoreDefaults(scopeName: L("Window Switcher"), destructive: false) { [settings] in
                          settings.reset()
                      },
                      restoreControl: ControlID("switcher.advanced.restoreDefaults")) {
            Section {
                ToggleSetting(L("Window thumbnails"), help: L("Live images of your windows. Needs Screen Recording."),
                              isOn: SwitcherBinding.feature(settings, .thumbnails),
                              anchor: ControlID("switcher.advanced.thumbnails"))
                PickerSetting(L("Show on"), help: L("Where the switcher appears."),
                              selection: SwitcherBinding.config(settings, \.showOnScreen),
                              options: [PickerOption(.activeWindow, L("Display with the Active Window")),
                                        PickerOption(.mouse, L("Display with the Pointer"))],
                              style: .popUp, defaultValue: Config().showOnScreen,
                              anchor: ControlID("switcher.advanced.showOn"))
                ToggleSetting(L("One entry per app"), help: L("Lists each app once, with its most recent window."),
                              isOn: SwitcherBinding.primary(settings, \.oneWindowPerApp),
                              anchor: ControlID("switcher.advanced.oneWindowPerApp"))
                ToggleSetting(L("Include apps with no open windows"), help: L("Lists running apps that have no windows."),
                              isOn: SwitcherBinding.windowless(settings, id: nil),
                              anchor: ControlID("switcher.advanced.includeWindowless"))
            } header: {
                Text(L("Switcher"))
            }
            Section {
                ToggleSetting(L("Search"), help: L("Press S or / while the switcher is open, then type a name."),
                              isOn: SwitcherBinding.feature(settings, .search), anchor: ControlID("switcher.advanced.search"))
                LabeledContent {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Self.actions, id: \.feature) { action in
                            Toggle(action.title, isOn: SwitcherBinding.feature(settings, action.feature))
                                .toggleStyle(.checkbox)
                        }
                    }
                } label: {
                    Text(L("Window actions"))
                    Text(L("Keys that act on the selected window while the switcher is open."))
                }
                .modifier(SettingsAnchor(ControlID("switcher.advanced.actions")))
                ToggleSetting(L("Window buttons on hover"),
                              help: L("Close, minimize, and full-screen buttons on the window under the pointer."),
                              isOn: SwitcherBinding.feature(settings, .hoverButtons),
                              anchor: ControlID("switcher.advanced.hoverButtons"))
                ToggleSetting(L("Select by hovering"), help: L("Moving the pointer over a window selects it."),
                              isOn: SwitcherBinding.feature(settings, .hoverSelect),
                              anchor: ControlID("switcher.advanced.selectOnHover"))
            } header: {
                Text(L("Keys and pointer"))
            }
            Section {
                ToggleSetting(L("⌘⇥ replaces the app switcher"),
                              help: L("Shortcuts that use ⌘ work, and ⌘⇥ opens the Window Switcher."),
                              isOn: SwitcherBinding.feature(settings, .commandTabTakeover),
                              anchor: ControlID("switcher.advanced.commandTab"))
                ToggleSetting(L("Pass shortcuts through to apps"),
                              help: L("In the apps listed below, Snaptic's shortcuts go to the app."),
                              isOn: SwitcherBinding.feature(settings, .passthrough),
                              anchor: ControlID("switcher.advanced.passthrough"))
                if passthroughOn {
                    ToggleSetting(L("Only while full screen"), help: L("Applies while one of these apps is full screen."),
                                  isOn: SwitcherBinding.config(settings, \.passthroughOnlyWhenFullscreen), subordinate: true,
                                  anchor: ControlID("switcher.advanced.passthroughFullScreen"))
                }
            } header: {
                Text(L("Shortcuts"))
            }
            if passthroughOn {
                AppListEditor(L("Apps that keep the shortcut"),
                              help: L("Useful for virtual machines and remote desktops."),
                              bundleIDs: SwitcherBinding.config(settings, \.passthroughBundleIDs),
                              anchor: ControlID("switcher.advanced.passthroughApps"))
            }
            AppListEditor(L("Apps hidden from the switcher"), help: L("These apps never appear in the switcher."),
                          bundleIDs: SwitcherBinding.config(settings, \.excludedBundleIDs),
                          anchor: ControlID("switcher.advanced.excludedApps"))
            Section {
                ToggleSetting(L("Protect private windows"),
                              help: L("Password managers and private browsing windows show their app icon instead."),
                              isOn: SwitcherBinding.config(settings, \.protectPrivateWindows),
                              anchor: ControlID("switcher.advanced.protectPrivate"))
            } header: {
                Text(L("Privacy"))
            } footer: {
                Text(L("Thumbnails stay in memory, are never saved, and are cleared when your Mac locks or sleeps."))
                    .foregroundStyle(.secondary)
            }
            if settings.config.protectPrivateWindows {
                AppListEditor(L("Never show thumbnails for"),
                              help: L("These apps show their icon instead of a thumbnail."),
                              bundleIDs: SwitcherBinding.config(settings, \.privateBundleIDs),
                              anchor: ControlID("switcher.advanced.privateApps"))
            }
        }
    }

    private struct Action {
        let feature: SwitcherFeature
        let title: String
    }

    private static let actions: [Action] = [
        Action(feature: .actionClose, title: L("Close (W)")),
        Action(feature: .actionMinimize, title: L("Minimize (M)")),
        Action(feature: .actionFullscreen, title: L("Full screen (F)")),
        Action(feature: .actionHide, title: L("Hide app (H)")),
        Action(feature: .actionQuit, title: L("Quit app (Q)")),
    ]
}

/// App names and pickers for app lists (AppListEditor; Awake's app sessions use AppChoice).
@MainActor
enum AppNames {
    /// The app's name as Finder shows it; for an app that isn't installed, the name of a well-known one (the
    /// default lists), else the identifier itself.
    static func name(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return knownNames[bundleID] ?? bundleID
    }

    /// Names for the entries of the switcher's default lists (some are identifier prefixes, never installed as is).
    static let knownNames: [String: String] = [
        "com.parallels": "Parallels Desktop", "com.vmware.fusion": "VMware Fusion", "com.utmapp.UTM": "UTM",
        "org.virtualbox.app.VirtualBoxVM": "VirtualBox", "com.microsoft.rdc": "Microsoft Remote Desktop",
        "com.citrix.receiver": "Citrix Workspace", "com.omnissa.horizon": "Omnissa Horizon Client",
        "com.vmware.horizon": "VMware Horizon Client", "com.apple.ScreenSharing": "Screen Sharing",
        "com.teamviewer.TeamViewer": "TeamViewer", "com.p5sys.jump.mac.viewer": "Jump Desktop",
        "com.1password.1password": "1Password", "com.agilebits.onepassword7": "1Password 7",
        "com.bitwarden.desktop": "Bitwarden", "com.apple.Passwords": "Passwords", "com.apple.keychainaccess": "Keychain Access",
        "in.sinew.Enpass-Desktop": "Enpass", "com.dashlane.dashlanephonefinal": "Dashlane", "com.lastpass.LastPass": "LastPass",
        "org.torproject.torbrowser": "Tor Browser",
        // Picture in Picture's default privacy prefixes (PIPPrivacy.defaultProtectedPrefixes).
        "com.1password": "1Password", "com.agilebits": "1Password 7", "com.bitwarden": "Bitwarden",
        "com.dashlane": "Dashlane", "com.lastpass": "LastPass", "org.keepassxc": "KeePassXC",
        "org.torproject": "Tor Browser",
    ]

    static func runningApps() -> [AppChoice] {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != own }
            .compactMap { app -> AppChoice? in
                guard let id = app.bundleIdentifier else { return nil }
                return AppChoice(bundleID: id, name: app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func chooseApp() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
