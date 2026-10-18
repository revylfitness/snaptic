import AppKit
import SnapticKit

// Stub (owner: M). Hand-written by the lead in step 0 from PLAN 0.3 §5.1 + R5-13 (kind S): plain native items with
// the contract signatures. M builds the real factory (one header style, AppKit-only custom rows) in step 1.

/// The menu item factory: every item built through it passes its `ControlID("…")` literal (lint L15).
@MainActor enum MenuKit {
    /// Menus containing custom rows.
    static let width: CGFloat = 300

    /// NSMenuItem.sectionHeader(title:) — the ONLY header style.
    static func header(_ title: String, control: ControlID? = nil) -> NSMenuItem {
        NSMenuItem.sectionHeader(title: title)
    }

    static func action(_ title: String, symbol: String? = nil, key: String = "",
                       modifiers: NSEvent.ModifierFlags = .command, enabled: Bool = true,
                       control: ControlID? = nil,
                       _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = MenuKitItem(title: title, key: key, handler: handler)
        item.keyEquivalentModifierMask = modifiers
        item.isEnabled = enabled
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    /// Checkmark.
    static func toggle(_ title: String, isOn: Bool, symbol: String? = nil, enabled: Bool = true,
                       control: ControlID? = nil,
                       _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = action(title, symbol: symbol, enabled: enabled, control: control, handler)
        item.state = isOn ? .on : .off
        return item
    }

    /// ⌥, isAlternate.
    static func alternate(of item: NSMenuItem, title: String, control: ControlID? = nil,
                          _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let alt = MenuKitItem(title: title, key: item.keyEquivalent, handler: handler)
        alt.keyEquivalentModifierMask = item.keyEquivalentModifierMask.union(.option)
        alt.isAlternate = true
        return alt
    }

    /// One level only (asserted in debug by M).
    static func submenu(_ title: String, symbol: String? = nil, enabled: Bool = true, control: ControlID? = nil,
                        _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for child in items { menu.addItem(child) }
        item.submenu = menu
        item.isEnabled = enabled
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    /// Disabled info row.
    static func status(_ text: String, symbol: String? = nil, control: ControlID? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    static func device(_ title: String, symbol: String, dimmed: Bool = false, submenu: [NSMenuItem],
                       control: ControlID? = nil) -> NSMenuItem {
        let item = self.submenu(title, symbol: symbol, control: control, submenu)
        if dimmed { item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.disabledControlTextColor]) }
        return item
    }

    /// Secondary line: `NSMenuItem.subtitle` on 14.4+; appended to the title on 14.0–14.3.
    static func withSubtitle(_ item: NSMenuItem, _ subtitle: String?) -> NSMenuItem {
        guard let subtitle, !subtitle.isEmpty else { return item }
        if #available(macOS 14.4, *) {
            item.subtitle = subtitle
        } else {
            item.title = item.title + " — " + subtitle
        }
        return item
    }

    /// AppKit view row (MenuSwitchHeaderView) in M's build. Stub: a native checkmark item.
    static func switchHeader(_ title: String, isOn: Bool, detail: [String], control: ControlID? = nil,
                             onToggle: @escaping @MainActor (Bool) -> Void) -> NSMenuItem {
        toggle(title, isOn: isOn, control: control) { onToggle(!isOn) }
    }

    /// ⌘,
    static func settings(_ title: String, control: ControlID? = nil, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        action(title, key: ",", control: control, handler)
    }

    /// "Quit Snaptic" ⌘Q.
    static func quit(control: ControlID? = nil) -> NSMenuItem {
        action(L("Quit Snaptic"), key: "q", control: control) { NSApp.terminate(nil) }
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
