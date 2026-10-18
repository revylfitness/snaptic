import SwiftUI
import SnapticKit

/// Glyph tiles (Snaptic/module/Awake icons, display icons): rendered symbols with the `.isSelected` trait, never
/// raw names. A radio group: the row title is the group label; ← and → move the selection (design m10). VoiceOver
/// names each tile from `labels`, or from the symbol's words ("Cup and saucer").
struct GlyphTilePicker: View {
    let title: String
    let symbols: [String]
    let selection: Binding<String>
    let anchor: ControlID?
    let labels: [String: String]

    init(_ title: String, symbols: [String], selection: Binding<String>, anchor: ControlID? = nil) {
        self.init(title, symbols: symbols, labels: [:], selection: selection, anchor: anchor)
    }

    init(_ title: String, symbols: [String], labels: [String: String], selection: Binding<String>,
         anchor: ControlID? = nil) {
        self.title = title
        self.symbols = symbols
        self.labels = labels
        self.selection = selection
        self.anchor = anchor
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                ForEach(symbols, id: \.self) { symbol in
                    tile(symbol)
                }
            }
            .focusable()
            .onKeyPress(.leftArrow) { move(-1) }
            .onKeyPress(.rightArrow) { move(1) }
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .modifier(OptionalSettingsAnchor(anchor))
    }

    private func tile(_ symbol: String) -> some View {
        let selected = symbol == selection.wrappedValue
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Button {
            selection.wrappedValue = symbol
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 32, height: 26)
                .background(shape.fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
                .overlay(shape.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1),
                                            lineWidth: selected ? 1.5 : 0.5))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(name(symbol))
        .accessibilityLabel(name(symbol))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !symbols.isEmpty else { return .ignored }
        let i = symbols.firstIndex(of: selection.wrappedValue) ?? 0
        let next = min(symbols.count - 1, max(0, i + delta))
        if symbols[next] != selection.wrappedValue { selection.wrappedValue = symbols[next] }
        return .handled
    }

    /// "cup.and.saucer.fill" → "Cup and saucer".
    private func name(_ symbol: String) -> String {
        if let label = labels[symbol] { return label }
        let skip: Set<String> = ["fill", "circle", "square", "badge"]
        let words = symbol.split(separator: ".").map(String.init).filter { !skip.contains($0) }
        let text = words.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
