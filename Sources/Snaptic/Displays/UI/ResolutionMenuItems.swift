import AppKit
import Combine
import SnapticKit

/// Resolution in the Displays menu (PLAN 0.3 §5.2): an optional slider under the device row (top level, never in a
/// submenu; hidden by default), up to eight resolutions in the display submenu (current, default, favorites,
/// recommended; "Default", "More Space" and "Larger Text" as subtitles), "More Resolutions…", Undo/Redo when
/// available, and Display Tools › "Match Text Size…".
///
/// Constructed and registered by ResolutionController in start(). Reads caches only (≤ 50 ms rebuilds); item actions
/// capture the `DisplayKey` and re-resolve it on click.
@MainActor final class ResolutionMenuItems: DisplayMenuContributor, ControlDeclaring {
    typealias Controls = ResolutionMenuItemsControls

    weak var context: DisplaysContext?
    weak var controller: ResolutionController?
    private var sliderApply: DispatchWorkItem?

    /// A slider stop is applied this long after the last release or scroll step (mode changes are slow).
    static let applyDelay: TimeInterval = 0.4

    init(context: DisplaysContext) { self.context = context }

    static var menuItemIDs: [DisplayMenuItemID] { [.dResolutionSlider, .dResolutionMenu, .dMatchUI] }

    var descriptors: [DisplayMenuItemDescriptor] {
        var list = [
            DisplayMenuItemDescriptor(id: .dResolutionSlider, title: L("Resolution Slider"), slot: .display, defaultVisibility: .hidden),
            DisplayMenuItemDescriptor(id: .dResolutionMenu, title: L("Resolutions"), slot: .display, defaultVisibility: .inSubmenu),
        ]
        if controller?.effective.contains(.scaleMatch) == true {
            list.append(DisplayMenuItemDescriptor(id: .dMatchUI, title: L("Match Text Size…"), slot: .tools, defaultVisibility: .visible))
        }
        return list
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let c = controller, c.effective.contains(.resolution), display.isActive, display.mirrorOf == nil else { return [] }
        let key = display.key
        let current = c.currentMode(display)
        var items: [(DisplayMenuItemID, NSMenuItem)] = []
        if let slider = sliderRow(c, key: key, current: current) { items.append((.dResolutionSlider, slider)) }
        items += modeItems(c, key: key, current: current).map { (.dResolutionMenu, $0) }
        return items
    }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, let ctx = context, let c = controller, c.effective.contains(.scaleMatch),
              ctx.registry.displays.filter({ $0.isActive && $0.mirrorOf == nil }).count >= 2 else { return [] }
        let item = MenuKit.action(L("Match Text Size…"), control: ControlID("menu.display.d.matchTextSize")) { [weak self] in
            self?.context?.openSettings("displays.matchTextSize")
        }
        return [(.dMatchUI, item)]
    }

    // MARK: Display submenu

    private func modeItems(_ c: ResolutionController, key: DisplayKey, current: ModeRef?) -> [NSMenuItem] {
        let picks = ResolutionMenuPicks.picks(modes: c.modes(for: key), current: current, favorites: c.favorites(key))
        let anyHiDPI = picks.contains { $0.mode.isHiDPI }
        var items: [NSMenuItem] = []
        for pick in picks {
            let target = pick.mode
            var title = "\(target.pointWidth) × \(target.pointHeight)"
            if anyHiDPI && !target.isHiDPI { title += " " + L("(Low Resolution)") }
            let item = MenuKit.toggle(title, isOn: pick.isCurrent, control: ControlID("menu.display.d.resolution")) { [weak c] in
                c?.apply(target, to: key)
            }
            items.append(MenuKit.withSubtitle(item, Self.subtitle(pick.role)))
        }
        items.append(MenuKit.action(L("More Resolutions…"), control: ControlID("menu.display.d.moreResolutions")) { [weak self] in
            self?.context?.openSettings("displays.resolution")
        })
        if c.canUndo(key) {
            items.append(MenuKit.action(L("Undo Resolution Change"), control: ControlID("menu.display.d.resolutionUndo")) { [weak c] in
                c?.undo(key)
            })
        }
        if c.canRedo(key) {
            items.append(MenuKit.action(L("Redo Resolution Change"), control: ControlID("menu.display.d.resolutionRedo")) { [weak c] in
                c?.redo(key)
            })
        }
        return items
    }

    static func subtitle(_ role: ResolutionMenuRole?) -> String? {
        switch role {
        case .defaultMode: return L("Default")
        case .moreSpace: return L("More Space")
        case .largerText: return L("Larger Text")
        case nil: return nil
        }
    }

    // MARK: Slider

    /// The slider's value is the point width; it moves freely and lands on the nearest stop (same HiDPI class and
    /// refresh as the current mode) when released, then applies `applyDelay` after the last release or scroll step.
    private func sliderRow(_ c: ResolutionController, key: DisplayKey, current: ModeRef?) -> MenuSliderRow? {
        let stops = c.sliderModes(for: key)
        guard stops.count >= 2, let current, stops.contains(current), let first = stops.first, let last = stops.last,
              last.pointWidth > first.pointWidth else { return nil }
        var format = ValueFormat.plain(digits: 0)
        if context?.config.value.resolution.sliderLabel == .percent, let def = c.defaultMode(key), def.pointWidth > 0 {
            format = .percent(of: Double(def.pointWidth))
        }
        var rowRef = WeakSliderRow()
        let row = MenuSliderRow(title: L("Resolution"), symbol: "rectangle.arrowtriangle.2.outward",
                                value: Double(current.pointWidth),
                                range: Double(first.pointWidth)...Double(last.pointWidth), format: format,
                                control: ControlID("menu.display.d.resolutionSlider")) { [weak self] value, phase in
            guard phase == .ended else { return }
            self?.sliderReleased(key, width: value, row: rowRef.row)
        }
        rowRef.row = row
        if let runtime = context?.runtime {
            row.bind(to: runtime.$displays
                .map { displays -> Double? in
                    (displays.first { $0.key == key }?.currentMode?.ref.pointWidth).map { Double($0) }
                }
                .removeDuplicates()
                .eraseToAnyPublisher())
        }
        return row
    }

    /// Snaps the slider to the nearest stop (and to a favorite, the current, default or native mode next to it unless
    /// ⌥ is held), then applies after `applyDelay`. A change that may need confirming closes the menu first (W8b), so
    /// Return and Esc reach the confirm panel instead of the menu's tracking loop.
    private func sliderReleased(_ key: DisplayKey, width: Double, row: MenuSliderRow?) {
        guard let c = controller else { return }
        let stops = c.sliderModes(for: key)
        guard stops.count >= 2, width.isFinite else { return }
        let nearest = stops.indices.min { abs(Double(stops[$0].pointWidth) - width) < abs(Double(stops[$1].pointWidth) - width) } ?? 0
        let bypass = NSEvent.modifierFlags.contains(.option)
        let index = c.snappedStop(nearest, in: stops, key: key, bypass: bypass)
        let target = stops[index]
        row?.setValue(Double(target.pointWidth))
        sliderApply?.cancel()
        let work = DispatchWorkItem { [weak self, weak row] in
            MainActor.assumeIsolated {
                guard let self, let c = self.controller else { return }
                if let d = self.context?.registry.info(for: key), c.currentMode(d) == target { return }
                guard Self.cancelTracking(of: row) else {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.applyDelay, execute: work)
    }

    /// Ends tracking of the menu tree holding `item` (the status menu, or the floating panel's menu). False when it
    /// isn't in an open menu.
    private static func cancelTracking(of item: NSMenuItem?) -> Bool {
        guard var menu = item?.menu else { return false }
        while let parent = menu.supermenu { menu = parent }
        menu.cancelTrackingWithoutAnimation()
        return true
    }
}

/// Weak holder: the slider's own closure must not keep the row alive.
private struct WeakSliderRow {
    weak var row: MenuSliderRow?
}
