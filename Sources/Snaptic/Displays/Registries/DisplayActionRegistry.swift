import Foundation
import SnapticKit

/// Which display an action applies to.
enum DisplayTarget: Equatable, Sendable {
    case display(DisplayKey)
    /// The display with the menu bar.
    case main
    /// The display under the pointer.
    case pointer
    case all
}

/// One user-invokable command. Shortcuts, menus and the CLI all read from here.
struct Action {
    let id: DisplayActionID
    let title: String
    let feature: DisplayFeature
    /// Exposed to the CLI only if true (R5.4 exposure table).
    let cliAllowed: Bool
    let perform: @MainActor (DisplayTarget) -> Void

    init(id: DisplayActionID, title: String, feature: DisplayFeature, cliAllowed: Bool,
         perform: @escaping @MainActor (DisplayTarget) -> Void) {
        self.id = id
        self.title = title
        self.feature = feature
        self.cliAllowed = cliAllowed
        self.perform = perform
    }
}

/// Every registered action (lead). Registrations end with the registering lifetime.
@MainActor final class DisplayActionRegistry {
    private var entries: [(serial: UInt64, action: Action)] = []
    private var serial: UInt64 = 0

    init() {}

    func register(_ action: Action, lifetime: Lifetime) {
        guard !lifetime.isEnded else { return }
        serial &+= 1
        let mine = serial
        if entries.contains(where: { $0.action.id == action.id }) {
            EventLog.shared.record(.modules, "Action \(action.id.rawValue) registered twice; the newer one wins")
            entries.removeAll { $0.action.id == action.id }
        }
        entries.append((mine, action))
        lifetime.onEnd { [weak self] in self?.entries.removeAll { $0.serial == mine } }
    }

    var all: [Action] { entries.map(\.action) }

    func action(_ id: DisplayActionID) -> Action? { entries.first { $0.action.id == id }?.action }

    /// Runs an action if it is registered. Returns false if it isn't.
    @discardableResult
    func perform(_ id: DisplayActionID, on target: DisplayTarget) -> Bool {
        guard let action = action(id) else { return false }
        action.perform(target)
        return true
    }
}
