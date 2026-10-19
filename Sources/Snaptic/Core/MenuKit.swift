import AppKit
import SnapticKit

/// The one menu item factory (PLAN 0.3 §5.1, R5-13). Every Snaptic menu item is built here: one header style
/// (`NSMenuItem.sectionHeader`), native items for everything a keyboard or VoiceOver user needs, and AppKit-only
/// custom rows (`MenuSliderRow`, `MenuSwitchHeaderView`, 0.3.1's `MenuTabBarView`; never a hosting view, lint L13)
/// for sliders, switch headers and the Snaptic menu's tabs. Each item carries its `ControlID` as its `identifier`, so the control a row belongs to is visible to
/// accessibility tools and UI tests (lint L15 checks the literal against the caller's control table).
///
/// Item rules (§5.1): Title Case; an ellipsis only when more input follows; toggles use a checkmark or a changing
/// title; submenus one level deep; symbols on every item of a section or on none; "Settings…" then "Quit" last.
@MainActor enum MenuKit {
    /// Width of menus that contain custom rows.
    static let width: CGFloat = 300
    /// Leading and trailing inset of the custom rows' content (aligned with native item text; HW-15 measures it).
    static let rowInset: CGFloat = 14
    /// The selection highlight of a custom row: inset from the menu edges and corner radius (macOS 14–27 menus).
    static let highlightInset: CGFloat = 5
    static let highlightRadius: CGFloat = 4
    /// Point size of item symbols (a 16 pt template image in the image column).
    static let symbolPointSize: CGFloat = 13

    // MARK: Native items

    /// `NSMenuItem.sectionHeader(title:)`: the ONLY header style.
    static func header(_ title: String, control: ControlID? = nil) -> NSMenuItem {
        let item = NSMenuItem.sectionHeader(title: title)
        tag(item, control)
        return item
    }

    static func separator() -> NSMenuItem { NSMenuItem.separator() }

    static func action(_ title: String, symbol: String? = nil, key: String = "",
                       modifiers: NSEvent.ModifierFlags = .command, enabled: Bool = true,
                       control: ControlID? = nil,
                       _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = MenuKitItem(title: title, key: key, handler: handler)
        // Without a key equivalent the mask only matters for ⌥ alternates, which need the primary at "no modifiers".
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.isEnabled = enabled
        item.image = symbol.flatMap { symbolImage($0) }
        tag(item, control)
        return item
    }

    /// A checkmark toggle.
    static func toggle(_ title: String, isOn: Bool, symbol: String? = nil, enabled: Bool = true,
                       control: ControlID? = nil,
                       _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = action(title, symbol: symbol, enabled: enabled, control: control, handler)
        item.state = isOn ? .on : .off
        return item
    }

    /// The ⌥ alternate of `item`; it must directly follow `item` in the menu.
    static func alternate(of item: NSMenuItem, title: String, control: ControlID? = nil,
                          _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let alt = MenuKitItem(title: title, key: item.keyEquivalent, handler: handler)
        alt.keyEquivalentModifierMask = item.keyEquivalentModifierMask.union(.option)
        alt.isAlternate = true
        alt.isEnabled = item.isEnabled
        alt.image = item.image
        tag(alt, control)
        return alt
    }

    /// One level only: a child with its own submenu is a programming error (asserted in debug, dropped in release
    /// so a stray nested submenu never reaches the user).
    static func submenu(_ title: String, symbol: String? = nil, enabled: Bool = true, control: ControlID? = nil,
                        _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        assert(items.allSatisfy { $0.submenu == nil }, "MenuKit submenus are one level deep (§5.1)")
        for child in items where child.submenu == nil { menu.addItem(child) }
        item.submenu = menu
        item.isEnabled = enabled
        item.image = symbol.flatMap { symbolImage($0) }
        tag(item, control)
        return item
    }

    /// A disabled information row ("Safe Mode Is On").
    static func status(_ text: String, symbol: String? = nil, control: ControlID? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.image = symbol.flatMap { symbolImage($0) }
        tag(item, control)
        return item
    }

    /// A display row with its submenu; `dimmed` for a disconnected display (its submenu still offers Connect).
    static func device(_ title: String, symbol: String, dimmed: Bool = false, submenu: [NSMenuItem],
                       control: ControlID? = nil) -> NSMenuItem {
        let item = self.submenu(title, symbol: symbol, control: control, submenu)
        if dimmed {
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.disabledControlTextColor,
            ])
        }
        return item
    }

    /// Secondary line under an item: `NSMenuItem.subtitle` on 14.4+. On 14.0–14.3 the subtitle is appended to the
    /// title ("Desk dock — Active") instead of a separate row, because an ⌥ alternate must directly follow its
    /// primary item.
    static func withSubtitle(_ item: NSMenuItem, _ subtitle: String?) -> NSMenuItem {
        guard let subtitle, !subtitle.isEmpty else { return item }
        if #available(macOS 14.4, *) {
            item.subtitle = subtitle
        } else {
            item.title = item.title + " — " + subtitle
        }
        return item
    }

    /// "⌘,". The title names the scope ("Snaptic Settings…", "Displays Settings…").
    static func settings(_ title: String, control: ControlID? = nil, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        action(title, key: ",", control: control, handler)
    }

    /// "Quit Snaptic" ⌘Q.
    static func quit(control: ControlID? = nil) -> NSMenuItem {
        action(L("Quit Snaptic"), key: "q", control: control) { NSApp.terminate(nil) }
    }

    // MARK: Custom rows

    /// AppKit view row (`MenuSwitchHeaderView`): bold title + small switch + up to two secondary lines. Mouse only:
    /// the same action always exists as a native item (parity M4). Update it in place with `update(_:isOn:detail:)`.
    static func switchHeader(_ title: String, isOn: Bool, detail: [String], control: ControlID? = nil,
                             onToggle: @escaping @MainActor (Bool) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.view = MenuSwitchHeaderView(title: title, isOn: isOn, detail: detail, onToggle: onToggle)
        tag(item, control)
        return item
    }

    /// Updates a switch header built by `switchHeader` while its menu is open. The height stays as it was when the
    /// menu opened; returns false when the line count changed, so the caller rebuilds the menu after it closes.
    @discardableResult
    static func update(_ item: NSMenuItem, isOn: Bool, detail: [String]) -> Bool {
        guard let view = item.view as? MenuSwitchHeaderView else { return true }
        return view.update(isOn: isOn, detail: detail)
    }

    /// 0.3.1 A2: the Snaptic menu's tab bar (`MenuTabBarView`, 28 pt), one segment per label in order. `attention` and
    /// `active` are segment indices (the attention mark; ", on" while Awake governs); `width` is the menu's minimum
    /// width. `onSelect` runs synchronously in the control's action with the chosen index. The item has no title, so
    /// type-select only reaches the visible tab's items; it stays enabled and draws no highlight (HW-24, HW-25 decide
    /// whether it becomes `isEnabled = false`). Mouse and VoiceOver only: the Show … Tab items are the keyboard path.
    static func tabBar(labels: [MenuTabLabel], selected: Int, attention: Set<Int>, active: Int?,
                       width: CGFloat = MenuKit.width, control: ControlID? = nil,
                       onSelect: @escaping @MainActor (Int) -> Void) -> NSMenuItem {
        let segments = labels.enumerated().map { index, label in
            MenuTabSegment(label: label,
                           toolTip: MenuTabs.segmentToolTip(title: label.title,
                                                            keyIndex: index < MenuTabs.maxKeyIndex ? index + 1 : nil,
                                                            active: index == active),
                           accessibilityLabel: MenuTabs.segmentLabel(title: label.title, active: index == active,
                                                                     attention: attention.contains(index)),
                           attention: attention.contains(index))
        }
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.view = MenuTabBarView(segments: segments, selected: selected, width: width,
                                   help: MenuTabs.barHelp(tabCount: labels.count), onSelect: onSelect)
        tag(item, control)
        return item
    }

    /// Call from `menu(_:willHighlight:)` of a menu that holds custom rows: the rows draw the system highlight
    /// for arrow-key navigation (they also check their item when drawn).
    static func menu(_ menu: NSMenu, willHighlight highlighted: NSMenuItem?) {
        for item in menu.items {
            (item.view as? MenuRowView)?.setHighlighted(item === highlighted && item.isEnabled)
        }
    }

    /// Whether a menu holds custom rows (then it is at least `width` wide).
    static func hasCustomRows(_ menu: NSMenu) -> Bool { menu.items.contains { $0.view != nil } }

    // MARK: Helpers

    /// The control an item was built for.
    static func control(of item: NSMenuItem) -> ControlID? {
        item.identifier.map { ControlID(rawValue: $0.rawValue) }
    }

    /// A template SF Symbol for the image column; nil for an unknown name.
    static func symbolImage(_ name: String) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let image = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .regular))
            ?? base
        image.isTemplate = true
        return image
    }

    private static func tag(_ item: NSMenuItem, _ control: ControlID?) {
        guard let control else { return }
        item.identifier = NSUserInterfaceItemIdentifier(control.rawValue)
    }
}

/// A menu item that runs a closure.
@MainActor private final class MenuKitItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, key: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) {
        handler = {}
        super.init(coder: coder)
    }

    @objc private func fire() { handler() }
}

/// Base of the AppKit view rows (§5.1 custom-row behavior): the system selection highlight is drawn behind the
/// content from the enclosing item's highlight state, so arrow-key navigation shows where the user is. Rows are
/// never clickable themselves; their controls take the mouse.
@MainActor class MenuRowView: NSView {
    private let highlight = NSVisualEffectView()
    private(set) var isHighlighted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setUpHighlight()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpHighlight()
    }

    private func setUpHighlight() {
        autoresizingMask = [.width]
        highlight.material = .selection
        highlight.state = .active
        highlight.isEmphasized = true
        highlight.blendingMode = .behindWindow
        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = MenuKit.highlightRadius
        highlight.layer?.masksToBounds = true
        highlight.isHidden = true
        highlight.autoresizingMask = [.width, .height]
        highlight.frame = bounds.insetBy(dx: MenuKit.highlightInset, dy: 0)
        addSubview(highlight)
    }

    /// Sets the highlight (from `MenuKit.menu(_:willHighlight:)` or the item's state at draw time).
    func setHighlighted(_ on: Bool) {
        guard on != isHighlighted else { return }
        isHighlighted = on
        highlight.isHidden = !on
        highlightDidChange(on)
    }

    /// Subclasses switch their text to `selectedMenuItemTextColor` while highlighted.
    func highlightDidChange(_ highlighted: Bool) {}

    override func viewWillDraw() {
        super.viewWillDraw()
        if let item = enclosingMenuItem { setHighlighted(item.isHighlighted && item.isEnabled) }
    }

    override func layout() {
        super.layout()
        highlight.frame = bounds.insetBy(dx: MenuKit.highlightInset, dy: 0)
    }

    /// Text color for the current highlight state.
    func textColor(_ normal: NSColor) -> NSColor { isHighlighted ? .selectedMenuItemTextColor : normal }
}
