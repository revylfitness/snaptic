import AppKit
import Combine
import SnapticKit

// Awake's own status item (owner: G; PLAN 0.3 §5.3, §5.5, N11, design M7/M8, code R2-M6). The Kit plan decides
// whether the item exists; this controller only executes it, creating and removing the item ONLY in
// `applyStatusItem` (AwakeModule forwards StatusItemProvider here; StatusMenu.applyPlan calls it in the plan's turn).
// While the item's own menu is open it stays, and `menuDidClose` asks for a new plan. The glyph is a template SF
// Symbol (outline idle, `.fill` active), the optional time is plain `button.title` text in the menu bar font with
// monospaced digits (never a colored attributed title), and the spoken label and tooltip follow every countdown tick.
// 0.3.1: while lid-closed mode is on the glyph carries a short bar and the label says so (B1); Awake's own menu opens
// with the host's leftover rows (B3.4) and, where it carries the shared footer, the Update Available row (E1).

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
        rows.items(style: .compact)
    }

    /// 0.3.1 A4: Awake's tab in the Snaptic menu (the own rows minus Awake Settings…).
    func tabSection() -> [NSMenuItem] {
        rows.items(style: .tab)
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
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular, scale: .medium)
        func glyph(_ name: String) -> NSImage? {
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        }
        // B1: while lid-closed mode is on, the family's lid symbol, or its active glyph with Kit's bar under it.
        let lidOn = active && (rt?.lidMode.isOn ?? false)
        var image: NSImage?
        if lidOn, let lid = config.lidSymbol() { image = glyph(lid) }
        if image == nil { image = glyph(config.symbol(active: active)) }
        if image == nil { image = NSImage(systemSymbolName: AwakeGlyphFamily.cup.idle, accessibilityDescription: nil) }
        if lidOn, config.lidSymbol() == nil, let base = image { image = Self.lidImage(base) }
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
                                                          ruleName: ruleName(governing), holderSummary: rt?.holderSummary,
                                                          lidModeOn: lidOn)
        button.setAccessibilityLabel(label)
        button.toolTip = label
    }

    /// 0.3.1 B1: the family's active glyph with a short bar under it (Kit's ratios of the glyph's height), a template
    /// image at the item's 15 pt, for a family without a lid symbol; visibly not N11's dot on the shared glyph.
    private static func lidImage(_ base: NSImage) -> NSImage {
        let bar = max(1, base.size.height * CGFloat(AwakeGlyphFamily.lidBarHeightRatio))
        let gap = max(1, base.size.height * CGFloat(AwakeGlyphFamily.lidBarGapRatio))
        let size = NSSize(width: base.size.width, height: base.size.height + bar + gap)
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: NSRect(x: 0, y: bar + gap, width: base.size.width, height: base.size.height))
            let width = max(6, (rect.width * 0.6).rounded())
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: ((rect.width - width) / 2).rounded(), y: 0, width: width, height: bar),
                         xRadius: bar / 2, yRadius: bar / 2).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func ruleName(_ governing: AwakeGoverning) -> String? {
        guard case .trigger(let top) = governing, let ctx = context else { return nil }
        return ctx.config.value.triggers.triggers.first { $0.id == top.id }?.displayName(AwakeFormat.text)
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        var items: [NSMenuItem] = []
        let host = context?.host.moduleHost
        // 0.3.1 B3.4: the host's leftover rows head every Snaptic menu (fresh items: one item, one menu).
        if let host {
            let leftover = StatusMenu.leftoverItems(host: host)
            if !leftover.isEmpty { items += leftover + [MenuKit.separator()] }
        }
        // E1: the Update Available row joins the footer this menu carries when the Snaptic item is absent.
        let extras = row.footer ? host.map { StatusMenu.updateItems(host: $0) } ?? [] : []
        items += rows.items(style: .own, footer: row.footer, footerExtras: extras)
        for item in items { menu.addItem(item) }
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
            rt.$lidMode.map { _ in () }.eraseToAnyPublisher(),
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
