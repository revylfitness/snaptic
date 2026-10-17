import AppKit
import SnapticKit

/// Builds the Displays section of the status menu (PLAN §3.5): state banners (Safe Mode,
/// panic latch, other display apps, Unprotected), one DisplayMenuBlock per display in the
/// user's order, then the Tools section (`MenuSlot.tools` items) — sections in the order
/// MenuConfig gives. Called from DisplaysModule.menuSection() on every rebuild.
@MainActor final class DisplaysMenuBuilder {
    weak var context: DisplaysContext?

    init(context: DisplaysContext) { self.context = context }

    func build() -> [NSMenuItem] {
        guard let ctx = context else { return [] }
        var items = banners(ctx)
        for section in ctx.config.value.menu.orderedSections {
            let part: [NSMenuItem]
            switch section {
            case .displays: part = displayBlocks(ctx)
            case .tools: part = tools(ctx)
            }
            guard !part.isEmpty else { continue }
            if !items.isEmpty { items.append(NSMenuItem.separator()) }
            items += part
        }
        return items
    }

    // MARK: Banners

    private func banners(_ ctx: DisplaysContext) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if case .degraded(let reason) = ctx.runtime.moduleState {
            items.append(DisplayMenuBlock.infoItem(L("Displays: \(reason)"), symbol: "exclamationmark.triangle"))
        }
        if ctx.safeMode.isActive {
            items.append(DisplayMenuBlock.infoItem(L("Safe Mode: display automation is off"), symbol: "exclamationmark.shield"))
            let relauncher = ctx.relauncher
            items.append(DisplayMenuBlock.actionItem(L("Leave Safe Mode…"), symbol: "arrow.clockwise") {
                relauncher.relaunch(reason: L("Leave Safe Mode"))
            })
        }
        if ctx.runtime.isPanicLatched {
            items.append(DisplayMenuBlock.infoItem(L("Display automation is paused"), symbol: "pause.circle"))
            let panic = ctx.panic
            items.append(DisplayMenuBlock.actionItem(L("Resume Display Automation"), symbol: "play.circle") {
                panic.resume()
            })
        }
        let paused = ctx.otherApps.pausedDisplayFeatures
        if !paused.isEmpty {
            let reasons = Self.pauseReasons(paused, monitor: ctx.otherApps)
            let item = DisplayMenuBlock.infoItem(reasons.first ?? L("Some features are paused"), symbol: "pause.circle")
            item.toolTip = paused.map(DisplaysUIText.title).sorted().joined(separator: ", ")
            items.append(item)
        }
        if Self.isUnprotected(ctx) {
            items.append(DisplayMenuBlock.infoItem(L("Unprotected: the safety helper isn't running"), symbol: "exclamationmark.shield"))
            let relauncher = ctx.relauncher
            items.append(DisplayMenuBlock.actionItem(L("Restart Snaptic"), symbol: "arrow.clockwise") {
                relauncher.relaunch(reason: L("Restart the safety helper"))
            })
        }
        return items
    }

    /// Unique, sorted pause reasons ("Paused while MonitorControl runs").
    static func pauseReasons(_ paused: Set<DisplayFeature>, monitor: OtherAppsMonitor) -> [String] {
        Array(Set(paused.compactMap { monitor.pauseReason(for: $0) })).sorted()
    }

    /// Features that rely on the guard are on, but the guard isn't alive (PLAN §3.5 "Unprotected").
    static func isUnprotected(_ ctx: DisplaysContext) -> Bool {
        FeatureGraph.requiredServices(effective: ctx.runtime.effectiveFeatures).contains(.guardProcess)
            && !ctx.guardClient.isAlive
    }

    // MARK: Display blocks

    /// Displays in menu order without hidden ones.
    static func orderedDisplays(_ ctx: DisplaysContext, includeHidden: Bool = false) -> [DisplayInfo] {
        let all = ctx.runtime.displays
        let main = all.first(where: \.isMain)?.key
        let order = ctx.config.value.menu.orderedDisplays(all.map(\.key), main: main, includeHidden: includeHidden)
        return order.compactMap { key in all.first { $0.key == key } }
    }

    private func displayBlocks(_ ctx: DisplaysContext) -> [NSMenuItem] {
        let all = ctx.runtime.displays
        guard !all.isEmpty else {
            return [DisplayMenuBlock.infoItem(L("No displays detected"), symbol: "display.trianglebadge.exclamationmark")]
        }
        let shown = Self.orderedDisplays(ctx)
        guard !shown.isEmpty else {
            let config = ctx.config
            return [
                DisplayMenuBlock.infoItem(L("All displays are hidden from the menu")),
                DisplayMenuBlock.actionItem(L("Show All Displays"), symbol: "eye") { config.value.menu.hiddenDisplays = [] },
            ]
        }
        let menu = ctx.config.value.menu
        let showHeader = shown.count > 1 || menu.headerForSingleDisplay
        var items: [NSMenuItem] = []
        for (index, display) in shown.enumerated() {
            if index > 0 { items.append(NSMenuItem.separator()) }
            items += DisplayMenuBlock(display: display, context: ctx, showHeader: showHeader).items()
        }
        return items
    }

    // MARK: Tools

    private func tools(_ ctx: DisplaysContext) -> [NSMenuItem] {
        let menu = ctx.config.value.menu
        var defaults: [DisplayMenuItemID: MenuItemVisibility] = [:]
        for descriptor in ctx.menus.descriptors where descriptor.slot == .tools {
            defaults[descriptor.id] = descriptor.defaultVisibility
        }
        let result = ctx.menus.globalItems(slot: .tools) { id in
            menu.visibility(of: id, default: defaults[id] ?? .visible)
        }
        var items: [NSMenuItem] = [NSMenuItem.sectionHeader(title: L("Tools"))]
        items += result.visible
        if !result.more.isEmpty {
            items.append(DisplayMenuBlock.submenuItem(L("More Tools"), symbol: "ellipsis.circle", result.more))
        }
        items.append(DisplayMenuBlock.actionItem(L("More Display Features…"), symbol: "switch.2") {
            DisplayMenuBlock.openSettings(page: "displays.features")
        })
        return items
    }
}
