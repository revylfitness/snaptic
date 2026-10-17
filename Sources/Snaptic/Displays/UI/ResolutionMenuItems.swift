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
            let slider = MenuSliderItem(title: L("Resolution"), symbol: "rectangle.arrowtriangle.2.outward", value: value) { [weak self] v in
                self?.sliderMoved(key, value: v)
            }
            slider.toolTip = c.label(current, markers: false)
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
            items.append(ManagedMenuItem(c.label(m.ref, key: key), on: m.ref == current) { [weak c] in c?.apply(m.ref, to: key) })
        }
        if modes.count > 60 {
            items.append(ManagedMenuItem(L("All Modes in Settings…")) { [weak self] in self?.context?.openSettings("displays.resolution") })
        }
        return items
    }

    /// The slider snaps to stops and applies 0.4 s after it stops moving (mode changes are slow).
    private func sliderMoved(_ key: DisplayKey, value: Double) {
        sliderApply?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let c = self?.controller else { return }
                let stops = c.sliderModes(for: key)
                guard stops.count >= 2 else { return }
                let i = Int((min(1, max(0, value)) * Double(stops.count - 1)).rounded())
                c.apply(stops[i], to: key)
            }
        }
        sliderApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
