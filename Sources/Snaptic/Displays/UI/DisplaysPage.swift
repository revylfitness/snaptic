import SwiftUI
import SnapticKit

/// The Displays root page (owner F; PLAN 0.3 §4.3 "Displays root page", §4.5): header switch "Use Displays", status
/// rows while they're true, the Display section (Display Tools ▾, display tiles, Display Details…, live Brightness),
/// Resolution, Arrangement, the navigation groups and the footer (Advanced… · ?). A hub, like System Settings ›
/// Displays: rendered whether or not Displays runs; while it is off it shows what it does.
/// Live values come from `DisplayRuntime` and the controllers' `ControllerRevision`s; config through slices, so a
/// write elsewhere doesn't re-render the page.
struct DisplaysPage: View, ControlDeclaring {
    typealias Controls = DisplaysPageControls

    let env: DisplaysPageEnvironment

    static let title = L("Displays")
    static let summary = L("Brightness, resolution, and arrangement for every display.")
    static let symbol = "sun.max.fill"
    static let tint = SettingsTint.blue

    /// Shown while Displays is off (the module's `highlights`).
    static let highlights: [FeatureHighlight] = [
        FeatureHighlight(id: "displays.brightness", symbol: "sun.max.fill", title: L("Brightness for every display"),
                         text: L("One slider per display, including external displays, here and in the menu.")),
        FeatureHighlight(id: "displays.resolution", symbol: "rectangle.arrowtriangle.2.outward",
                         title: L("Resolution and arrangement"),
                         text: L("Larger text or more space, refresh rates, mirroring, and saved layouts.")),
        FeatureHighlight(id: "displays.hardware", symbol: "slider.horizontal.3", title: L("Hardware controls"),
                         text: L("Volume, input, and power for displays that support them.")),
    ]

    /// The Settings sidebar root (`DisplaysModule.settingsRoot()`).
    @MainActor static func settingsRoot(env: DisplaysPageEnvironment) -> SettingsRoot {
        SettingsRoot(id: SettingsRootID.displays, title: title, symbol: symbol, tint: tint) {
            AnyView(DisplaysPage(env: env))
        }
    }

    /// Every Displays sub-route (`DisplaysModule.settingsDestination(_:)`, PLAN 0.3 §4.3): the owner's 0.3 page once
    /// it is built, else the 0.2 page that still holds those settings. nil for routes the shell resolves to a 0.2 page
    /// itself.
    @MainActor static func destination(_ route: SettingsRoute, env: DisplaysPageEnvironment) -> AnyView? {
        if route.id == DisplaysFeaturesPage.route.id { return AnyView(DisplaysFeaturesPage(env: env)) }
        // Arrange Displays is a sheet on the root page (the menu's "Arrange Displays…" opens this route).
        if route.id == ArrangeSheetControls.sheet { return AnyView(DisplaysRootSheetRedirect(sheet: ArrangeSheetControls.sheet)) }
        if let page = DisplaysSubpage(rawValue: route.id) {
            SettingsShell.shared.noteTitle(page.title, for: route)
            return DisplaysOwnerPages.page(page, env: env)
        }
        if let section = DisplaysSectionRoute(rawValue: route.id) {
            SettingsShell.shared.noteTitle(section.title, for: route)
            return DisplaysOwnerPages.page(section)
        }
        return nil
    }

    var body: some View {
        if let host = SettingsShell.shared.host {
            DisplaysRootContent(env: env, host: host)
        } else {
            UnavailablePage()
        }
    }
}

// MARK: - Root content

private struct DisplaysRootContent: View {
    let env: DisplaysPageEnvironment
    @ObservedObject private var host: ModuleHost
    @ObservedObject private var modules: ConfigStore<ModulesConfig>
    @ObservedObject private var shell: SettingsShell
    @ObservedObject private var runtime: DisplaysRuntimeState
    /// B bumps it when the guard, panic or transaction state changes (the status rows).
    @ObservedObject private var safetyRevision: ControllerRevision
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var menu: ConfigSlice<DisplaysConfig, MenuConfig>
    @StateObject private var models = DisplayLiveModelCache()

    init(env: DisplaysPageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _modules = ObservedObject(wrappedValue: host.modulesStore)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _safetyRevision = ObservedObject(wrappedValue: env.runtime.revision(.diagnostics))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
        _menu = StateObject(wrappedValue: ConfigSlice(env.config, \.menu))
    }

    var body: some View {
        let blocked = host.disabledByDefaults.contains(.displays)
        let enabled = !blocked && modules.value.isEnabled(.displays)
        let context = host.isRunning(.displays) ? env.context : nil
        let displays = context == nil ? [] : connectedDisplays
        let selected = displays.first { $0.key == shell.selectedDisplay } ?? displays.first
        SettingsPageScaffold(route: SettingsRoute(SettingsRootID.displays)) {
            SettingsPageHeader(DisplaysPage.title, summary: DisplaysPage.summary, symbol: DisplaysPage.symbol,
                               tint: DisplaysPage.tint, isOn: shell.moduleEnabled(.displays),
                               switchLabel: L("Use Displays"),
                               status: context == nil ? nil : DisplaysRootText.status(displayCount: displays.count),
                               control: ControlID("displays.root.useDisplays"))
                .disabled(blocked)
            if blocked {
                Section {
                    DefaultsLockRow(module: .displays)
                }
            }
            if !enabled {
                FeatureHighlights(DisplaysPage.highlights)
            } else if let context {
                statusRows(context)
                if let selected {
                    displaySection(context, displays: displays, display: selected)
                    resolutionSection(context, display: selected)
                } else {
                    Section {
                        StatusRow(L("No displays are connected."), actions: [
                            StatusAction(title: L("Redetect Displays")) {
                                _ = context.actions.perform(OverviewController.redetectAction, on: .all)
                            },
                        ])
                    }
                }
                arrangementSection(displays: displays, display: selected)
                navigationSections
            } else {
                Section {
                    if case .degraded(let reason) = runtime.moduleState {
                        StatusRow(reason, style: .warning)
                    } else {
                        StatusRow(L("Starting…"))
                    }
                }
            }
            // While Displays is off the footer offers only (?), like the other modules' pages (ux round 2 Nit 9).
            PageFooterButtons(advanced: enabled ? openAdvanced : nil,
                              help: SettingsRoute(SettingsRootID.displays),
                              advancedControl: ControlID("displays.root.advanced"))
        }
        .sheet(isPresented: shell.sheetBinding(DisplaysAdvancedSheetControls.sheet)) {
            DisplaysAdvancedSheet(env: env)
        }
        .sheet(isPresented: shell.sheetBinding(DisplayDetailsSheetControls.sheet)) {
            DisplayDetailsSheet(env: env, key: selected?.key)
        }
        .sheet(isPresented: shell.sheetBinding(ArrangeSheetControls.sheet)) {
            ArrangeSheet(env: env)
        }
    }

    private var openAdvanced: (() -> Void)? {
        let shell = shell
        return { shell.openSheet = DisplaysAdvancedSheetControls.sheet }
    }

    /// Connected displays in the menu order (hidden ones too: Settings shows every display).
    private var connectedDisplays: [DisplayInfo] {
        DisplaysLive.ordered(runtime: runtime, menu: menu.value, includeHidden: true).filter(\.isOnline)
    }

    // MARK: Status rows (only while true; parity minor 1)

    @ViewBuilder private func statusRows(_ ctx: DisplaysContext) -> some View {
        let paused = ctx.otherApps.pausedDisplayFeatures
        let unprotected = DisplaysLive.unprotectedReason(ctx)
        let degraded: String? = {
            if case .degraded(let reason) = runtime.moduleState { return reason }
            return nil
        }()
        if ctx.safeMode.isActive || runtime.isPanicLatched || unprotected != nil || !paused.isEmpty || degraded != nil {
            Section {
                if let degraded {
                    StatusRow(degraded, style: .warning)
                }
                if ctx.safeMode.isActive {
                    StatusRow(L("Safe Mode is on."), style: .warning, actions: [
                        // The one "Leave Safe Mode?" confirmation everywhere (ux round 2 N5; H's helper).
                        StatusAction(title: L("Leave Safe Mode…"), control: ControlID("displays.root.status.leaveSafeMode")) {
                            SafeModeLeave.confirm(relauncher: ctx.relauncher)
                        },
                    ])
                }
                if runtime.isPanicLatched {
                    StatusRow(L("Display automation is paused."), symbol: "pause.circle.fill", actions: [
                        StatusAction(title: L("Resume Display Automation"),
                                     control: ControlID("displays.root.status.resume")) {
                            _ = ctx.actions.perform(PanicCoordinator.resumeActionID, on: .all)
                        },
                    ])
                }
                if unprotected != nil {
                    StatusRow(L("The safety helper stopped."), style: .warning, actions: [
                        StatusAction(title: L("Restart Snaptic"), control: ControlID("displays.root.status.restartHelper")) {
                            ctx.relauncher.relaunch(reason: L("Restart the safety helper"))
                        },
                    ])
                }
                ForEach(Array(Set(paused.compactMap { ctx.otherApps.pauseReason(for: $0) })).sorted(), id: \.self) {
                    StatusRow($0, symbol: "pause.circle")
                }
            }
        }
    }

    // MARK: Display

    @ViewBuilder
    private func displaySection(_ ctx: DisplaysContext, displays: [DisplayInfo], display: DisplayInfo) -> some View {
        let model = models.model(display.key, context: ctx)
        Section {
            if displays.count > 1 {
                PerDisplayPicker(displays.map {
                    DisplayTile(id: $0.key, name: $0.name, isBuiltin: $0.isBuiltin, badges: DisplaysLive.badges(for: $0))
                }, selection: $shell.selectedDisplay)
                .modifier(SettingsAnchor(ControlID("displays.root.display")))
            }
            ButtonRow(L("Display Details…"), control: ControlID("displays.root.details")) {
                shell.openSheet = DisplayDetailsSheetControls.sheet
            }
            if runtime.isEffective(.brightness) {
                LiveBrightnessRow(anchor: ControlID("displays.root.brightness"), live: runtime.runtime(for: display.key),
                                  model: model)
            }
            if runtime.isEffective(.autoBrightness), display.isBuiltin {
                LiveAutoBrightnessRow(anchor: ControlID("displays.root.autoBrightness"), model: model,
                                      revision: runtime.revision(.systemColors))
            }
        } header: {
            HStack {
                Text(L("Display"))
                Spacer(minLength: 8)
                ActionMenuButton(L("Display Tools"), items: displayTools(ctx), primaryAction: nil,
                                 control: ControlID("displays.root.displayTools"))
            }
        }
    }

    /// Display Tools ▾ (design m14): there with one display too; an item whose feature is off isn't listed.
    private func displayTools(_ ctx: DisplaysContext) -> [ActionMenuItem] {
        func perform(_ id: DisplayActionID, on target: DisplayTarget = .all) -> @MainActor () -> Void {
            { _ = ctx.actions.perform(id, on: target) }
        }
        func has(_ id: DisplayActionID) -> Bool { ctx.actions.action(id) != nil }
        var items = [
            ActionMenuItem(id: "identify", title: L("Identify Displays"), enabled: has(.fIdentify),
                           action: perform(.fIdentify)),
            ActionMenuItem(id: "redetect", title: L("Redetect Displays"), enabled: has(OverviewController.redetectAction),
                           action: perform(OverviewController.redetectAction)),
            ActionMenuItem(id: "panel", title: L("Show Displays Panel"), enabled: has(.fShowPanel),
                           action: perform(.fShowPanel, on: .pointer)),
        ]
        if runtime.isEffective(.scaleMatch), has(.dMatchUI) {
            items.append(ActionMenuItem(id: "matchTextSize", title: L("Match Text Size…"), action: perform(.dMatchUI)))
        }
        if runtime.isEffective(.disconnect) {
            if has(.dConnectAll) {
                items.append(ActionMenuItem(id: "connectAll", title: L("Connect All Displays"), action: perform(.dConnectAll)))
            }
            if has(.dDisconnectAllButMain) {
                items.append(ActionMenuItem(id: "disconnectAll", title: L("Disconnect All But Main"),
                                            action: perform(.dDisconnectAllButMain)))
            }
        }
        items.append(.separator("restoreSeparator"))
        items.append(ActionMenuItem(id: "restoreAll", title: L("Restore All Displays")) {
            ctx.panic.panic(reason: L("Restore All Displays (Settings)"))
        })
        return items
    }

    // MARK: Resolution (the selected display)

    @ViewBuilder private func resolutionSection(_ ctx: DisplaysContext, display: DisplayInfo) -> some View {
        if runtime.isEffective(.resolution), display.isActive {
            let model = models.model(display.key, context: ctx)
            Section {
                if display.mirrorOf != nil {
                    StatusRow(L("This display mirrors another display, so it uses that display’s resolution."))
                } else {
                    LiveResolutionRow(display: display, anchor: ControlID("displays.root.resolution"), model: model,
                                      revision: runtime.revision(.resolution))
                    LiveRefreshRow(display: display, anchor: ControlID("displays.root.refreshRate"), model: model,
                                   revision: runtime.revision(.resolution))
                    ResolutionSections(env: env, display: display)
                }
            }
        }
    }

    // MARK: Arrangement

    @ViewBuilder private func arrangementSection(displays: [DisplayInfo], display: DisplayInfo?) -> some View {
        Section {
            if let display {
                ArrangementRows(env: env, display: display, displayCount: displays.count)
            }
            navigationRow(.layouts, control: ControlID("displays.root.nav.layouts"))
        }
    }

    // MARK: Navigation

    @ViewBuilder private var navigationSections: some View {
        Section {
            navigationRow(.brightness, control: ControlID("displays.root.nav.brightness"))
            navigationRow(.color, control: ControlID("displays.root.nav.color"))
            navigationRow(.hardware, control: ControlID("displays.root.nav.hardware"))
            navigationRow(.keyboard, control: ControlID("displays.root.nav.keyboard"))
        }
        Section {
            navigationRow(.virtual, control: ControlID("displays.root.nav.virtual"))
            navigationRow(.pip, control: ControlID("displays.root.nav.pip"))
            navigationRow(.automations, control: ControlID("displays.root.nav.automations"))
        }
        Section {
            navigationRow(.information, control: ControlID("displays.root.nav.information"))
        }
    }

    /// A row shows On/Off only when its sub-page has a feature switch (consistency m14).
    private func navigationRow(_ page: DisplaysSubpage, control: ControlID) -> some View {
        let switches = page.headerSwitch.map { [$0] } ?? page.rowSwitches
        let value = page.showsValue
            ? DisplaysRootText.navigationValue(isOn: switches.contains { FeatureGraph.rawState($0, in: features.value) })
            : nil
        return NavigationRow(page.title, symbol: page.symbol, tint: page.tint, value: value,
                             route: SettingsRoute(page.rawValue), control: control)
    }
}

// MARK: - Sub-pages (hosts for the 0.2 pages until each owner's 0.3 sub-page is built)

/// The root page's navigation targets. Route ids are the owners' control-table surfaces.
enum DisplaysSubpage: String, CaseIterable {
    case brightness = "displays.brightness"
    case color = "displays.color"
    case hardware = "displays.hardware"
    case keyboard = "displays.keyboard"
    case layouts = "displays.layouts"
    case virtual = "displays.virtual"
    case pip = "displays.pip"
    case automations = "displays.automations"
    case information = "displays.info"

    var title: String {
        switch self {
        case .brightness: return L("Brightness and Dimming")
        case .color: return L("Color")
        case .hardware: return L("Hardware Controls")
        case .keyboard: return L("Keyboard")
        case .layouts: return L("Saved Layouts")
        case .virtual: return L("Virtual Displays")
        case .pip: return L("Picture in Picture")
        case .automations: return L("Automations")
        case .information: return L("Display Information")
        }
    }

    var symbol: String {
        switch self {
        case .brightness: return "sun.max.fill"
        case .color: return "paintpalette.fill"
        case .hardware: return "slider.horizontal.3"
        case .keyboard: return "keyboard.fill"
        case .layouts: return "rectangle.3.group.fill"
        case .virtual: return "display.2"
        case .pip: return "pip.fill"
        case .automations: return "gearshape.2.fill"
        case .information: return "info.circle.fill"
        }
    }

    var tint: SettingsTint {
        switch self {
        case .brightness: return .blue
        case .color: return .purple
        case .hardware: return .gray
        case .keyboard: return .graphite
        case .layouts: return .indigo
        case .virtual: return .teal
        case .pip: return .green
        case .automations: return .orange
        case .information: return .gray
        }
    }

    /// The sub-page's header switch (PLAN 0.3 §4.3 sub-page table).
    var headerSwitch: DisplayFeature? {
        switch self {
        case .color: return .color
        case .hardware: return .ddcControls
        case .layouts: return .layouts
        case .virtual: return .virtualScreens
        case .pip: return .pip
        case .brightness, .keyboard, .automations, .information: return nil
        }
    }

    /// Switches shown as rows (Keyboard's keys) or section switches (Automations).
    var rowSwitches: [DisplayFeature] {
        switch self {
        case .keyboard: return [.brightnessKeys, .volumeKeys]
        case .automations: return [.hooks, .customActions]
        default: return []
        }
    }

    /// Whether the root page's row shows On/Off (Brightness and Dimming and Keyboard show none).
    var showsValue: Bool { headerSwitch != nil || self == .automations }
}

/// Sub-routes that aren't navigation rows of the root page: the full-page forms of D's root and Display Details
/// sections, opened from menus ("Match Text Size…", "Underscan…", "More Resolutions…"), search and Display Details.
enum DisplaysSectionRoute: String, CaseIterable {
    case resolution = "displays.resolution"
    case matchTextSize = "displays.matchTextSize"
    case connection = "displays.connection"

    var title: String {
        switch self {
        case .resolution: return L("Resolution")
        case .matchTextSize: return L("Match Text Size")
        case .connection: return L("Connection")
        }
    }
}

/// The owners' 0.3 pages, each shown directly (they have their own header and switches).
@MainActor enum DisplaysOwnerPages {
    static func page(_ page: DisplaysSubpage, env: DisplaysPageEnvironment) -> AnyView {
        switch page {
        case .brightness: return AnyView(BrightnessSubpage(env: env))
        case .color: return AnyView(ColorPage(env: env))
        case .hardware: return AnyView(HardwareControlsPage(env: env))
        case .keyboard: return AnyView(KeyboardPage(env: env))
        case .layouts: return AnyView(SavedLayoutsPage(env: env))
        case .virtual: return AnyView(VirtualDisplaysPage(env: env))
        case .pip: return AnyView(PIPPage(env: env))
        case .automations: return AnyView(AutomationsPage(env: env))
        case .information: return AnyView(DisplayInformationPage(env: env))
        }
    }

    static func page(_ route: DisplaysSectionRoute) -> AnyView {
        switch route {
        case .resolution: return AnyView(ResolutionSections())
        case .matchTextSize: return AnyView(MatchTextSizeSection())
        case .connection: return AnyView(ConnectionSection())
        }
    }
}

/// A route that names a sheet of the root page: goes back to the root page, then opens the sheet there (a sheet is
/// presented by the page that owns it, never pushed).
private struct DisplaysRootSheetRedirect: View {
    let sheet: String

    var body: some View {
        Color.clear
            .onAppear {
                let sheet = sheet
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let shell = SettingsShell.shared
                        shell.go(to: SettingsLocation(root: SettingsRootID.displays))
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated { shell.openSheet = sheet }
                        }
                    }
                }
            }
    }
}

/// "displays.features" (0.2 links still open it): the feature switches of Displays › Advanced as a page.
struct DisplaysFeaturesPage: View {
    static let route = SettingsRoute("displays.features")

    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>

    init(env: DisplaysPageEnvironment) {
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
    }

    var body: some View {
        SettingsPageScaffold(route: Self.route) {
            DisplaysFeatureGroups(switcher: switcher, runtime: runtime, features: features)
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
    }
}
