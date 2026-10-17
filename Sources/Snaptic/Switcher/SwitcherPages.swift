import AppKit
import SwiftUI
import SnapticKit

/// The Window Switcher's Settings pages (PLAN §3.7): Features, Shortcuts, Behavior,
/// Thumbnails, App lists, Privacy. The Features page is the only place for on/off
/// switches (PLAN §2.2).
enum SwitcherPages {
    @MainActor static func pages(module: WindowSwitcherModule) -> [SettingsPage] {
        let settings = module.settings
        return [
            SettingsPage(id: "switcher.features", title: L("Switcher Features"), symbol: "switch.2") {
                AnyView(SwitcherFeaturesPage(settings: settings, module: module))
            },
            SettingsPage(id: "switcher.shortcuts", title: L("Shortcuts"), symbol: "keyboard") {
                AnyView(SwitcherShortcutsPage(settings: settings, module: module))
            },
            SettingsPage(id: "switcher.behavior", title: L("Behavior"), symbol: "hand.tap") {
                AnyView(Form { SwitcherBehaviorSection(settings: settings) }.formStyle(.grouped))
            },
            SettingsPage(id: "switcher.thumbnails", title: L("Thumbnails"), symbol: "photo.on.rectangle") {
                AnyView(Form { SwitcherThumbnailsSection(settings: settings) }.formStyle(.grouped))
            },
            SettingsPage(id: "switcher.apps", title: L("App Lists"), symbol: "list.bullet.rectangle") {
                AnyView(Form { SwitcherAppListsSections(settings: settings) }.formStyle(.grouped))
            },
            SettingsPage(id: "switcher.privacy", title: L("Privacy"), symbol: "hand.raised") {
                AnyView(Form { SwitcherPrivacySections(settings: settings) }.formStyle(.grouped))
            },
        ]
    }
}

private struct SwitcherFeaturesPage: View {
    @ObservedObject var settings: AppSettings
    let module: WindowSwitcherModule

    private struct FeatureGroup: Identifiable {
        let title: String
        let features: [SwitcherFeature]
        var id: String { title }
    }

    private let groups: [FeatureGroup] = [
        FeatureGroup(title: L("What the switcher shows"), features: [.thumbnails, .preview, .otherSpaces, .windowlessApps]),
        FeatureGroup(title: L("Keys while it's open"),
                     features: [.search, .actionClose, .actionMinimize, .actionFullscreen, .actionHide, .actionQuit]),
        FeatureGroup(title: L("Mouse"), features: [.hoverButtons, .hoverSelect]),
        FeatureGroup(title: L("Shortcuts"), features: [.commandTabTakeover, .passthrough]),
    ]

    var body: some View {
        Form {
            if !module.tapIsRunning && module.isRunning {
                Section {
                    PermissionRow(
                        title: PermissionFlow.paneName(.accessibility),
                        detail: L("Required. Lets Snaptic see your shortcut and switch windows."),
                        granted: false,
                        open: { module.presentPermission(.accessibility) }
                    )
                }
            }
            if settings.config.needsScreenCapture && !Permissions.screenRecording {
                Section {
                    PermissionRow(
                        title: PermissionFlow.paneName(.screenRecording),
                        detail: L("For thumbnails, previews and titles of windows on other Spaces. Turn off Window thumbnails to never need it."),
                        granted: false,
                        open: { module.presentPermission(.screenRecording) }
                    )
                }
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.features, id: \.self) { feature in
                        row(feature)
                    }
                }
            }
            Section {
                Text(L("VoiceOver announcements and the secure-input safety check are always on."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(_ feature: SwitcherFeature) -> some View {
        let needsThumbnails = feature == .preview && !settings.config.isOn(.thumbnails)
        VStack(alignment: .leading, spacing: 2) {
            Toggle(SwitcherFeaturesConfig.title(feature), isOn: binding(feature))
                .disabled(needsThumbnails)
            Text(needsThumbnails ? L("Needs Window thumbnails.") : SwitcherFeaturesConfig.detail(feature))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Aliased features write their existing setting (same key as before); the rest
    /// write `disabledFeatures`.
    private func binding(_ feature: SwitcherFeature) -> Binding<Bool> {
        Binding(
            get: {
                let c = settings.config
                guard c.disabledFeatures.isEnabled(feature) else { return false }
                switch feature {
                case .preview: return c.previewSelected
                case .otherSpaces: return c.showOtherSpaces
                case .hoverSelect: return c.selectOnHover
                default: return true
                }
            },
            set: { on in
                var c = settings.config
                switch feature {
                case .preview: c.previewSelected = on
                case .otherSpaces: c.showOtherSpaces = on
                case .hoverSelect: c.selectOnHover = on
                default: break
                }
                // Aliased features live in their own setting; clear any stray "disabled"
                // entry so the toggle always means what it shows.
                c.disabledFeatures.set(feature, enabled: SwitcherFeaturesConfig.aliased.contains(feature) || on)
                settings.config = c
            }
        )
    }
}

private struct SwitcherShortcutsPage: View {
    @ObservedObject var settings: AppSettings
    let module: WindowSwitcherModule

    var body: some View {
        Form {
            SwitcherShortcutsSection(settings: settings)
            Section {
                LabeledContent {
                    ShortcutRecorder(combo: $settings.config.gatherShortcut)
                } label: {
                    Text(L("Gather windows on the display under the pointer"))
                }
                if let problem = module.gatherShortcutProblem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(L("Gather windows"))
            } footer: {
                Text(L("Moves every window onto that display. From a shortcut, Snaptic asks first. Needs Accessibility."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
