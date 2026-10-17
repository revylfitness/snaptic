import AppKit
import SnapticKit

/// Brightness items in each display block: the combined slider (first level by default,
/// snapping to Min HW / Max HW, extended for XDR) and a method submenu.
/// Constructed and registered by BrightnessController in start().
@MainActor final class BrightnessMenuItems: DisplayMenuContributor {
    static let sliderItem = DisplayMenuItemID(rawValue: "c.brightness.slider")
    static let methodItem = DisplayMenuItemID(rawValue: "c.brightness.method")

    weak var context: DisplaysContext?
    private var sliders: [DisplayKey: WeakSliderItem] = [:]

    init(context: DisplaysContext) { self.context = context }

    var descriptors: [DisplayMenuItemDescriptor] {
        [
            DisplayMenuItemDescriptor(id: Self.sliderItem, title: L("Brightness slider"), slot: .display,
                                      defaultVisibility: .visible),
            DisplayMenuItemDescriptor(id: Self.methodItem, title: L("Brightness method"), slot: .display,
                                      defaultVisibility: .inSubmenu),
        ]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let context, context.runtime.isEffective(.brightness), let value = context.brightness.value(for: display.key)
        else { return [] }
        let key = display.key
        var result: [(DisplayMenuItemID, NSMenuItem)] = []
        let range = context.brightness.range(for: key)
        let slider = MenuSliderItem(title: L("Brightness") + " — " + TextSanitizer.clean(display.name, maxScalars: 64),
                                    symbol: range.upperBound > 1 ? "sun.max.circle" : "sun.max",
                                    value: value) { [weak self] newValue in
            guard let self, let ctx = self.context else { return }
            let snapped = ctx.brightness.scale(for: key)?.snapped(newValue) ?? newValue
            ctx.brightness.set(snapped, for: key, source: .user)
        }
        slider.range = range
        slider.setValue(value)
        sliders[key] = WeakSliderItem(slider)
        result.append((Self.sliderItem, slider))

        let methods = context.brightness.methods(for: key)
        if methods.count > 1 {
            let item = NSMenuItem(title: L("Brightness Method"), action: nil, keyEquivalent: "")
            let menu = NSMenu(title: L("Brightness Method"))
            let chosen = context.config.value.perDisplay[key]?.brightness.method
            let automatic = CMenu.item(L("Automatic"), on: chosen == nil) { [weak self] in
                guard let ctx = self?.context else { return }
                PerDisplayEdit.update(ctx, key) { $0.brightness.method = nil }
            }
            menu.addItem(automatic)
            menu.addItem(.separator())
            for method in methods {
                let entry = CMenu.item(method.title, on: chosen == method) { [weak self] in
                    guard let ctx = self?.context else { return }
                    if method == .gamma { ctx.gamma.resetGiveUp(key) }
                    PerDisplayEdit.update(ctx, key) { $0.brightness.method = method }
                }
                menu.addItem(entry)
            }
            item.submenu = menu
            result.append((Self.methodItem, item))
        }
        return result
    }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] { [] }

    /// Updates an open menu's slider in place.
    func update(_ key: DisplayKey, value: Double) {
        guard let slider = sliders[key]?.item else {
            sliders[key] = nil
            return
        }
        if let range = context?.brightness.range(for: key), slider.range != range { slider.range = range }
        slider.setValue(value)
    }
}

/// Weak holder so stale menus don't keep sliders alive.
struct WeakSliderItem {
    weak var item: MenuSliderItem?
    init(_ item: MenuSliderItem) { self.item = item }
}

/// Menu item helpers for C's contributors (actions capture DisplayKeys, never display ids).
enum CMenu {
    @MainActor static func item(_ title: String, on: Bool = false, enabled: Bool = true,
                                _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        item.state = on ? .on : .off
        item.isEnabled = enabled
        return item
    }

    @MainActor static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach { menu.addItem($0) }
        item.submenu = menu
        return item
    }

    @MainActor static func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
