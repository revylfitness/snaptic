import AppKit
import SnapticKit

fileprivate extension DisplayMenuItemID {
    static let pipDisplay = DisplayMenuItemID(rawValue: "e.pip.display")
    static let pipTools = DisplayMenuItemID(rawValue: "e.pip.tools")
}

/// Picture in Picture menu items (R5.4 exposure: a submenu with start/stop/hide/pause
/// all). Constructed and registered by PIPController in start(). Items capture
/// DisplayKeys and configuration ids and re-resolve at click time.
@MainActor final class PIPMenuItems: DisplayMenuContributor {
    weak var context: DisplaysContext?
    weak var controller: PIPController?

    init(context: DisplaysContext) { self.context = context }

    var descriptors: [DisplayMenuItemDescriptor] {
        [
            DisplayMenuItemDescriptor(id: .pipDisplay, title: L("Picture in Picture (per display)"), slot: .display,
                                      defaultVisibility: .inSubmenu),
            DisplayMenuItemDescriptor(id: .pipTools, title: L("Picture in Picture"), slot: .tools, defaultVisibility: .visible),
        ]
    }

    func menuItems(for display: DisplayInfo) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard let ctx = context, let controller, ctx.runtime.isEffective(.pip) else { return [] }
        let key = display.key
        var items: [NSMenuItem] = []
        let saved = ctx.config.value.perDisplay[key]?.pip.configurations ?? []
        for c in saved {
            let id = c.id
            let title = c.kind == .fullScreen ? L("Stream “\(c.name)”") : c.name
            let item = DisplayMenuBlock.actionItem(title, symbol: c.kind == .fullScreen ? "rectangle.on.rectangle" : "pip") {
                [weak controller] in controller?.toggle(id)
            }
            item.state = controller.isRunning(id) ? .on : .off
            items.append(item)
        }
        if !saved.isEmpty { items.append(.separator()) }
        if saved.count < PerDisplayPIP.maxConfigurations {
            items.append(DisplayMenuBlock.actionItem(L("New Picture in Picture"), symbol: "plus") { [weak controller] in
                controller?.createAndStart(source: .display(key), kind: .window)
            })
            let targets = ctx.registry.displays.filter { $0.key != key && $0.isOnline }
            if !targets.isEmpty {
                var streamItems: [NSMenuItem] = []
                for t in targets {
                    var probe = PIPConfiguration(kind: .fullScreen)
                    probe.target = t.key
                    let targetKey = t.key
                    if let refusal = controller.streamRefusal(source: .display(key), configuration: probe, excluding: nil) {
                        let item = DisplayMenuBlock.infoItem(t.name)
                        item.toolTip = refusal
                        streamItems.append(item)
                    } else {
                        streamItems.append(DisplayMenuBlock.actionItem(t.name) { [weak controller] in
                            controller?.createAndStart(source: .display(key), kind: .fullScreen, target: targetKey)
                        })
                    }
                }
                items.append(DisplayMenuBlock.submenuItem(L("Stream Full Screen To"), symbol: "arrow.up.right.square", streamItems))
            }
        }
        return [(.pipDisplay, DisplayMenuBlock.submenuItem(L("Picture in Picture"), symbol: "pip", items))]
    }

    func globalItems(slot: MenuSlot) -> [(DisplayMenuItemID, NSMenuItem)] {
        guard slot == .tools, let ctx = context, let controller, ctx.runtime.isEffective(.pip) else { return [] }
        var items: [NSMenuItem] = []
        let running = ctx.capture.sessions
        for info in running {
            let id = info.id
            let item = DisplayMenuBlock.actionItem("\(info.name) — \(info.state.title)", symbol: "stop.circle") {
                [weak controller] in controller?.endSession(id, reason: nil)
            }
            item.toolTip = L("Stop")
            items.append(item)
        }
        if !running.isEmpty { items.append(.separator()) }
        for c in ctx.config.value.pip.windowConfigurations where !controller.isRunning(c.id) {
            let id = c.id
            items.append(DisplayMenuBlock.actionItem(c.name, symbol: "macwindow") { [weak controller] in controller?.toggle(id) })
        }
        items.append(DisplayMenuBlock.actionItem(L("Picture in Picture of a Window…"), symbol: "macwindow.badge.plus") {
            [weak controller] in controller?.pickWindow()
        })
        if !running.isEmpty {
            items.append(.separator())
            items.append(DisplayMenuBlock.actionItem(L("Stop All"), symbol: "stop.fill") { [weak controller] in controller?.stopAll() })
            let hidden = controller.allHidden
            items.append(DisplayMenuBlock.actionItem(hidden ? L("Show All") : L("Hide All"), symbol: hidden ? "eye" : "eye.slash") {
                [weak controller] in controller?.setAllHidden(!hidden)
            })
            let paused = controller.allPaused
            items.append(DisplayMenuBlock.actionItem(paused ? L("Resume All") : L("Pause All"), symbol: paused ? "play.fill" : "pause.fill") {
                [weak controller] in controller?.setAllPaused(!paused)
            })
        }
        items.append(.separator())
        items.append(DisplayMenuBlock.actionItem(L("Picture in Picture Settings…"), symbol: "gearshape") {
            DisplayMenuBlock.openSettings(page: "displays.pip")
        })
        return [(.pipTools, DisplayMenuBlock.submenuItem(L("Picture in Picture"), symbol: "pip", items))]
    }
}
