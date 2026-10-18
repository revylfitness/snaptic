import AppKit
import SwiftUI
import SnapticKit

/// The Window Switcher's place in Settings (H; PLAN 0.3 §4.3): one root page, its Advanced sheet and the More
/// Shortcuts sheet. The 0.2 sub-pages (Features, Shortcuts, Behavior, Thumbnails, App Lists, Privacy) are merged
/// into them.
enum SwitcherPages {
    /// The sidebar root (`WindowSwitcherModule.settingsRoot()`).
    @MainActor static func root(module: WindowSwitcherModule) -> SettingsRoot {
        SettingsRoot(id: SettingsRootID.windowSwitcher, title: module.title, symbol: "rectangle.on.rectangle",
                     tint: .indigo) { [weak module] in
            guard let module, let host = SettingsShell.shared.host else { return AnyView(UnavailablePage()) }
            return AnyView(SwitcherPage(host: host, module: module))
        }
    }

    /// What the page shows while the module is off.
    static let highlights: [FeatureHighlight] = [
        FeatureHighlight(id: "windows", symbol: "rectangle.on.rectangle", title: L("Every window, not just apps"),
                         text: L("Press ⌥⇥ to see all of your windows, then pick one.")),
        FeatureHighlight(id: "search", symbol: "magnifyingglass", title: L("Find a window fast"),
                         text: L("Type to search, or close and minimize windows from the keyboard.")),
        FeatureHighlight(id: "thumbnails", symbol: "photo.on.rectangle", title: L("See before you switch"),
                         text: L("Thumbnails show what's in each window.")),
    ]
}

/// Settings › Window Switcher (§4.3; 8 settings + More Shortcuts…): header switch "Use Window Switcher"; the
/// permission status rows; Shortcut (primary shortcut, More Shortcuts…, release to switch, Show, Style with its
/// thumbnail options); Windows (minimized and hidden, Spaces). Footer: Advanced… (?).
struct SwitcherPage: View, ControlDeclaring {
    typealias Controls = SwitcherPageControls
    @ObservedObject var host: ModuleHost
    let module: WindowSwitcherModule

    var body: some View {
        SwitcherPageContent(host: host, modules: host.modulesStore, permissions: host.permissions,
                            settings: module.settings, module: module, shell: SettingsShell.shared)
    }
}

/// The two sheets this page opens (one `.sheet(item:)`, so they never fight).
private enum SwitcherSheet: String, Identifiable {
    case advanced = "switcher.advanced"
    case shortcuts = "switcher.shortcuts"
    var id: String { rawValue }
}

private struct SwitcherPageContent: View {
    @ObservedObject var host: ModuleHost
    @ObservedObject var modules: ConfigStore<ModulesConfig>
    @ObservedObject var permissions: PermissionFlow
    @ObservedObject var settings: AppSettings
    let module: WindowSwitcherModule
    @ObservedObject var shell: SettingsShell

    private var blocked: Bool { host.disabledByDefaults.contains(.windowSwitcher) }
    private var enabled: Bool { !blocked && modules.value.isEnabled(.windowSwitcher) }
    private var thumbnailsOn: Bool { settings.config.isOn(.thumbnails) }

    var body: some View {
        SettingsPageScaffold(route: SettingsRoute(SettingsRootID.windowSwitcher)) {
            SettingsPageHeader(L("Window Switcher"), summary: L("Switch between windows, not just apps, with a keyboard shortcut."),
                               symbol: "rectangle.on.rectangle", tint: .indigo,
                               isOn: shell.moduleEnabled(.windowSwitcher), switchLabel: L("Use Window Switcher"),
                               control: ControlID("switcher.page.header"))
                .disabled(blocked)
            if blocked {
                Section {
                    DefaultsLockRow(module: .windowSwitcher)
                }
                FeatureHighlights(SwitcherPages.highlights)
            } else if !enabled {
                FeatureHighlights(SwitcherPages.highlights)
            } else {
                statusRows
                shortcutSection
                windowsSection
                PageFooterButtons(advanced: { shell.openSheet = SwitcherSheet.advanced.rawValue },
                                  help: SettingsRoute(SettingsRootID.windowSwitcher),
                                  advancedControl: ControlID("switcher.page.advanced"))
            }
        }
        .sheet(item: sheetBinding) { sheet in
            switch sheet {
            case .advanced: SwitcherAdvancedSheet(settings: settings)
            case .shortcuts: SwitcherShortcutsSheet(settings: settings, module: module)
            }
        }
    }

    private var sheetBinding: Binding<SwitcherSheet?> {
        Binding(get: { shell.openSheet.flatMap(SwitcherSheet.init(rawValue:)) },
                set: { newValue in
                    if let newValue {
                        shell.openSheet = newValue.rawValue
                    } else if let open = shell.openSheet, SwitcherSheet(rawValue: open) != nil {
                        shell.openSheet = nil
                    }
                })
    }

    // MARK: Sections

    @ViewBuilder private var statusRows: some View {
        let needsAccessibility = host.isRunning(.windowSwitcher) && !permissions.granted.contains(.accessibility)
        let needsScreenRecording = settings.config.needsScreenCapture && !permissions.granted.contains(.screenRecording)
        if needsAccessibility || needsScreenRecording {
            Section {
                if needsAccessibility {
                    StatusRow(L("Window Switcher needs \(PermissionFlow.paneName(.accessibility)) to see its shortcut."),
                              style: .warning, actions: [
                                  StatusAction(title: L("Open Privacy Settings…"),
                                               control: ControlID("switcher.page.accessibility")) {
                                      module.presentPermission(.accessibility)
                                  },
                              ])
                }
                if needsScreenRecording {
                    StatusRow(L("Window thumbnails need Screen Recording."), style: .warning, actions: [
                        StatusAction(title: L("Open Privacy Settings…"), control: ControlID("switcher.page.screenRecording")) {
                            module.presentPermission(.screenRecording)
                        },
                    ])
                }
            }
        }
    }

    private var shortcutSection: some View {
        let style = SwitcherBinding.primary(settings, \.style)
        let showsThumbnailOptions = SwitcherPageRules.showsThumbnailOptions(style: style.wrappedValue.rawValue,
                                                                            thumbnailsOn: thumbnailsOn)
        return Section {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent {
                    ShortcutKeysPicker(settings: settings, id: nil)
                } label: {
                    Text(L("Shortcut"))
                    Text(L("Hold the modifier and press the key to open the switcher."))
                }
                if let note = SwitcherBinding.note(settings, id: nil) {
                    SettingsRowNote(note)
                }
            }
            .modifier(SettingsAnchor(ControlID("switcher.page.shortcut")))
            ButtonRow(L("More Shortcuts…"), control: ControlID("switcher.page.moreShortcuts")) {
                shell.openSheet = SwitcherSheet.shortcuts.rawValue
            }
            ToggleSetting(L("Switch when you release the keys"),
                          help: L("Letting go of the modifier key switches to the selected window."),
                          isOn: SwitcherBinding.config(settings, \.releaseToSwitch),
                          anchor: ControlID("switcher.page.releaseToSwitch"))
            PickerSetting(L("Show"), help: L("Which windows the switcher lists. This Display is the display it opens on."),
                          selection: SwitcherBinding.primary(settings, \.scope),
                          options: SwitcherBinding.scopeOptions, style: .popUp, defaultValue: .allWindows,
                          anchor: ControlID("switcher.page.scope"))
            PickerSetting(L("Style"), help: L("How the switcher shows each window."),
                          selection: SwitcherBinding.style(settings, id: nil),
                          options: SwitcherBinding.styleOptions(thumbnailsOn: thumbnailsOn), style: .segmented,
                          defaultValue: thumbnailsOn ? .thumbnails : .icons, anchor: ControlID("switcher.page.style"))
            if showsThumbnailOptions {
                ToggleSetting(L("Preview the selected window"),
                              help: L("Shows the selected window full size behind the switcher."),
                              isOn: SwitcherBinding.preview(settings), subordinate: true,
                              anchor: ControlID("switcher.page.preview"))
                ToggleSetting(L("Size thumbnails automatically"), help: L("Fits the thumbnails to the number of windows."),
                              isOn: SwitcherBinding.config(settings, \.autoSize), subordinate: true,
                              anchor: ControlID("switcher.page.autoSize"))
                if !settings.config.autoSize {
                    SliderSetting(L("Thumbnail size"), value: SwitcherBinding.config(settings, \.thumbnailSize),
                                  in: 100...300, step: 10, defaultValue: Config().thumbnailSize, format: .points,
                                  anchor: ControlID("switcher.page.thumbnailSize"), subordinate: true)
                }
            }
        } footer: {
            if !thumbnailsOn {
                Text(L("To show thumbnails, turn on Window thumbnails in Advanced."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var windowsSection: some View {
        Section {
            ToggleSetting(L("Include minimized and hidden windows"),
                          help: L("Lists windows that are minimized or belong to hidden apps."),
                          isOn: SwitcherBinding.primary(settings, \.includeMinimized),
                          anchor: ControlID("switcher.page.includeMinimized"))
            PickerSetting(L("Windows from"), help: L("Which Spaces the switcher lists windows from."),
                          selection: SwitcherBinding.spaces(settings, id: nil),
                          options: SwitcherBinding.spacesOptions, style: .popUp,
                          defaultValue: .all, anchor: ControlID("switcher.page.spaces"))
        } header: {
            Text(L("Windows"))
        }
    }
}

// MARK: - Shared by the page and its sheets

/// The modifier and key pop-ups of one switcher shortcut (`id` nil = the primary, first shortcut). ⌘ allows only
/// Tab, the key above Tab and Space, so a shortcut never takes ⌘C or ⌘Q; switching to ⌘ moves an unsafe key to Tab.
struct ShortcutKeysPicker: View {
    @ObservedObject var settings: AppSettings
    let id: UUID?

    var body: some View {
        let modifier = SwitcherBinding.primaryOr(settings, id: id, \.modifier)
        HStack(spacing: 6) {
            Picker(L("Modifier"), selection: SwitcherBinding.modifier(settings, id: id)) {
                ForEach(ModifierKey.allCases) { key in
                    Text(SwitcherBinding.modifierTitle(key)).tag(key)
                }
            }
            .labelsHidden()
            .fixedSize()
            Picker(L("Key"), selection: SwitcherBinding.shortcut(settings, id: id, \.keyCode)) {
                ForEach(Keys.allowedChoices(for: modifier)) { choice in
                    Text(choice.label).tag(choice.code)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// Bindings into the switcher's `Config` (AppSettings saves through its 250 ms debounce). Writes happen only when a
/// value changes; feature switches keep the 0.2 aliasing (preview ↔ previewSelected, other Spaces ↔
/// showOtherSpaces, hover select ↔ selectOnHover) so a switch always means what it shows.
@MainActor enum SwitcherBinding {
    static func config<V: Equatable>(_ settings: AppSettings, _ path: WritableKeyPath<Config, V>) -> Binding<V> {
        Binding(get: { settings.config[keyPath: path] },
                set: { value in
                    if settings.config[keyPath: path] != value { settings.config[keyPath: path] = value }
                })
    }

    /// A field of the primary shortcut.
    static func primary<V: Equatable>(_ settings: AppSettings, _ path: WritableKeyPath<Shortcut, V>) -> Binding<V> {
        Self.shortcut(settings, id: nil, path)
    }

    /// A field of the shortcut with `id` (nil = the primary one). A shortcut that went away reads as a default one
    /// and ignores writes.
    static func shortcut<V: Equatable>(_ settings: AppSettings, id: UUID?, _ path: WritableKeyPath<Shortcut, V>) -> Binding<V> {
        Binding(get: { Self.primaryOr(settings, id: id, path) },
                set: { value in
                    guard let index = Self.index(settings, id: id), settings.config.shortcuts[index][keyPath: path] != value
                    else { return }
                    settings.config.shortcuts[index][keyPath: path] = value
                })
    }

    static func primaryOr<V>(_ settings: AppSettings, id: UUID?, _ path: KeyPath<Shortcut, V>) -> V {
        guard let index = Self.index(settings, id: id) else { return Shortcut()[keyPath: path] }
        return settings.config.shortcuts[index][keyPath: path]
    }

    static func index(_ settings: AppSettings, id: UUID?) -> Int? {
        guard let id else { return settings.config.shortcuts.isEmpty ? nil : 0 }
        return settings.config.shortcuts.firstIndex { $0.id == id }
    }

    /// Changing the modifier keeps the key when it is allowed with it, and moves it to Tab when it isn't.
    static func modifier(_ settings: AppSettings, id: UUID?) -> Binding<ModifierKey> {
        Binding(get: { Self.primaryOr(settings, id: id, \.modifier) },
                set: { value in
                    guard let index = Self.index(settings, id: id) else { return }
                    var shortcut = settings.config.shortcuts[index]
                    guard shortcut.modifier != value else { return }
                    shortcut.modifier = value
                    if !Keys.isAllowed(shortcut) { shortcut.keyCode = KeyCode.tab }
                    settings.config.shortcuts[index] = shortcut
                })
    }

    /// Style as the switcher shows it: Thumbnails reads as Icons while window thumbnails are off.
    static func style(_ settings: AppSettings, id: UUID?) -> Binding<SwitcherStyle> {
        Binding(get: {
            let raw = Self.primaryOr(settings, id: id, \.style).rawValue
            let shown = SwitcherPageRules.effectiveStyle(raw, thumbnailsOn: settings.config.isOn(.thumbnails))
            return SwitcherStyle(rawValue: shown) ?? .icons
        }, set: { value in
            let enabled = SwitcherPageRules.styleChoiceEnabled(value.rawValue, thumbnailsOn: settings.config.isOn(.thumbnails))
            guard enabled else { return }
            Self.shortcut(settings, id: id, \.style).wrappedValue = value
        })
    }

    /// Spaces as the switcher uses them: the current Space only while the other-Spaces feature is off. Choosing All
    /// Spaces or Other Spaces turns that feature on (ux M3: this pop-up is the only control for it); every other
    /// shortcut then keeps the Current Space it showed (`SwitcherPageRules.spacesChoice`, round 2 ui F2).
    static func spaces(_ settings: AppSettings, id: UUID?) -> Binding<SpacesFilter> {
        Binding(get: {
            let raw = Self.primaryOr(settings, id: id, \.spaces).rawValue
            let shown = SwitcherPageRules.effectiveSpace(raw, otherSpacesOn: settings.config.isOn(.otherSpaces))
            return SpacesFilter(rawValue: shown) ?? .current
        }, set: { value in
            guard let index = Self.index(settings, id: id) else { return }
            var c = settings.config
            let choice = SwitcherPageRules.spacesChoice(c.shortcuts.map(\.spaces.rawValue), changed: index,
                                                        to: value.rawValue, otherSpacesOn: c.isOn(.otherSpaces))
            if choice.turnsOn {
                c.showOtherSpaces = true
                c.disabledFeatures.set(.otherSpaces, enabled: true)
            }
            for (i, raw) in choice.spaces.enumerated() where i != index {
                if let spaces = SpacesFilter(rawValue: raw) { c.shortcuts[i].spaces = spaces }
            }
            c.shortcuts[index].spaces = value
            if c != settings.config { settings.config = c }
        })
    }

    /// "Include apps with no open windows" of one shortcut: reads on only while the windowless feature is on too, and
    /// turning it on turns the feature on (ux M3: this switch is the only control for it); every other shortcut then
    /// keeps reading as it did (`SwitcherPageRules.windowlessChoice`, round 2 ui F2).
    static func windowless(_ settings: AppSettings, id: UUID?) -> Binding<Bool> {
        Binding(get: {
            SwitcherPageRules.effectiveWindowless(Self.primaryOr(settings, id: id, \.includeWindowlessApps),
                                                  featureOn: settings.config.isOn(.windowlessApps))
        }, set: { on in
            guard let index = Self.index(settings, id: id) else { return }
            var c = settings.config
            let choice = SwitcherPageRules.windowlessChoice(c.shortcuts.map(\.includeWindowlessApps), changed: index,
                                                            to: on, featureOn: c.isOn(.windowlessApps))
            if choice.turnsOn { c.disabledFeatures.set(.windowlessApps, enabled: true) }
            for (i, value) in choice.values.enumerated() { c.shortcuts[i].includeWindowlessApps = value }
            if c != settings.config { settings.config = c }
        })
    }

    /// "Preview the selected window": the 0.2 setting, with any stray "turned off" feature entry cleared.
    static func preview(_ settings: AppSettings) -> Binding<Bool> {
        Binding(get: { settings.config.previewSelected && settings.config.disabledFeatures.isEnabled(.preview) },
                set: { on in
                    var c = settings.config
                    c.previewSelected = on
                    c.disabledFeatures.set(.preview, enabled: true)
                    if c != settings.config { settings.config = c }
                })
    }

    /// A feature switch (Advanced). Aliased features write their own setting and clear any stray entry.
    static func feature(_ settings: AppSettings, _ feature: SwitcherFeature) -> Binding<Bool> {
        Binding(get: {
            let c = settings.config
            guard c.disabledFeatures.isEnabled(feature) else { return false }
            switch feature {
            case .preview: return c.previewSelected
            case .otherSpaces: return c.showOtherSpaces
            case .hoverSelect: return c.selectOnHover
            default: return true
            }
        }, set: { on in
            var c = settings.config
            switch feature {
            case .preview: c.previewSelected = on
            case .otherSpaces: c.showOtherSpaces = on
            case .hoverSelect: c.selectOnHover = on
            default: break
            }
            c.disabledFeatures.set(feature, enabled: SwitcherFeaturesConfig.aliased.contains(feature) || on)
            if c != settings.config { settings.config = c }
        })
    }

    /// Why a shortcut doesn't act, if it doesn't: another shortcut before it uses the same keys, or it uses ⌘
    /// while ⌘⇥ stays with macOS.
    static func note(_ settings: AppSettings, id: UUID?) -> String? {
        guard let index = Self.index(settings, id: id) else { return nil }
        let shortcuts = settings.config.shortcuts
        let shortcut = shortcuts[index]
        if shortcuts[..<index].contains(where: { $0.sameKeys(as: shortcut) }) {
            return L("Another shortcut uses the same keys, so this one does nothing.")
        }
        if shortcut.modifier == .command && !settings.config.isOn(.commandTabTakeover) {
            return L("⌘ shortcuts work only while “⌘⇥ replaces the app switcher” is on in Advanced.")
        }
        return nil
    }

    static func modifierTitle(_ key: ModifierKey) -> String {
        switch key {
        case .option: return L("⌥ Option")
        case .command: return L("⌘ Command")
        case .control: return L("⌃ Control")
        }
    }

    static let scopeOptions: [PickerOption<SwitcherScope>] = [
        PickerOption(.allWindows, L("All Windows")),
        PickerOption(.activeApp, L("Active App")),
        PickerOption(.currentScreen, L("This Display")),
    ]

    /// Thumbnails isn't offered while window thumbnails are off.
    static func styleOptions(thumbnailsOn: Bool) -> [PickerOption<SwitcherStyle>] {
        (thumbnailsOn ? [PickerOption(.thumbnails, L("Thumbnails"))] : [])
            + [PickerOption(.icons, L("Icons")), PickerOption(.titles, L("List"))]
    }

    static let spacesOptions: [PickerOption<SpacesFilter>] = [
        PickerOption(.all, L("All Spaces")),
        PickerOption(.current, L("Current Space")),
        PickerOption(.others, L("Other Spaces")),
    ]
}
