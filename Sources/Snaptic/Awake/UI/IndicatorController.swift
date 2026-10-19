import AppKit
import Combine
import SnapticKit

// Awake's own status item (owner: G; PLAN 0.3 §5.3, §5.5, N11, design M7/M8, code R2-M6). The Kit plan decides
// whether the item exists; this controller only executes it, creating and removing the item ONLY in
// `applyStatusItem` (AwakeModule forwards StatusItemProvider here; StatusMenu.applyPlan calls it in the plan's turn).
// While the item's own menu is open it stays, and `menuDidClose` asks for a new plan. The glyph is a template SF
// Symbol (outline idle, `.fill` active), the optional time is plain `button.title` text in the menu bar font with
// monospaced digits (never a colored attributed title), and the spoken label and tooltip follow every countdown tick.

@MainActor final class IndicatorController: NSObject, AwakeFeatureController, NSMenuDelegate {
    typealias Controls = IndicatorControllerControls

    static var id: AwakeControllerID { .indicator }
    static let autosaveName = "SnapticAwake"

    weak var context: AwakeContext?
    /// nil while the item doesn't exist.
    private(set) var statusItem: NSStatusItem?

    /// The rows of both menus (own and compact section).
    let rows = AwakeMenuRows()
    private var row = CustomItemRow(exists: false, presence: .ownIconWhenActive, footer: false, recentNotices: false)
    private var menuOpen = false
    /// Our own writes to `isVisible` (and teardown) are not the user's ⌘-drag.
    private var writingVisibility = false
    private var visibilityObservation: NSKeyValueObservation?
    private var sinks: [AnyCancellable] = []
    private var configSink: AnyCancellable?

    override init() { super.init() }

    // MARK: StatusItemProvider (via AwakeModule)

    func applyStatusItem(_ row: CustomItemRow) {
        self.row = row
        if row.exists {
            if statusItem == nil { createItem() }
            render()
        } else if statusItem != nil, !menuOpen {
            removeItem()
        }
        context?.runtime.indicatorVisible = statusItem?.isVisible ?? false
    }

    /// The compact section for the Snaptic menu (§5.4): AwakeModule.menuSection() returns it.
    func compactSection() -> [NSMenuItem] {
        rows.items(compact: true)
    }

    private func createItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.autosaveName
        item.behavior = .removalAllowed
        writingVisibility = true
        // The autosave name restores `false` after a removal (code minor 5).
        item.isVisible = true
        writingVisibility = false
        let menu = NSMenu(title: L("Awake"))
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        if let button = item.button {
            button.imagePosition = .imageLeading
            button.identifier = NSUserInterfaceItemIdentifier(ControlID("menu.awake.item.button").rawValue)
        }
        statusItem = item
        visibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] item, _ in
            let visible = item.isVisible
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.visibilityChanged(visible) } }
        }
    }

    private func removeItem() {
        guard let item = statusItem else { return }
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        writingVisibility = true
        NSStatusBar.system.removeStatusItem(item)
        writingVisibility = false
        statusItem = nil
    }

    /// A user ⌘-drag removal: Awake moves into the Snaptic menu and says so (§5.3).
    private func visibilityChanged(_ visible: Bool) {
        context?.runtime.indicatorVisible = visible
        guard !visible, !writingVisibility, statusItem != nil, let ctx = context else { return }
        ctx.host.setPresence(.inSnapticMenu)
        ctx.host.toasts.show(L("Awake’s menu bar icon was removed. Awake is now in the Snaptic menu; change this in Settings › Menu Bar."))
    }

    // MARK: Look

    private func render() {
        guard let button = statusItem?.button else { return }
        let rt = context?.runtime
        let governing = rt?.governing ?? .inactive
        let config = context?.config.value.indicator ?? AwakeIndicatorConfig()
        let active = governing.isActive
        let symbol = config.symbol(active: active)
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular, scale: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
            ?? NSImage(systemSymbolName: AwakeGlyphFamily.cup.idle, accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image

        let now = AwakeModule.clockNow()
        var endClock: String?
        var appName: String?
        if case .manual(let s) = governing {
            endClock = AwakeClock.endWall(s, now: now).map { AwakeFormat.clock($0) }
            if case .whileApp(let b, _) = s.kind { appName = AwakeFormat.appName(b) }
        }
        let title = AwakeIndicatorText.title(style: config.style, governing: governing, remaining: rt?.remaining,
                                             endClock: endClock)
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        button.title = title.map { " " + $0 } ?? ""
        let label = AwakeIndicatorText.accessibilityLabel(governing: governing, remaining: rt?.remaining, appName: appName,
                                                          ruleName: ruleName(governing), holderSummary: rt?.holderSummary)
        button.setAccessibilityLabel(label)
        button.toolTip = label
    }

    private func ruleName(_ governing: AwakeGoverning) -> String? {
        guard case .trigger(let top) = governing, let ctx = context else { return nil }
        return ctx.config.value.triggers.triggers.first { $0.id == top.id }?.displayName(AwakeFormat.text)
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in rows.items(compact: false, footer: row.footer) { menu.addItem(item) }
        menu.minimumWidth = MenuKit.hasCustomRows(menu) ? MenuKit.width : 0
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        context?.sessions.arbitrate()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        // The plan may have dropped the item while its menu was open: re-plan, so it goes away in applyStatusItem.
        context?.host.requestStatusPlan()
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        MenuKit.menu(menu, willHighlight: item)
    }

    // MARK: AwakeFeatureController

    func availability(of feature: AwakeFeature, context: AwakeContext) -> FeatureAvailability { .available }

    func start(_ context: AwakeContext, lifetime: Lifetime, effective: Set<AwakeFeature>) {
        guard sinks.isEmpty else { return }   // idempotent
        self.context = context
        rows.attach(context)
        let rt = context.runtime
        let changes: [AnyPublisher<Void, Never>] = [
            rt.$governing.map { _ in () }.eraseToAnyPublisher(),
            rt.$remaining.map { _ in () }.eraseToAnyPublisher(),
            rt.$holderSummary.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.render() } }
            .store(in: &sinks)
        configSink = context.config.$value
            .map(\.indicator)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.render() } }
        render()
    }

    func effectiveFeaturesDidChange(_ effective: Set<AwakeFeature>) {}

    func configDidChange(from old: AwakeConfig, to new: AwakeConfig) {
        if old.indicator != new.indicator { render() }
    }

    /// The item itself stays until the next plan (applyStatusItem) removes it.
    func stop() {
        sinks.removeAll()
        configSink = nil
        rows.attach(nil)
        context = nil
        render()
    }
}
