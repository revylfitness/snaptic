import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// List .onMove + ▲▼ context menu; VoiceOver actions Edit, Delete, Move Up, Move Down.
struct ReorderableList<Item: Identifiable, Row: View>: View {
    let items: Binding<[Item]>
    let onEdit: ((Item) -> Void)?
    let onDelete: ((Item) -> Void)?
    let row: (Item) -> Row

    init(_ items: Binding<[Item]>, onEdit: ((Item) -> Void)? = nil, onDelete: ((Item) -> Void)?,
         @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.row = row
    }

    var body: some View {
        List {
            ForEach(items.wrappedValue) { item in
                row(item)
            }
            .onMove { from, to in items.wrappedValue.move(fromOffsets: from, toOffset: to) }
        }
    }
}
