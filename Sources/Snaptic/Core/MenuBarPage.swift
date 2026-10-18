import SwiftUI
import SnapticKit

/// Settings › Menu Bar (PLAN 0.3 §4.3, N7): everything about the menu bar lives here and only here.
///
/// ```
/// Window Switcher                    [Show in Snaptic Menu ▾]
///    Icon (own icon only)            [▭] [◫] [⧉]
/// Displays                           [Show in Snaptic Menu ▾]
///    Icon (own icon only)            [▭] [◫] [☀]
/// Awake                              [Show When Active ▾]
///    Time (own icon only)            [Don't Show ▾]
///    Icon                            [cup] [eye] [bulb]
/// ⚠ status rows, only while true
/// Displays menu: Style · Scroll over a slider to adjust it · Customize Displays Menu…
/// Snaptic icon                       [◫] [◩] [◰]
///                         Restore Menu Bar Defaults…     (?)
/// ```
struct MenuBarPage: View, ControlDeclaring {
    typealias Controls = MenuBarPageControls

    var body: some View {
        if let host = SettingsShell.shared.host {
            MenuBarPageContent(host: host, modules: host.modulesStore, displays: host.displaysStore,
                               awake: host.awakeStore, awakeRuntime: host.awake.runtime)
        } else {
            UnavailablePage()
        }
    }
}

private struct MenuBarPageContent: View {
    typealias Controls = MenuBarPageControls

    @ObservedObject var host: ModuleHost
    @ObservedObject var modules: ConfigStore<ModulesConfig>
    @ObservedObject var displays: ConfigStore<DisplaysConfig>
    @ObservedObject var awake: ConfigStore<AwakeConfig>
    /// For the Keep Awake shortcut's registration (`keepAwakeRegistered`; anything else counts as unbound).
    @ObservedObject var awakeRuntime: AwakeRuntimeState
    @ObservedObject private var shell = SettingsShell.shared
    /// The display the Customize sheet opens with (Display Details' "Customize Displays Menu…" link sets
    /// `SettingsShell.selectedDisplay`, then opens the sheet; parity M6). Nil when opened from this page or search.
    @State private var customizeFocus: DisplayKey?
    /// The sheet was opened by this page's own button.
    @State private var openedHere = false

    var body: some View {
        SettingsPageScaffold(route: SettingsRoute(SettingsRootID.menuBar)) {
            SettingsPageHeader(L("Menu Bar"), summary: L("Choose where Window Switcher, Displays, and Awake appear in the menu bar."),
                               symbol: "menubar.rectangle", tint: .graphite)
            Section {
                ForEach(ModuleID.allCases, id: \.self) { id in
                    moduleRows(id)
                }
            } footer: {
                if let footer = modulesFooter { Text(footer) }
            }
            warnings
            Section {
                PickerSetting(L("Style"), help: L("Compact shows one slider per display."),
                              selection: SettingsBinding.store(displays, \.menu.style),
                              options: [PickerOption(MenuStyle.standard, L("Standard")),
                                        PickerOption(MenuStyle.compact, L("Compact"))],
                              style: .segmented, defaultValue: MenuConfig().style,
                              anchor: ControlID("menubar.page.style"))
                    .disabled(!displaysOn)
                ToggleSetting(L("Scroll over a slider to adjust it"),
                              help: L("Scrolling over a menu slider moves it, as dragging does."),
                              isOn: SettingsBinding.store(displays, \.menu.scrollAdjustsSliders),
                              anchor: ControlID("menubar.page.scroll"))
                    .disabled(!displaysOn)
                ButtonRow(L("Customize Displays Menu…"), control: ControlID("menubar.page.customize")) {
                    openedHere = true
                    customizeFocus = nil
                    shell.openSheet = CustomizeMenuSheetControls.sheetID
                }
                .disabled(!displaysOn)
            } header: {
                Text(L("Displays menu"))
            } footer: {
                if !displaysOn {
                    Text(L("Turn on Displays to choose how its menu looks."))
                }
            }
            Section {
                GlyphTilePicker(L("Snaptic icon"),
                                symbols: MenuLayout.snapticSymbolChoices(stored: modules.value.sharedSymbol,
                                                                         ownIconSymbols: ownIconSymbols)
                                    .filter(ModulesConfig.isCuratedSymbol),
                                labels: Self.symbolLabels, selection: snapticSymbol,
                                anchor: ControlID("menubar.page.snapticIcon"))
            }
            PageFooterButtons(advanced: nil, help: SettingsRoute(SettingsRootID.menuBar),
                              restoreDefaults: RestoreDefaults(
                                  title: L("Restore Menu Bar Defaults…"),
                                  question: L("Restore menu bar settings to their defaults?"),
                                  message: L("Where Window Switcher, Displays, and Awake appear, their icons, and the Displays menu go back to their defaults. Your other Snaptic settings stay as they are."),
                                  button: L("Restore Defaults"), destructive: false) { restoreDefaults() },
                              restoreControl: ControlID("menubar.page.restoreDefaults"))
        }
        .sheet(isPresented: shell.sheetBinding(CustomizeMenuSheetControls.sheetID),
               onDismiss: { openedHere = false; customizeFocus = nil }) {
            CustomizeMenuSheet(focus: customizeFocus)
        }
        .onAppear { noteCustomizeOpening() }
        .onChange(of: shell.openSheet) { _, _ in noteCustomizeOpening() }
    }

    /// The Customize sheet is the shell's sheet `CustomizeMenuSheetControls.surface`. Opened from elsewhere — Display
    /// Details' link, which selects its display and switches to this page first — it starts with the selected
    /// display shown; a search result (the sidebar search still has text) shows its own row instead.
    private func noteCustomizeOpening() {
        guard shell.openSheet == CustomizeMenuSheetControls.surface, !openedHere else { return }
        customizeFocus = shell.searchText.isEmpty ? shell.selectedDisplay : nil
    }

    private var displaysOn: Bool { modules.value.isEnabled(.displays) }

    // MARK: Modules

    @ViewBuilder
    private func moduleRows(_ id: ModuleID) -> some View {
        let module = host.module(id)
        let presence = modules.value.presence(id)
        // A module that's off shows nothing in the menu bar: its choice stays visible but can't change (ux m18).
        let on = modules.value.isEnabled(id)
        PickerSetting(module.title,
                      help: on ? MenuPlacement.help(presence, for: id) : L("Turn on \(module.title) to choose where it appears."),
                      selection: presenceBinding(id), options: presenceOptions(id), style: .popUp,
                      defaultValue: ModulesConfig.defaultPreferences(id).presence, anchor: Self.presenceControl(id))
            .disabled(!on)
        Group {
            if id == .awake {
                if presence == .ownIcon || presence == .ownIconWhenActive {
                    PickerSetting(L("Time"), help: L("Shows how long your Mac stays awake next to the icon."),
                                  selection: SettingsBinding.store(awake, \.indicator.style),
                                  options: [PickerOption(AwakeIndicatorStyle.icon, L("Don't Show")),
                                            PickerOption(AwakeIndicatorStyle.iconAndTime, L("Time Remaining")),
                                            PickerOption(AwakeIndicatorStyle.iconAndEndTime, L("End Time"))],
                                  style: .popUp, defaultValue: AwakeIndicatorConfig().style,
                                  anchor: ControlID("menubar.page.awakeTime"), subordinate: true)
                    GlyphTilePicker(L("Icon"), symbols: AwakeGlyphFamily.allCases.map(\.idle), labels: Self.symbolLabels,
                                    selection: awakeGlyph, anchor: ControlID("menubar.page.awakeIcon"))
                        .padding(.leading, 20)
                }
            } else if presence == .ownIcon || presence == .ownIconWhenActive {
                GlyphTilePicker(L("Icon"), symbols: Self.moduleSymbols(id, default: module.symbolName,
                                                                       current: modules.value.preferences(id).symbol),
                                labels: Self.symbolLabels, selection: moduleSymbol(id, default: module.symbolName),
                                anchor: Self.iconControl(id))
                    .padding(.leading, 20)
            }
        }
        .disabled(!on)
    }

    private static func presenceControl(_ id: ModuleID) -> ControlID {
        switch id {
        case .windowSwitcher: return ControlID("menubar.page.switcherPresence")
        case .displays: return ControlID("menubar.page.displaysPresence")
        case .awake: return ControlID("menubar.page.awakePresence")
        }
    }

    private static func iconControl(_ id: ModuleID) -> ControlID? {
        switch id {
        case .windowSwitcher: return ControlID("menubar.page.switcherIcon")
        case .displays: return ControlID("menubar.page.displaysIcon")
        case .awake: return nil
        }
    }

    /// The same status the menu bar's Don't Show fallback uses (StatusMenu): registered only per G's runtime flag.
    private var awakeShortcutStatus: MenuLayout.AwakeShortcutStatus {
        MenuLayout.awakeShortcutStatus(awake.value.shortcuts, failed: awakeRuntime.failedShortcuts,
                                       registered: awakeRuntime.keepAwakeRegistered)
    }

    private var awakeShortcutBound: Bool { awakeShortcutStatus.isBound }

    /// Always Show in Menu Bar · Show When Active (Displays, Awake) · Show in Snaptic Menu · Don't Show; Awake's
    /// Don't Show only with a Keep Awake shortcut (parity M2).
    private func presenceOptions(_ id: ModuleID) -> [PickerOption<MenuPresence>] {
        MenuPlacement.presences(for: id).map { presence in
            PickerOption(presence, MenuPlacement.title(presence),
                         enabled: MenuLayout.isSelectable(presence, for: id, awakeShortcutBound: awakeShortcutBound)
                            || modules.value.presence(id) == presence)
        }
    }

    private func presenceBinding(_ id: ModuleID) -> Binding<MenuPresence> {
        let store = modules
        let bound = awakeShortcutBound
        return Binding(get: { store.value.presence(id) },
                       set: { presence in
                           guard store.value.presence(id) != presence,
                                 MenuLayout.isSelectable(presence, for: id, awakeShortcutBound: bound) else { return }
                           store.value.setPresence(presence, for: id)
                       })
    }

    private var modulesFooter: String? {
        var lines: [String] = []
        // Only while Awake runs: off (or turned off by a defaults setting) its row is moot and nothing is registered.
        if awakeRuntime.moduleState != .stopped, let hint = MenuLayout.awakeHideHint(awakeShortcutStatus) {
            lines.append(hint)
        }
        if PermissionFlow.isMacOS27OrLater {
            lines.append(L("macOS can also hide icons in System Settings › Menu Bar. Opening Snaptic again always shows Settings."))
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    // MARK: Warnings (0.2's hidden-icon warnings)

    @ViewBuilder private var warnings: some View {
        let config = modules.value
        let plan = config.statusItemPlan(running: host.runningModules)
        if plan.everythingHidden {
            Section {
                StatusRow(L("No Snaptic icon is shown. Open Snaptic again to come back to Settings; shortcuts keep working."),
                          style: .warning, actions: [
                              StatusAction(title: L("Show Snaptic Menu"), control: ControlID("menubar.page.warning")) {
                                  showSnapticMenu()
                              },
                          ])
            }
        } else if config.iconsNeedExternalDisplay {
            Section {
                StatusRow(L("The Displays icon only appears while an external display is connected. Without one, no Snaptic icon is shown."),
                          style: .warning,
                          actions: [
                              StatusAction(title: L("Always Show Displays"), control: ControlID("menubar.page.warning")) {
                                  modules.value.setPresence(.ownIcon, for: .displays)
                              },
                          ])
            }
        }
    }

    /// Brings the Snaptic item back: every hidden module except Awake moves into it (Awake too when it is the
    /// only one on).
    private func showSnapticMenu() {
        var config = modules.value
        let hidden = config.enabledModules.filter { config.presence($0) == .hidden }
        let movable = hidden.filter { $0 != .awake }
        for id in movable.isEmpty ? hidden : movable { config.setPresence(.inSnapticMenu, for: id) }
        modules.value = config
    }

    // MARK: Icons

    /// Curated glyphs per module; the module's own symbol first (stored as "" = default).
    private static func moduleSymbols(_ id: ModuleID, default symbol: String, current: String) -> [String] {
        let extra: [String]
        switch id {
        case .windowSwitcher: extra = ["rectangle.stack", "macwindow.on.rectangle"]
        case .displays: extra = ["display", "sun.max"]
        case .awake: extra = []
        }
        return unique([symbol] + extra + (current.isEmpty ? [] : [current]))
    }

    private static func unique(_ symbols: [String]) -> [String] {
        var seen = Set<String>()
        return symbols.filter { ModulesConfig.isCuratedSymbol($0) && seen.insert($0).inserted }
    }

    static let symbolLabels: [String: String] = [
        "rectangle.on.rectangle": L("Windows"), "rectangle.stack": L("Stack"), "macwindow.on.rectangle": L("Window"),
        "display.2": L("Two displays"), "display": L("Display"), "sun.max": L("Sun"),
        "square.grid.2x2": L("Grid"), "circle.grid.cross": L("Dots"),
        "cup.and.saucer": L("Cup"), "eye": L("Eye"), "lightbulb": L("Light bulb"),
    ]

    private func moduleSymbol(_ id: ModuleID, default symbol: String) -> Binding<String> {
        let store = modules
        return Binding(get: {
            let stored = store.value.preferences(id).symbol
            return stored.isEmpty ? symbol : stored
        }, set: { chosen in
            let value = chosen == symbol ? "" : chosen
            guard store.value.preferences(id).symbol != value else { return }
            store.value.setSymbol(value, for: id)
        })
    }

    /// The glyphs of the own icons the menu bar shows now: the same modules as the live plan's `ownIcon`
    /// (`ModulesConfig.ownIconIDs`: running, and Displays' Show When Active only with an external display), so the
    /// page and the Snaptic item agree on its glyph (code N3). Awake's item has its own glyph family and never
    /// collides.
    private var ownIconSymbols: [String] {
        let config = modules.value
        let own = config.ownIconIDs(running: host.runningModules, displaysActive: MenuPlacement.hasExternalDisplay)
        return MenuPlacement.ownIconSymbols(own.map { host.module($0) }, in: config)
    }

    /// Shows the glyph the Snaptic item shows; choosing the default stores "" (`storedSharedSymbol`), so it steps
    /// aside by itself whenever an own icon uses it and a choice never pins a colliding glyph.
    private var snapticSymbol: Binding<String> {
        let store = modules
        let own = ownIconSymbols
        return Binding(get: { MenuLayout.sharedSymbol(stored: store.value.sharedSymbol, ownIconSymbols: own) },
                       set: { chosen in
                           let value = MenuLayout.storedSharedSymbol(chosen: chosen)
                           guard store.value.sharedSymbol != value, ModulesConfig.isCuratedSymbol(value) else { return }
                           store.value.sharedSymbol = value
                       })
    }

    private var awakeGlyph: Binding<String> {
        let store = awake
        return Binding(get: { store.value.indicator.glyph.idle },
                       set: { symbol in
                           guard let family = AwakeGlyphFamily.allCases.first(where: { $0.idle == symbol }),
                                 store.value.indicator.glyph != family else { return }
                           store.value.indicator.glyph = family
                       })
    }

    // MARK: Restore

    /// Presence, icons, Awake's Time and Icon, and the Displays menu (style, scrolling, Customize choices).
    private func restoreDefaults() {
        modules.value.resetMenu()
        displays.value.menu = displays.value.menu.restoringDefaults(scope: .menuBar)
        awake.value.indicator = AwakeIndicatorConfig()
    }
}
