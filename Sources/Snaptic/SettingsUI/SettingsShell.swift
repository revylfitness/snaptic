import AppKit
import SwiftUI
import SnapticKit

/// The Settings window's navigation state (H, sole owner; PLAN 0.3 §4.1, §4.2, R5-8): sidebar root, one
/// NavigationStack path per root, the open sheet, the search highlight, the shared display selection and the focus
/// guard for session starts. One instance, `SettingsShell.shared`, attached to the host by `SettingsWindowHost`.
/// Pages reach it as `SettingsShell.shared` (an `@ObservedObject` where they show its state).
@MainActor final class SettingsShell: ObservableObject {
    static let shared = SettingsShell()
    /// `@AppStorage("settingsLastRoute")`: "root" or "root route" (no dots in the key).
    static let lastRouteKey = "settingsLastRoute"
    /// How long a revealed row stays tinted.
    static let highlightSeconds = 1.2

    /// Sidebar selection.
    @Published var root: String = SettingsRootID.general {
        didSet { if root != oldValue { remember() } }
    }
    /// One NavigationStack path per root.
    @Published var paths: [String: [SettingsRoute]] = [:] {
        didSet { remember() }
    }
    @Published var openSheet: String?
    @Published var highlightedAnchor: String? {
        didSet { SettingsHighlight.shared.show(highlightedAnchor) }
    }
    /// Shared PerDisplayPicker selection (design m9).
    @Published var selectedDisplay: DisplayKey?
    /// R5-8: set by every externally requested open; cleared by the first mouse-down in the window or an open from
    /// Snaptic's own menu or hotkey.
    @Published private(set) var externalOpenPending = false
    /// The sidebar search field.
    @Published var searchText = ""
    /// The chosen search result (its entry id).
    @Published var selectedResult: String?

    private(set) weak var host: ModuleHost?
    /// Whether the Settings window shows a sheet now (set by `SettingsWindowHost`).
    var windowHasSheet: (@MainActor () -> Bool)?
    private var focusGuard = SettingsFocusGuard()
    private var pendingHighlight: PendingHighlight?
    private var highlightWork: DispatchWorkItem?
    private var revealToken = 0
    private var routeTitles: [String: String] = [:]
    private var indexCache: [SettingsSearchEntry]?
    private var restored = false

    init() {}

    func attach(_ host: ModuleHost) {
        self.host = host
    }

    // MARK: Roots

    /// Fixed sidebar symbols and tints (§4.2; the IA is normative, whatever a module's own symbol).
    static let sidebarStyle: [String: (symbol: String, tint: SettingsTint)] = [
        SettingsRootID.general: ("gearshape", .gray),
        SettingsRootID.menuBar: ("menubar.rectangle", .graphite),
        SettingsRootID.windowSwitcher: ("rectangle.on.rectangle", .indigo),
        SettingsRootID.displays: ("sun.max.fill", .blue),
        SettingsRootID.awake: ("cup.and.saucer.fill", .orange),
        SettingsRootID.permissions: ("hand.raised.fill", .blue),
        SettingsRootID.about: ("info.circle.fill", .gray),
    ]

    /// The seven roots in sidebar order: the host's pages and every module's `settingsRoot()` (rendered whether the
    /// module runs or not).
    func roots() -> [SettingsRoot] {
        guard let host else { return [] }
        var byID: [String: SettingsRoot] = [:]
        func add(_ id: String, _ title: String, _ make: @escaping @MainActor () -> AnyView) {
            let style = Self.sidebarStyle[id] ?? ("gearshape", .gray)
            byID[id] = SettingsRoot(id: id, title: title, symbol: style.symbol, tint: style.tint, makeView: make)
        }
        add(SettingsRootID.general, L("General")) { [weak host] in
            host.map { AnyView(GeneralPage(host: $0)) } ?? AnyView(UnavailablePage())
        }
        add(SettingsRootID.menuBar, L("Menu Bar")) { AnyView(MenuBarPage()) }
        for module in host.modules {
            // The Window Switcher's page is H's (its module keeps the default hub for its 0.2 pages).
            let r = module.id == .windowSwitcher ? SwitcherPages.root(module: host.switcher) : module.settingsRoot()
            // The sidebar's symbols and tints are fixed by the IA, whatever a module's own symbol (§4.2).
            if let style = Self.sidebarStyle[r.id] {
                byID[r.id] = SettingsRoot(id: r.id, title: r.title, symbol: style.symbol, tint: style.tint, makeView: r.makeView)
            } else {
                byID[r.id] = r
            }
        }
        add(SettingsRootID.permissions, L("Permissions")) { [weak host] in
            host.map { AnyView(PermissionsPage(host: $0)) } ?? AnyView(UnavailablePage())
        }
        add(SettingsRootID.about, L("About")) { [weak host] in
            host.map { AnyView(AboutPage(host: $0)) } ?? AnyView(UnavailablePage())
        }
        let known = SettingsRootID.all
        return known.compactMap { byID[$0] } + byID.values.filter { !known.contains($0.id) }.sorted { $0.id < $1.id }
    }

    var rootIDs: Set<String> {
        var ids = Set(SettingsRootID.all)
        if let host { ids.formUnion(host.modules.map { $0.id.rawValue }) }
        return ids
    }

    /// A sidebar item's title, without building the roots (search result rows ask once per row).
    func rootTitle(_ id: String) -> String {
        switch id {
        case SettingsRootID.general: return L("General")
        case SettingsRootID.menuBar: return L("Menu Bar")
        case SettingsRootID.permissions: return L("Permissions")
        case SettingsRootID.about: return L("About")
        default: return host?.modules.first { $0.id.rawValue == id }?.title ?? id
        }
    }

    /// Module on/off as a binding (the page header master switch). A module turned off by `Modules.disable.<id>`
    /// reads off and ignores writes.
    func moduleEnabled(_ id: ModuleID) -> Binding<Bool> {
        Binding(get: { [weak self] in
            guard let host = self?.host, !host.disabledByDefaults.contains(id) else { return false }
            return host.modulesStore.value.isEnabled(id)
        }, set: { [weak self] on in
            guard let host = self?.host, !host.disabledByDefaults.contains(id) else { return }
            host.setEnabled(on, id)
        })
    }

    // MARK: Navigation

    func push(_ route: SettingsRoute) { paths[root, default: []].append(route) }

    func pop() { _ = paths[root]?.popLast() }

    func pathBinding(for root: String) -> Binding<[SettingsRoute]> {
        Binding(get: { [weak self] in self?.paths[root] ?? [] },
                set: { [weak self] in self?.paths[root] = $0 })
    }

    /// `.sheet(isPresented: SettingsShell.shared.sheetBinding("awake.advanced"))`: search can open it.
    func sheetBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { [weak self] in self?.openSheet == id },
                set: { [weak self] on in
                    guard let self else { return }
                    if on { self.openSheet = id } else if self.openSheet == id { self.openSheet = nil }
                })
    }

    /// A NavigationRow's title, used as the pushed page's window title.
    func noteTitle(_ title: String, for route: SettingsRoute) {
        if routeTitles.count < 512 || routeTitles[route.id] != nil { routeTitles[route.id] = title }
    }

    func title(for route: SettingsRoute) -> String? {
        if let t = routeTitles[route.id] { return t }
        return legacyPage(route, root: root)?.title
    }

    /// The page a route shows: the module's `settingsDestination`, or (until each module provides its own) the
    /// module's 0.2 page with that id while it runs. The host roots (General, Menu Bar, Permissions, About) have no
    /// sub-pages.
    func destination(_ route: SettingsRoute, root: String) -> AnyView? {
        guard let host else { return nil }
        guard let module = host.modules.first(where: { $0.id.rawValue == root }) else { return nil }
        if let view = module.settingsDestination(route) { return view }
        return legacyPage(route, root: root)?.makeView()
    }

    private func legacyPage(_ route: SettingsRoute, root: String) -> SettingsPage? {
        guard let host, let module = host.modules.first(where: { $0.id.rawValue == root }),
              host.isRunning(module.id) else { return nil }
        return module.settingsPages().first { $0.id == route.id }
    }

    // MARK: Opening

    /// Every open of the window goes through here. `external`: reopen from the Dock or Finder, the
    /// `open-settings` verb (R5-8). `page`: a root, a route ("displays.color") or a 0.2 page id.
    func open(page: String?, external: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if external { focusGuard.externalOpen(now: now) } else { focusGuard.internalOpen() }
        externalOpenPending = focusGuard.externalOpenPending
        if let page, let location = SettingsLocation.resolve(page, roots: rootIDs) {
            restored = true
            go(to: location)
        } else if !restored {
            restored = true
            if let text = UserDefaults.standard.string(forKey: Self.lastRouteKey),
               var location = SettingsLocation(encoded: text, roots: rootIDs) {
                // A route remembered from the interim hubs ("general general.menu") opens its 0.3 root.
                if let id = location.route?.id, let root = SettingsRootID.legacyPages[id], rootIDs.contains(root) {
                    location = SettingsLocation(root: root)
                }
                go(to: location)
            }
        }
    }

    /// Sets the root now and pushes the route on the next main-queue turn (macOS 14 drops a push made in the same
    /// transaction as the root change). A route nothing shows is not pushed.
    func go(to location: SettingsLocation) {
        searchText = ""
        root = location.root
        paths[location.root] = []
        guard let route = location.route else { return }
        revealToken &+= 1
        let token = revealToken
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.revealToken == token, self.destination(route, root: location.root) != nil else { return }
                self.paths[location.root] = [route]
            }
        }
    }

    /// Search result chosen: root now; the route on the next turn (macOS 14 drops a push made with the root
    /// change); the sheet one turn after the push (or at once on a root page); the highlight once the sheet has
    /// appeared (`sheetDidAppear`) or, without a sheet, one turn after the page (code minor 3). A module that is off
    /// shows its off state, so the reveal highlights its "Use …" switch instead and opens nothing.
    func reveal(_ entry: SettingsSearchEntry) {
        revealToken &+= 1
        let token = revealToken
        openSheet = nil
        highlightWork?.cancel()
        highlightedAnchor = nil
        pendingHighlight = nil
        root = entry.root
        paths[entry.root] = []
        let off = moduleIsOff(entry.root)
        let target = off ? SettingsIndex.masterSwitch(root: entry.root, in: ControlRegistry.tables) : entry.anchor
        let fallbacks = off ? [] : SettingsIndex.revealFallbacks(for: entry.anchor, in: ControlRegistry.tables)
        afterTurn(token) { shell in
            var pushed = false
            if !off, let route = entry.route, shell.destination(route, root: entry.root) != nil {
                shell.paths[entry.root] = [route]
                pushed = true
            }
            guard !off, let sheet = entry.sheet else {
                shell.afterTurn(token) { $0.showHighlight(target, fallbacks: fallbacks, token: token) }
                return
            }
            let open: @MainActor (SettingsShell) -> Void = { shell in
                shell.pendingHighlight = PendingHighlight(anchor: target, fallbacks: fallbacks, token: token)
                shell.openSheet = sheet
                shell.watchSheet(sheet, token: token)
            }
            if pushed { shell.afterTurn(token, open) } else { open(shell) }
        }
    }

    /// Called by `AdvancedSheet` (and other sheets) when they appear.
    func sheetDidAppear() {
        guard let pending = pendingHighlight, pending.token == revealToken else { return }
        pendingHighlight = nil
        showHighlight(pending.anchor, fallbacks: pending.fallbacks, token: pending.token)
    }

    /// A reveal waiting for its sheet to appear.
    private struct PendingHighlight {
        let anchor: String?
        let fallbacks: [String]
        let token: Int
    }

    /// `body` on the next main-queue turn, unless a newer reveal or navigation started meanwhile.
    private func afterTurn(_ token: Int, _ body: @escaping @MainActor (SettingsShell) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.revealToken == token else { return }
                body(self)
            }
        }
    }

    /// A sheet that doesn't report its appearance (it isn't an `AdvancedSheet`) is highlighted into after a while;
    /// one that no view presents (its page doesn't bind `sheetBinding`) never appears, so the request is withdrawn
    /// and the highlight goes to the page.
    private func watchSheet(_ sheet: String, token: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.revealToken == token, let pending = self.pendingHighlight,
                      pending.token == token else { return }
                self.pendingHighlight = nil
                if self.openSheet == sheet, self.windowHasSheet?() == false { self.openSheet = nil }
                self.showHighlight(pending.anchor, fallbacks: pending.fallbacks, token: token)
            }
        }
    }

    /// Tints `anchor` for `highlightSeconds`. When its row isn't on screen once the page has scrolled to it (a
    /// subordinate row whose parent is off), the nearest parent row that is gets the highlight instead.
    private func showHighlight(_ anchor: String?, fallbacks: [String], token: Int) {
        guard let anchor else { return }
        highlight(anchor)
        guard !fallbacks.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.revealToken == token, self.highlightedAnchor == anchor else { return }
                let rows = SettingsHighlight.shared
                guard !rows.isVisible(anchor), let parent = fallbacks.first(where: { rows.isVisible($0) }) else { return }
                self.highlight(parent)
            }
        }
    }

    private func highlight(_ anchor: String) {
        highlightWork?.cancel()
        highlightedAnchor = anchor
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.highlightedAnchor == anchor else { return }
                self.highlightedAnchor = nil
            }
        }
        highlightWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.highlightSeconds, execute: item)
    }

    /// A module root whose module is off or turned off by a defaults setting (its page shows the off state).
    private func moduleIsOff(_ root: String) -> Bool {
        guard let host, let id = ModuleID(rawValue: root), host.modules.contains(where: { $0.id == id }) else {
            return false
        }
        return host.disabledByDefaults.contains(id) || !host.modulesStore.value.isEnabled(id)
    }

    private func remember() {
        let location = SettingsLocation(root: root, route: paths[root]?.last)
        UserDefaults.standard.set(location.encoded, forKey: Self.lastRouteKey)
    }

    // MARK: Focus safety (R5-8)

    /// The first real mouse-down inside the Settings window (SettingsWindowHost's local monitor).
    func mouseDown() {
        focusGuard.mouseDown()
        if externalOpenPending { externalOpenPending = false }
    }

    /// Every session-start handler in Settings checks this (Keep Awake and its pull-down, Replace With, Start Again,
    /// the guard toast's re-start); when false the handler only keeps focus. False for 1 s after an external open,
    /// and for key presses while that open is pending. VoiceOver and AX presses carry no key event, so they act.
    func mayStart() -> Bool {
        focusGuard.mayStart(now: ProcessInfo.processInfo.systemUptime,
                            eventIsKeyDown: NSApp.currentEvent?.type == .keyDown)
    }

    // MARK: Search

    /// Every searchable control: the host roots' and each module's entries, derived from the control tables
    /// (R5-13). Static, computed once.
    var searchIndex: [SettingsSearchEntry] {
        if let indexCache { return indexCache }
        var all = SettingsIndex.all(ControlRegistry.tables)
        var seen = Set(all.map(\.id))
        for module in host?.modules ?? [] {
            for e in module.settingsIndex() where seen.insert(e.id).inserted { all.append(e) }
        }
        indexCache = all
        return all
    }

    /// At most 50 ranked matches for the search field.
    var searchResults: [SettingsSearchEntry] {
        Array(SettingsSearch.rank(entries: searchIndex, query: searchText).prefix(50))
    }

    /// "Awake", "Displays › Color" or "Window Switcher › Advanced" for a result row.
    func pageTitle(for entry: SettingsSearchEntry) -> String {
        SettingsIndex.location(of: entry, rootTitle: rootTitle(entry.root),
                               routeTitle: entry.route.flatMap { routeTitles[$0.id] })
    }
}

// MARK: - Window content

/// The Settings window: sidebar (search at the top, 7 roots in 3 groups) and a NavigationStack per root.
struct SettingsShellView: View {
    @ObservedObject var host: ModuleHost
    @ObservedObject var shell: SettingsShell
    @AppStorage("settingsSeenAwake") private var seenAwake = false

    var body: some View {
        let roots = shell.roots()
        NavigationSplitView {
            sidebar(roots)
                .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 240)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(roots)
        }
        .searchable(text: $shell.searchText, placement: .sidebar, prompt: L("Search"))
        .frame(minWidth: SettingsWindowHost.width, maxWidth: SettingsWindowHost.width,
               minHeight: SettingsWindowHost.minimumHeight, maxHeight: .infinity)
        .onAppear { markSeen(shell.root) }
        .onChange(of: shell.root) { _, newRoot in markSeen(newRoot) }
    }

    @ViewBuilder private func sidebar(_ roots: [SettingsRoot]) -> some View {
        if shell.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            List(selection: rootSelection) {
                ForEach(Array(groups(roots).enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group) { root in
                            SidebarRow(root: root, showNew: root.id == SettingsRootID.awake && !seenAwake)
                                .tag(root.id as String?)
                        }
                    }
                }
            }
        } else {
            SettingsSearchView(shell: shell)
        }
    }

    @ViewBuilder private func detail(_ roots: [SettingsRoot]) -> some View {
        if let current = roots.first(where: { $0.id == shell.root }) ?? roots.first {
            NavigationStack(path: shell.pathBinding(for: current.id)) {
                current.makeView()
                    .navigationTitle(current.title)
                    .navigationDestination(for: SettingsRoute.self) { route in
                        (shell.destination(route, root: current.id) ?? AnyView(UnavailablePage()))
                            .navigationTitle(shell.title(for: route) ?? current.title)
                    }
            }
            .id(current.id)
        } else {
            UnavailablePage()
        }
    }

    private var rootSelection: Binding<String?> {
        Binding(get: { shell.root }, set: { if let id = $0 { shell.root = id } })
    }

    private func groups(_ roots: [SettingsRoot]) -> [[SettingsRoot]] {
        var result = SettingsRootID.groups.map { ids in ids.compactMap { id in roots.first { $0.id == id } } }
        let extra = roots.filter { !SettingsRootID.all.contains($0.id) }
        if !extra.isEmpty { result.append(extra) }
        return result.filter { !$0.isEmpty }
    }

    private func markSeen(_ root: String) {
        if root == SettingsRootID.awake && !seenAwake { seenAwake = true }
    }
}

private struct SidebarRow: View {
    let root: SettingsRoot
    let showNew: Bool

    var body: some View {
        Label {
            HStack(spacing: 6) {
                Text(root.title)
                Spacer(minLength: 4)
                if showNew { SettingsBadgeView(.new) }
            }
        } icon: {
            SettingsIcon(root.symbol, tint: root.tint, size: 20)
        }
        .accessibilityLabel(showNew ? L("\(root.title), new") : root.title)
    }
}

/// A route whose page isn't there (its module or feature is off).
struct UnavailablePage: View {
    var body: some View {
        ContentUnavailableView(L("This Page Isn’t Available"), systemImage: "rectangle.dashed",
                               description: Text(L("Turn on the module or feature it belongs to.")))
    }
}

// MARK: - Interim module hub

/// The root page of a module that still shows its 0.2 pages (the `SnapticModule.settingsRoot()` default until the
/// module's own root lands): header with the master switch ("Use Displays"), the off-state highlights or the
/// "Turned off by a defaults setting." state, and one navigation row per 0.2 page while the module runs.
struct LegacyModuleHub: View {
    let moduleID: ModuleID
    let pages: [SettingsPage]

    var body: some View {
        if let host = SettingsShell.shared.host {
            LegacyModuleHubContent(moduleID: moduleID, pages: pages, host: host, modules: host.modulesStore)
        } else {
            UnavailablePage()
        }
    }
}

private struct LegacyModuleHubContent: View {
    let moduleID: ModuleID
    let pages: [SettingsPage]
    @ObservedObject var host: ModuleHost
    @ObservedObject var modules: ConfigStore<ModulesConfig>

    var body: some View {
        let module = host.module(moduleID)
        let style = SettingsShell.sidebarStyle[moduleID.rawValue] ?? (module.symbolName, module.tint)
        let blocked = host.disabledByDefaults.contains(moduleID)
        let enabled = !blocked && modules.value.isEnabled(moduleID)
        SettingsPageScaffold(route: SettingsRoute(moduleID.rawValue)) {
            SettingsPageHeader(module.title, summary: module.summary, symbol: style.symbol, tint: style.tint,
                               isOn: SettingsShell.shared.moduleEnabled(moduleID), switchLabel: L("Use \(module.title)"))
                .disabled(blocked)
            if blocked {
                Section {
                    StatusRow(L("Turned off by a defaults setting."), style: .warning)
                }
            }
            if moduleID == .displays && host.safeMode.isActive {
                Section {
                    StatusRow(L("Safe Mode is on."), style: .warning, actions: [
                        StatusAction(title: L("Leave Safe Mode")) { [weak host] in
                            host?.relauncher.relaunch(reason: "leave safe mode")
                        },
                    ])
                }
            }
            if !enabled {
                FeatureHighlights(module.highlights)
            } else if host.isRunning(moduleID) {
                if case .degraded(let reason) = module.state {
                    Section { StatusRow(reason, style: .warning) }
                }
                if !pages.isEmpty {
                    Section {
                        ForEach(pages) { page in
                            NavigationRow(page.title, symbol: page.symbol, tint: style.tint, route: SettingsRoute(page.id))
                        }
                    }
                }
            } else {
                Section {
                    StatusRow(L("Starting…"))
                }
            }
        }
    }
}
