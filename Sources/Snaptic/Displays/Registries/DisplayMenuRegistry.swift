import AppKit
import SnapticKit

/// Menu contributors (lead). The menu builder asks each for items per display; the
/// Menu customization page lists the registered descriptors.
@MainActor final class DisplayMenuRegistry {
    private struct Entry { let serial: UInt64; weak var contributor: (any DisplayMenuContributor)? }
    private var entries: [Entry] = []
    private var serial: UInt64 = 0
    var onChange: (@MainActor () -> Void)?

    init() {}

    func register(_ contributor: any DisplayMenuContributor, lifetime: Lifetime) {
        guard !lifetime.isEnded else { return }
        serial &+= 1
        let mine = serial
        entries.append(Entry(serial: mine, contributor: contributor))
        onChange?()
        lifetime.onEnd { [weak self] in
            self?.entries.removeAll { $0.serial == mine || $0.contributor == nil }
            self?.onChange?()
        }
    }

    var contributors: [any DisplayMenuContributor] { entries.compactMap(\.contributor) }

    var descriptors: [DisplayMenuItemDescriptor] { contributors.flatMap(\.descriptors) }

    /// Items for one display, in registration order, honoring the user's visibility choices.
    func items(for display: DisplayInfo, visibility: (DisplayMenuItemID) -> MenuItemVisibility)
        -> (visible: [NSMenuItem], more: [NSMenuItem]) {
        var visible: [NSMenuItem] = []
        var more: [NSMenuItem] = []
        for contributor in contributors {
            for (id, item) in contributor.menuItems(for: display) {
                switch visibility(id) {
                case .visible: visible.append(item)
                case .inSubmenu: more.append(item)
                case .hidden: break
                }
            }
        }
        return (visible, more)
    }
}
