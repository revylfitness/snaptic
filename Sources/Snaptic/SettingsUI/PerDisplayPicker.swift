import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

struct DisplayTile: Identifiable, Hashable {
    let id: DisplayKey
    let name: String
    let isBuiltin: Bool
    let badges: [String]
}

/// ≤ 4 displays: tiles; more: a pop-up. Hidden with one display.
struct PerDisplayPicker: View {
    let displays: [DisplayTile]
    let selection: Binding<DisplayKey?>

    init(_ displays: [DisplayTile], selection: Binding<DisplayKey?>) {
        self.displays = displays
        self.selection = selection
    }

    var body: some View {
        if displays.count > 1 {
            Picker(L("Display"), selection: selection) {
                ForEach(displays) { tile in
                    Text(tile.name).tag(Optional(tile.id))
                }
            }
        }
    }
}
