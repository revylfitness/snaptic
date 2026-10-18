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

    /// The pages the root page's navigation rows open (`DisplaysModule.settingsDestination(_:)`); nil for every
    /// other route, which the shell then resolves to a 0.2 page.
    @MainActor static func destination(_ route: SettingsRoute, env: DisplaysPageEnvironment) -> AnyView? {
        if route.id == DisplaysFeaturesPage.route.id { return AnyView(DisplaysFeaturesPage(env: env)) }
        guard let page = DisplaysSubpage(rawValue: route.id) else { return nil }
        return AnyView(DisplaysSubpageHost(page: page, env: env))
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
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>
    @StateObject private var menu: ConfigSlice<DisplaysConfig, MenuConfig>
    @StateObject private var models = DisplayLiveModelCache()

    init(env: DisplaysPageEnvironment, host: ModuleHost) {
        self.env = env
        _host = ObservedObject(wrappedValue: host)
        _modules = ObservedObject(wrappedValue: host.modulesStore)
        _shell = ObservedObject(wrappedValue: SettingsShell.shared)
        _runtime = ObservedObject(wrappedValue: env.runtime)
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
                    StatusRow(L("Turned off by a defaults setting."), style: .warning)
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
                arrangementSection(displays: displays)
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
            PageFooterButtons(advanced: { shell.openSheet = DisplaysAdvancedSheetControls.sheet },
                              help: SettingsRoute(SettingsRootID.displays),
                              advancedControl: ControlID("displays.root.advanced"))
        }
        .sheet(isPresented: shell.sheetBinding(DisplaysAdvancedSheetControls.sheet)) {
            DisplaysAdvancedSheet(env: env)
        }
        .sheet(isPresented: shell.sheetBinding(DisplayDetailsSheetControls.sheet)) {
            DisplayDetailsSheet(env: env, key: selected?.key)
        }
    }

    /// Connected displays in the menu order (hidden ones too: Settings shows every display).
    private var connectedDisplays: [DisplayInfo] {
        DisplaysLive.ordered(runtime: runtime, config: env.config.value, includeHidden: true).filter(\.isOnline)
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
                        StatusAction(title: L("Leave Safe Mode…"), control: ControlID("displays.root.status.leaveSafeMode")) {
                            ctx.relauncher.relaunch(reason: L("Leave Safe Mode"))
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
                }
            }
        }
    }

    // MARK: Arrangement

    @ViewBuilder private func arrangementSection(displays: [DisplayInfo]) -> some View {
        Section {
            if runtime.isEffective(.arrangement), displays.count > 1 {
                ButtonRow(L("Arrange Displays…"), control: ControlID("displays.root.arrange")) {
                    shell.push(SettingsRoute("displays.arrangement"))
                }
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

// MARK: - Sub-pages (step 2: hosts for the 0.2 pages until each owner's 0.3 sub-page lands)

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

    var summary: String {
        switch self {
        case .brightness: return L("Restore, dim, sync, and extra brightness for every display.")
        case .color: return L("Contrast, gamma, temperature, and color profiles in software.")
        case .hardware: return L("Volume, input, and power for displays that support them.")
        case .keyboard: return L("Brightness and volume keys, the brightness indicator, and shortcuts.")
        case .layouts: return L("Save display arrangements and apply them automatically.")
        case .virtual: return L("Create displays that exist only in software.")
        case .pip: return L("Show a live view of any window or display.")
        case .automations: return L("Run a program when displays change.")
        case .information: return L("A live report about your displays, to copy when something goes wrong.")
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

    /// The 0.2 pages that hold these settings until the owner's sub-page lands.
    var legacyPages: [String] {
        switch self {
        case .brightness: return ["displays.brightness"]
        case .color: return ["displays.color"]
        case .hardware: return ["displays.ddc"]
        case .keyboard: return ["displays.keys", "displays.osd"]
        case .layouts: return ["displays.protection"]
        case .virtual: return ["displays.virtual"]
        case .pip: return ["displays.pip"]
        case .automations: return ["displays.automation"]
        case .information: return ["displays.diagnostics"]
        }
    }

    /// What a page that can't show yet needs, for pages without a switch of their own.
    var needs: [DisplayFeature] {
        switch self {
        case .brightness: return [.brightness]
        default: return []
        }
    }

    static func switchTitle(_ feature: DisplayFeature) -> String {
        switch feature {
        case .color: return L("Color adjustments")
        case .ddcControls: return L("Hardware controls")
        case .layouts: return L("Saved layouts")
        case .virtualScreens: return L("Virtual displays")
        case .pip: return L("Picture in Picture")
        case .hooks: return L("Event hooks")
        case .customActions: return L("Custom actions")
        case .brightnessKeys: return L("Brightness keys")
        case .volumeKeys: return L("Volume keys")
        case .brightness: return L("Brightness control")
        default: return DisplaysUIText.title(feature)
        }
    }

    static func switchHelp(_ feature: DisplayFeature) -> String {
        switch feature {
        case .brightnessKeys: return L("The brightness keys also change external displays.")
        case .volumeKeys: return L("The volume keys change a display’s speakers when it’s the sound output.")
        case .hooks: return L("Runs a program when a display connects, disconnects, or sleeps.")
        case .customActions: return L("Your own programs in the menu and as shortcuts.")
        default: return DisplaysUIText.summary(feature)
        }
    }
}

/// A root-page navigation target: the 0.2 page(s) holding its settings, under the sub-page's feature switch. One
/// page with a switch: the switch above the page. Several pages: an index. Nothing to show yet: the header, its
/// switch and what the page does (or what it needs).
private struct DisplaysSubpageHost: View {
    let page: DisplaysSubpage
    let env: DisplaysPageEnvironment
    @ObservedObject private var runtime: DisplaysRuntimeState
    @StateObject private var switcher: DisplaysFeatureSwitcher
    @StateObject private var features: ConfigSlice<DisplaysConfig, [DisplayFeature: Bool]>

    init(page: DisplaysSubpage, env: DisplaysPageEnvironment) {
        self.page = page
        self.env = env
        _runtime = ObservedObject(wrappedValue: env.runtime)
        _switcher = StateObject(wrappedValue: DisplaysFeatureSwitcher(env: env))
        _features = StateObject(wrappedValue: ConfigSlice(env.config, \.rawFeatures))
    }

    /// The 0.2 pages that exist now (their features run).
    private var available: [SettingsPage] {
        guard let host = SettingsShell.shared.host, host.isRunning(.displays) else { return [] }
        let pages = host.displays.settingsPages()
        return page.legacyPages.compactMap { id in pages.first { $0.id == id } }
    }

    var body: some View {
        let pages = available
        Group {
            if pages.count == 1, page.headerSwitch == nil, page.rowSwitches.isEmpty {
                pages[0].makeView()
            } else if pages.count == 1, page != .keyboard {
                VStack(spacing: 0) {
                    switchBar
                    Divider()
                    pages[0].makeView()
                }
            } else {
                index(pages)
            }
        }
        .modifier(DisplaysFeatureOffAlert(switcher: switcher))
    }

    /// The sub-page's switches above a 0.2 page.
    private var switchBar: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingsIcon(page.symbol, tint: page.tint, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title).font(.headline)
                Text(page.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if let feature = page.headerSwitch {
                Toggle(DisplaysSubpage.switchTitle(feature),
                       isOn: switcher.binding([feature], title: DisplaysSubpage.switchTitle(feature)))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help(DisplaysSubpage.switchTitle(feature))
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(page.rowSwitches, id: \.self) { feature in
                        Toggle(DisplaysSubpage.switchTitle(feature),
                               isOn: switcher.binding([feature], title: DisplaysSubpage.switchTitle(feature)))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func index(_ pages: [SettingsPage]) -> some View {
        SettingsPageScaffold(route: SettingsRoute(page.rawValue)) {
            SettingsPageHeader(page.title, summary: page.summary, symbol: page.symbol, tint: page.tint,
                               isOn: page.headerSwitch.map { switcher.binding([$0], title: DisplaysSubpage.switchTitle($0)) },
                               switchLabel: page.headerSwitch.map(DisplaysSubpage.switchTitle))
            if !page.rowSwitches.isEmpty {
                Section {
                    ForEach(page.rowSwitches, id: \.self) { feature in
                        ToggleSetting(DisplaysSubpage.switchTitle(feature), help: DisplaysSubpage.switchHelp(feature),
                                      isOn: switcher.binding([feature], title: DisplaysSubpage.switchTitle(feature)),
                                      disabledReason: unavailableReason(feature))
                    }
                }
            }
            if pages.isEmpty {
                waiting
            } else {
                Section {
                    ForEach(pages) { legacy in
                        NavigationRow(legacy.title, symbol: legacy.symbol, tint: page.tint, route: SettingsRoute(legacy.id))
                    }
                }
            }
        }
    }

    /// Why nothing shows yet.
    @ViewBuilder private var waiting: some View {
        let switches = page.headerSwitch.map { [$0] } ?? []
        let rowsOff = !page.rowSwitches.isEmpty
            && !page.rowSwitches.contains(where: { FeatureGraph.rawState($0, in: features.value) })
        let needs = page.needs
        if !(SettingsShell.shared.host?.isRunning(.displays) ?? false) {
            Section {
                StatusRow(L("Turn on Displays to use these settings."))
            }
        } else if !needs.isEmpty, !needs.contains(where: { FeatureGraph.rawState($0, in: features.value) }) {
            Section {
                StatusRow(L("\(DisplaysSubpage.switchTitle(needs[0])) is off."), actions: [
                    StatusAction(title: L("Turn On")) {
                        switcher.binding([needs[0]], title: DisplaysSubpage.switchTitle(needs[0])).wrappedValue = true
                    },
                ])
            }
        } else if !switches.isEmpty, !switches.contains(where: { FeatureGraph.rawState($0, in: features.value) }) {
            FeatureHighlights(switches.map {
                FeatureHighlight(id: $0.rawValue, symbol: page.symbol, title: DisplaysSubpage.switchTitle($0),
                                 text: DisplaysSubpage.switchHelp($0))
            })
        } else if rowsOff {
            EmptyView()
        } else {
            Section {
                StatusRow(reason ?? L("These settings aren’t available right now."), style: .info)
            }
        }
    }

    private var reason: String? {
        let switches = (page.headerSwitch.map { [$0] } ?? page.rowSwitches) + page.needs
        for feature in switches {
            if let r = unavailableReason(feature) { return r }
            if let r = env.context?.otherApps.pauseReason(for: feature) { return r }
        }
        return nil
    }

    private func unavailableReason(_ feature: DisplayFeature) -> String? {
        if case .unavailable(let reason)? = runtime.availability[feature] { return reason }
        return nil
    }
}

/// "displays.features" (0.2 links still open it): the feature switches of Displays › Advanced as a page.
private struct DisplaysFeaturesPage: View {
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
