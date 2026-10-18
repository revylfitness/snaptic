import SwiftUI
import SnapticKit

/// Rows that can be reordered by dragging (`onMove`) and from the keyboard: each row's context menu has Edit…,
/// Move Up, Move Down and Delete, and VoiceOver gets the same as named actions (design M4, m10). Place it inside a
/// `Section` of a grouped form, or inside a `List`. With `confirmDelete` (the alert's question for an item, e.g.
/// "Delete “Desk”?"), Delete asks first, like the editor sheets' Delete buttons (review ux m10). `deleteAsks` is for
/// a caller whose `onDelete` shows its own alert: the menu item then reads "Delete…" too.
struct ReorderableList<Item: Identifiable, Row: View>: View {
    let items: Binding<[Item]>
    let onEdit: ((Item) -> Void)?
    let onDelete: ((Item) -> Void)?
    let confirmDelete: ((Item) -> String)?
    let deleteAsks: Bool
    let row: (Item) -> Row
    @State private var pendingDelete: Item.ID?

    init(_ items: Binding<[Item]>, onEdit: ((Item) -> Void)? = nil, onDelete: ((Item) -> Void)?,
         confirmDelete: ((Item) -> String)? = nil, deleteAsks: Bool = false,
         @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.confirmDelete = confirmDelete
        self.deleteAsks = deleteAsks
        self.row = row
    }

    var body: some View {
        ForEach(items.wrappedValue) { item in
            row(item)
                .contextMenu { menu(for: item) }
                .modifier(ReorderAccessibilityActions(
                    edit: onEdit.map { edit in { edit(item) } },
                    delete: onDelete == nil ? nil : { requestDelete(item) },
                    moveUp: canMove(item, by: -1) ? { move(item, by: -1) } : nil,
                    moveDown: canMove(item, by: 1) ? { move(item, by: 1) } : nil))
                .alert(confirmDelete?(item) ?? "", isPresented: deleteBinding(for: item)) {
                    Button(L("Delete"), role: .destructive) {
                        pendingDelete = nil
                        if let current = self.item(item.id) { onDelete?(current) }
                    }
                    Button(L("Cancel"), role: .cancel) { pendingDelete = nil }
                } message: {
                    Text(L("This can’t be undone."))
                }
        }
        .onMove { from, to in
            items.wrappedValue.move(fromOffsets: from, toOffset: to)
        }
    }

    @ViewBuilder private func menu(for item: Item) -> some View {
        if let onEdit {
            Button(L("Edit…")) { onEdit(item) }
            Divider()
        }
        Button(L("Move Up")) { move(item, by: -1) }
            .disabled(!canMove(item, by: -1))
        Button(L("Move Down")) { move(item, by: 1) }
            .disabled(!canMove(item, by: 1))
        if onDelete != nil {
            Divider()
            Button(confirmDelete == nil && !deleteAsks ? L("Delete") : L("Delete…"), role: .destructive) {
                requestDelete(item)
            }
        }
    }

    /// Deletes at once, or asks first when `confirmDelete` is set.
    private func requestDelete(_ item: Item) {
        if confirmDelete == nil { onDelete?(item) } else { pendingDelete = item.id }
    }

    private func deleteBinding(for item: Item) -> Binding<Bool> {
        Binding(get: { pendingDelete == item.id },
                set: { shown in if !shown && pendingDelete == item.id { pendingDelete = nil } })
    }

    private func item(_ id: Item.ID) -> Item? {
        items.wrappedValue.first { $0.id == id }
    }

    private func index(of item: Item) -> Int? {
        items.wrappedValue.firstIndex { $0.id == item.id }
    }

    private func canMove(_ item: Item, by delta: Int) -> Bool {
        guard let i = index(of: item) else { return false }
        return items.wrappedValue.indices.contains(i + delta)
    }

    private func move(_ item: Item, by delta: Int) {
        guard let i = index(of: item), items.wrappedValue.indices.contains(i + delta) else { return }
        var list = items.wrappedValue
        list.swapAt(i, i + delta)
        items.wrappedValue = list
    }
}

/// VoiceOver actions Edit, Move Up, Move Down and Delete, each only when it can act.
private struct ReorderAccessibilityActions: ViewModifier {
    let edit: (() -> Void)?
    let delete: (() -> Void)?
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if let edit { Button(L("Edit")) { edit() } }
            if let moveUp { Button(L("Move Up")) { moveUp() } }
            if let moveDown { Button(L("Move Down")) { moveDown() } }
            if let delete { Button(L("Delete")) { delete() } }
        }
    }
}
