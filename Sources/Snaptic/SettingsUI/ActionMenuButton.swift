import SwiftUI
import SnapticKit

struct ActionMenuItem: Identifiable {
    let id: String
    let title: String
    let enabled: Bool
    let action: @MainActor () -> Void
    /// R5-13.
    var control: ControlID? = nil
    /// A submenu ("While an App Is Running ▸") when not empty; `action` is then unused.
    var children: [ActionMenuItem] = []
    /// A separator line (`ActionMenuItem.separator(_:)`).
    var isSeparator = false

    init(id: String, title: String, enabled: Bool = true, control: ControlID? = nil,
         action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.enabled = enabled
        self.control = control
        self.action = action
    }

    /// A submenu.
    init(id: String, title: String, enabled: Bool = true, children: [ActionMenuItem], control: ControlID? = nil) {
        self.id = id
        self.title = title
        self.enabled = enabled
        self.control = control
        self.children = children
        self.action = {}
    }

    static func separator(_ id: String) -> ActionMenuItem {
        var item = ActionMenuItem(id: id, title: "", enabled: false) {}
        item.isSeparator = true
        return item
    }
}

/// Pull-down button with actions (Display Tools ▾, Copy Settings From ▾, Options ▾). With `primaryAction` it is a
/// split button: a click runs the primary action and ▾ opens the menu (Mail's toolbar; R5-9 Keep Awake).
struct ActionMenuButton: View {
    let title: String
    let items: [ActionMenuItem]
    let primaryAction: (@MainActor () -> Void)?
    let control: ControlID?

    init(_ title: String, items: [ActionMenuItem]) {
        self.init(title, items: items, primaryAction: nil)
    }

    init(_ title: String, items: [ActionMenuItem], primaryAction: (@MainActor () -> Void)?, control: ControlID? = nil) {
        self.title = title
        self.items = items
        self.primaryAction = primaryAction
        self.control = control
    }

    var body: some View {
        Group {
            if let primaryAction {
                Menu {
                    entries
                } label: {
                    Text(title)
                } primaryAction: {
                    primaryAction()
                }
            } else {
                Menu {
                    entries
                } label: {
                    Text(title)
                }
            }
        }
        .fixedSize()
        .modifier(OptionalSettingsAnchor(control))
    }

    private var entries: some View {
        ForEach(items) { item in
            ActionMenuEntry(item: item)
        }
    }
}

private struct ActionMenuEntry: View {
    let item: ActionMenuItem

    var body: some View {
        if item.isSeparator {
            Divider()
        } else if !item.children.isEmpty {
            Menu(item.title) {
                ForEach(item.children) { child in
                    ActionMenuEntry(item: child)
                }
            }
            .disabled(!item.enabled)
        } else {
            Button(item.title) { item.action() }
                .disabled(!item.enabled)
        }
    }
}
