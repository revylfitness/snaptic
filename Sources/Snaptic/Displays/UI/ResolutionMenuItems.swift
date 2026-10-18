import AppKit
import SnapticKit

/// Constructed and registered by its controller in start(). Reads caches only (≤ 50 ms
/// rebuilds); item actions capture `DisplayKey` and re-resolve on click (R3C §5.6).
@MainActor final class ResolutionMenuItems: DisplayMenuContributor {
    weak var context: DisplaysContext?
    weak var controller: ResolutionController?
    private var sliderApply: DispatchWorkItem?

    init(context: DisplaysContext) { self.context = context }

    var descriptors: [DisplayMenuItemDescriptor] {
        var list = [
            DisplayMenuItemDescriptor(id: .dResolutionSlider, title: L("Resolution slider"), slot: .display, defaultVisibility: .inSubmenu),
            DisplayMenuItemDescriptor(id: .dResolutionMenu, title: L("Resolution modes"), slot: .display, defaultVisibility: .inSubmenu),
        ]
        if controller?.effective.contains(.scaleMatch) == true {
            list.append(DisplayMenuItemDescriptor(id: .dMatchUI, title: L("Match UI Size…"), slot: .tools, defaultVisibility: .visible))
        }
        return list
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let c = controller, c.effective.contains(.resolution), display.isActive, display.mirrorOf == nil else { return [] }
        let key = display.key
        var items: [(DisplayMenuItemID, NSMenuItem)] = []
        let stops = c.sliderModes(for: key)
        let current = c.currentMode(display)
        if stops.count >= 2, let current, let index = stops.firstIndex(of: current) {
            let value = Double(index) / Double(stops.count - 1)
            var sliderRef: WeakMenuItem?
            let slider = MenuSliderItem(title: L("Resolution"), symbol: "rectangle.arrowtriangle.2.outward", value: value) { [weak self] v in
                self?.sliderMoved(key, value: v, item: sliderRef?.item)
            }
            sliderRef = WeakMenuItem(slider)
            slider.toolTip = c.sliderValueText(current, key: key)
            items.append((.dResolutionSlider, slider))
        }
        items.append((.dResolutionMenu, ManagedMenuItem.submenu(L("Resolution"), items: modeMenu(c, key: key, current: current))))
        return items
    }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, let c = controller, c.effective.contains(.scaleMatch) else { return [] }
        return [(.dMatchUI, ManagedMenuItem(L("Match UI Size…")) { [weak c] in c?.matchUIScale() })]
    }

    // MARK: Building

    private func modeMenu(_ c: ResolutionController, key: DisplayKey, current: ModeRef?) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        func action(_ title: String, _ target: ModeRef?) {
            guard let target else { return }
            items.append(ManagedMenuItem(title, enabled: target != current) { [weak c] in c?.apply(target, to: key) })
        }
        action(L("Toggle HiDPI"), c.hiDPIToggleTarget(key))
        action(L("Native"), c.native(key))
        action(L("Default"), c.defaultMode(key))
        action(L("Native-Halved HiDPI"), c.nativeHalved(key))
        if let notch = c.notchToggleTarget(key) { action(L("Toggle Notch"), notch) }
        items.append(ManagedMenuItem(L("Undo Resolution Change"), enabled: c.canUndo(key)) { [weak c] in c?.undo(key) })
        items.append(ManagedMenuItem(L("Redo Resolution Change"), enabled: c.canRedo(key)) { [weak c] in c?.redo(key) })

        let favorites = c.favorites(key)
        if !favorites.isEmpty {
            items.append(.separator())
            items.append(ManagedMenuItem.disabled(L("Favorites")))
            for (i, f) in favorites.enumerated() {
                let on = current.map { FavoriteMode($0) == f } ?? false
                items.append(ManagedMenuItem(f.label, on: on) { [weak c] in c?.applyFavorite(i, on: key) })
            }
        }
        if let current, !favorites.contains(FavoriteMode(current)) {
            items.append(ManagedMenuItem(L("Add Current to Favorites")) { [weak c] in c?.saveFavorite(current, on: key) })
        }

        items.append(.separator())
        let modes = c.modes(for: key)
        for m in modes.prefix(60) {
            let ref = m.ref
            items.append(ManagedMenuItem(c.label(m), on: ref == current) { [weak c] in c?.apply(ref, to: key) })
        }
        if modes.count > 60 {
            items.append(ManagedMenuItem(L("All Modes in Settings…")) { [weak self] in self?.context?.openSettings("displays.resolution") })
        }
        return items
    }

    /// The slider snaps to stops (and to favorite/current/default/native unless ⌥ is held) and
    /// applies 0.4 s after it stops moving (mode changes are slow). A change that may need
    /// confirming closes the menu first (W8b), so Return and Esc reach the confirm panel
    /// instead of the menu's tracking loop.
    private func sliderMoved(_ key: DisplayKey, value: Double, item: NSMenuItem?) {
        sliderApply?.cancel()
        let bypass = NSEvent.modifierFlags.contains(.option)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let c = self?.controller else { return }
                let stops = c.sliderModes(for: key)
                guard stops.count >= 2 else { return }
                let raw = Int((min(1, max(0, value)) * Double(stops.count - 1)).rounded())
                let i = c.snappedStop(raw, in: stops, key: key, bypass: bypass)
                let target = stops[i]
                if let d = self?.context?.registry.info(for: key), c.currentMode(d) == target { return }
                guard ResolutionMenuItems.cancelTracking(of: item) else {
                    c.apply(target, to: key)
                    return
                }
                // Default mode only: runs once the menu's tracking loop has ended.
                RunLoop.main.perform(inModes: [.default]) { [weak self] in
                    MainActor.assumeIsolated { self?.controller?.apply(target, to: key) }
                }
            }
        }
        sliderApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Ends tracking of the menu tree holding `item` (the status menu, or the floating
    /// panel's menu). False when it isn't in an open menu.
    private static func cancelTracking(of item: NSMenuItem?) -> Bool {
        guard var menu = item?.menu else { return false }
        while let parent = menu.supermenu { menu = parent }
        menu.cancelTrackingWithoutAnimation()
        return true
    }
}

/// Weak holder: the slider's own closure must not keep the item alive.
private struct WeakMenuItem {
    weak var item: NSMenuItem?
    init(_ item: NSMenuItem) { self.item = item }
}
