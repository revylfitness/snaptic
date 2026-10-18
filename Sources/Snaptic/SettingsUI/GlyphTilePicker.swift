import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// Glyph tiles rendered as symbols (never raw names); a radio group.
struct GlyphTilePicker: View {
    let title: String
    let symbols: [String]
    let selection: Binding<String>
    let anchor: ControlID?

    init(_ title: String, symbols: [String], selection: Binding<String>, anchor: ControlID? = nil) {
        self.title = title
        self.symbols = symbols
        self.selection = selection
        self.anchor = anchor
    }

    var body: some View {
        Picker(title, selection: selection) {
            ForEach(symbols, id: \.self) { symbol in
                Image(systemName: symbol).tag(symbol)
            }
        }
    }
}
