import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

struct ActionMenuItem: Identifiable {
    let id: String
    let title: String
    let enabled: Bool
    let action: @MainActor () -> Void
    /// R5-13.
    var control: ControlID? = nil

    init(id: String, title: String, enabled: Bool = true, control: ControlID? = nil,
         action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.enabled = enabled
        self.control = control
        self.action = action
    }
}

/// Pull-down button with actions (Display Tools ▾, Copy Settings From ▾, Options ▾).
struct ActionMenuButton: View {
    let title: String
    let items: [ActionMenuItem]

    init(_ title: String, items: [ActionMenuItem]) {
        self.title = title
        self.items = items
    }

    var body: some View {
        Menu(title) {
            ForEach(items) { item in
                Button(item.title) { item.action() }
                    .disabled(!item.enabled)
            }
        }
        .fixedSize()
    }
}
