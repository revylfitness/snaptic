import AppKit
import SnapticKit

/// Hidden Icons' own status items (lead; PLAN 0.4 §4.1, §4.3, §4.13; A1): the arrow, `|` and `⋮`. It implements
/// the engine's `IconsItemsPort`; Kit decides the look (`IconsItemsLook`) and the seeding (`IconsSeeding`).
///
/// - Nothing is created before `start(engine:alwaysHidden:dividers:)`: `IconsModule.init` and a stopped module own no
///   item (`liveCount`, checked by `--selftest-launch`).
/// - `behavior = []`, so no item can be ⌘-dragged out of the bar (P-9). `isVisible` is forced on at every start for
///   the arrow, for `⋮` while Always Hidden is on and for `|` on Length (Y-10); a later `false` that isn't ours
///   (System Settings › Menu Bar, a stale `Visible` key) is reported through `onVisibilityLost` (G-4).
/// - Clicks arrive on mouse-up only and resolve through `IconsClicks.action(for:)`. The menu opens with
///   `popUp(positioning:at:in:)` at the button's bottom edge; nothing here calls `performClick` (Hidden Bar's
///   recursion crash).
/// - Frames are window frames in AppKit's global space (`AXInventory` converts Accessibility's y to match).
/// - The port is used on the main actor only (`@preconcurrency`: an off-main call traps rather than races).
@MainActor final class IconsItems: NSObject, @preconcurrency IconsItemsPort, ControlDeclaring {
    typealias Controls = IconsItemsControls

    /// Live Hidden Icons status items in this process (selftest: zero after `IconsModule.init`).
    private(set) static var liveCount = 0
    /// The running instance on Length, for P-10's seeding of other Snaptic items.
    private static weak var seedingOwner: IconsItems?

    /// Toggle or toggle-all from a click, a VoiceOver press (no event) or the keyboard.
    var onClick: ((IconsClickAction) -> Void)?
    /// The arrow's menu, built fresh on each open (A6). Nil: a menu click does nothing.
    var menuProvider: (() -> NSMenu?)?
    /// An item's `isVisible` went false without Snaptic asking (G-4).
    var onVisibilityLost: ((IconsItemRole) -> Void)?
    /// The menu bar's direction changed (`NSLocale.currentLocaleDidChangeNotification`).
    var onDirectionChange: ((Bool) -> Void)?

    private let defaults: UserDefaults
    private var items: [IconsItemRole: NSStatusItem] = [:]
    private var observations: [IconsItemRole: NSKeyValueObservation] = [:]
    private var writingVisibility = false
    private var localeToken: NSObjectProtocol?
    private(set) var engine: IconsEngineKind?
    private(set) var rightToLeft = IconsItems.menuBarIsRightToLeft()
    private var collapsed = false
    private var hiddenCount: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    var isStarted: Bool { engine != nil }

    // MARK: Direction (Y-6)

    /// The menu bar's direction from the first preferred language, not the app's (English-only) layout. Geometry
    /// isn't used: on 14–26 it would need Accessibility.
    static func menuBarIsRightToLeft(_ languages: [String] = Locale.preferredLanguages) -> Bool {
        guard let first = languages.first else { return false }
        return Locale.Language(identifier: first).characterDirection == .rightToLeft
    }

    // MARK: Lifetime

    /// Creates the items for `engine`. `|` starts at 0 on Native (the arrow is the boundary) and at its expanded
    /// length on Length; the engine sets every later length. Idempotent while started.
    func start(engine: IconsEngineKind, alwaysHidden: Bool, dividers: Bool) {
        guard self.engine == nil else { return }
        self.engine = engine
        rightToLeft = Self.menuBarIsRightToLeft()
        seedFirstRun()
        create(.toggle, length: NSStatusItem.variableLength)
        create(.separator, length: engine == .native ? 0 : (dividers ? IconsItemsLook.dividerLength : 0))
        if alwaysHidden { createAlwaysHidden() }
        if engine == .length { Self.seedingOwner = self }
        localeToken = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.localeChanged() }
        }
        render()
    }

    /// Removes every item (their positions stay remembered under their autosave names).
    func stop() {
        guard engine != nil else { return }
        if let localeToken { NotificationCenter.default.removeObserver(localeToken) }
        localeToken = nil
        for role in IconsItemRole.allCases { remove(role) }
        if Self.seedingOwner === self { Self.seedingOwner = nil }
        engine = nil
    }

    /// Always Hidden on: `⋮` at 20 pt (the caller expands if needed and shows the arrange hint, Y-4). Off: `⋮` and
    /// its remembered position go.
    func setAlwaysHidden(_ on: Bool) {
        guard engine != nil else { return }
        if on {
            guard items[.alwaysHidden] == nil else { return }
            createAlwaysHidden()
            render()
        } else if items[.alwaysHidden] != nil {
            remove(.alwaysHidden)
            let name = IconsItemRole.alwaysHidden.autosaveName
            defaults.removeObject(forKey: IconsSeeding.key(name))
            defaults.removeObject(forKey: "NSStatusItem Visible " + name)
        }
    }

    /// [Show Arrow] / [Show Divider] (G-4).
    func show(_ role: IconsItemRole) {
        guard let item = items[role] else { return }
        setVisible(item, true)
    }

    /// The arrow's glyph and spoken value for the state that actually holds (a refused collapse passes false).
    func update(collapsed: Bool, hiddenCount: Int?) {
        self.collapsed = collapsed
        self.hiddenCount = hiddenCount
        render()
    }

    // MARK: IconsItemsPort

    func frame(of role: IconsItemRole) -> IconsRect? {
        guard let window = items[role]?.button?.window else { return nil }
        let f = window.frame
        return IconsRect(x: f.origin.x, y: f.origin.y, width: f.width, height: f.height)
    }

    func setLength(_ length: Double, for role: IconsItemRole) {
        guard role != .toggle, let item = items[role], length.isFinite, length >= 0 else { return }
        item.length = CGFloat(length)
    }

    func length(of role: IconsItemRole) -> Double? {
        items[role].map { Double($0.length) }
    }

    func isVisible(_ role: IconsItemRole) -> Bool {
        items[role]?.isVisible ?? false
    }

    // MARK: Seeding (§4.1, P-10)

    private func position(_ autosaveName: String) -> Double? {
        (defaults.object(forKey: IconsSeeding.key(autosaveName)) as? NSNumber)?.doubleValue
    }

    /// Before the first creation: the arrow and `|` just left of Snaptic's existing items.
    private func seedFirstRun() {
        let snaptic = [StatusMenu.sharedAutosaveName, IndicatorController.autosaveName]
            + ModuleID.allCases.filter { $0 != .hiddenIcons }.map(StatusMenu.autosaveName)
        let seeded = IconsSeeding.firstRun(snapticPositions: snaptic.compactMap(position),
                                           arrow: position(IconsItemRole.toggle.autosaveName),
                                           separator: position(IconsItemRole.separator.autosaveName))
        for (role, at) in seeded { defaults.set(at, forKey: IconsSeeding.key(role.autosaveName)) }
    }

    /// P-10: StatusMenu and Awake's indicator call this before they first create an item. Only while Hidden Icons
    /// runs on Length, and only for an item never placed before.
    static func seedOwnItem(autosaveName: String) {
        guard let owner = seedingOwner, owner.engine == .length else { return }
        guard let at = IconsSeeding.ownItem(arrow: owner.position(IconsItemRole.toggle.autosaveName),
                                            current: owner.position(autosaveName)) else { return }
        owner.defaults.set(at, forKey: IconsSeeding.key(autosaveName))
    }

    // MARK: Items

    private func createAlwaysHidden() {
        let name = IconsItemRole.alwaysHidden.autosaveName
        if let at = IconsSeeding.alwaysHidden(separator: position(IconsItemRole.separator.autosaveName),
                                              current: position(name)) {
            defaults.set(at, forKey: IconsSeeding.key(name))
        }
        create(.alwaysHidden, length: IconsItemsLook.dividerLength)
    }

    private func create(_ role: IconsItemRole, length: CGFloat) {
        guard items[role] == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: length)
        Self.liveCount += 1
        item.autosaveName = role.autosaveName
        item.behavior = []
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp, .otherMouseUp])
            button.identifier = NSUserInterfaceItemIdentifier(Self.controlID(role))
            button.setAccessibilityLabel(IconsItemsLook.accessibilityLabel(role))
            button.setAccessibilityHelp(IconsItemsLook.help(role))
            button.toolTip = IconsItemsLook.help(role)
            if let title = IconsItemsLook.title(role) {
                button.title = title
                button.font = NSFont.menuBarFont(ofSize: 0)
                button.alphaValue = 1
            }
        }
        items[role] = item
        // Y-10: the autosave name can restore `false` from an earlier session.
        if role == .toggle || role == .alwaysHidden || engine == .length { setVisible(item, true) }
        observations[role] = item.observe(\.isVisible, options: [.new]) { [weak self] item, _ in
            let visible = item.isVisible
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.visibilityChanged(role, visible) } }
        }
    }

    private func remove(_ role: IconsItemRole) {
        observations[role]?.invalidate()
        observations[role] = nil
        guard let item = items[role] else { return }
        writingVisibility = true
        NSStatusBar.system.removeStatusItem(item)
        writingVisibility = false
        items[role] = nil
        Self.liveCount -= 1
    }

    private func setVisible(_ item: NSStatusItem, _ visible: Bool) {
        writingVisibility = true
        item.isVisible = visible
        writingVisibility = false
    }

    private func visibilityChanged(_ role: IconsItemRole, _ visible: Bool) {
        guard !visible, !writingVisibility, items[role] != nil else { return }
        // `|` on Native is zero-length and not forced; its visibility doesn't matter there.
        if role == .separator, engine == .native { return }
        onVisibilityLost?(role)
    }

    private static func controlID(_ role: IconsItemRole) -> String {
        switch role {
        case .toggle: ControlID("menu.iconItems.arrow").rawValue
        case .separator: ControlID("menu.iconItems.divider").rawValue
        case .alwaysHidden: ControlID("menu.iconItems.alwaysHiddenDivider").rawValue
        }
    }

    private func localeChanged() {
        let rtl = Self.menuBarIsRightToLeft()
        guard rtl != rightToLeft else { return }
        rightToLeft = rtl
        render()
        onDirectionChange?(rtl)
    }

    private func render() {
        guard let button = items[.toggle]?.button else { return }
        let symbol = IconsItemsLook.arrowSymbol(collapsed: collapsed, rightToLeft: rightToLeft)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.setAccessibilityValue(IconsItemsLook.arrowValue(collapsed: collapsed, hiddenCount: hiddenCount))
    }

    // MARK: Clicks (§4.3)

    /// The click as Kit sees it: nil for anything but a mouse-up on the item (a VoiceOver press, the keyboard).
    private static func clickEvent(_ event: NSEvent?) -> IconsClickEvent? {
        guard let event else { return nil }
        let button: IconsMouseButton
        switch event.type {
        case .leftMouseUp: button = .left
        case .rightMouseUp: button = .right
        case .otherMouseUp: button = .other
        default: return nil
        }
        let flags = event.modifierFlags
        return IconsClickEvent(button: button, option: flags.contains(.option), control: flags.contains(.control))
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let role = items.first(where: { $0.value.button === sender })?.key else { return }
        let action = IconsClicks.action(for: Self.clickEvent(NSApp.currentEvent))
        // `|` and `⋮` open the arrow's menu on any click (on Native `|` is zero-length and can't be clicked).
        if role != .toggle || action == .menu {
            openMenu(from: sender)
        } else {
            onClick?(action)
        }
    }

    private func openMenu(from button: NSStatusBarButton) {
        guard let menu = menuProvider?() else { return }
        let y = button.isFlipped ? button.bounds.maxY + 4 : button.bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: y), in: button)
    }
}
