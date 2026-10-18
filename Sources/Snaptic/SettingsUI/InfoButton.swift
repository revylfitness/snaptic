import SwiftUI
import SnapticKit

/// (i) popover for per-item details or a reference ("Exit codes"): 280 pt wide, title and message; never opens a
/// sheet.
struct InfoButton: View {
    let title: String
    let message: String
    @State private var shown = false

    init(_ title: String, message: String) {
        self.title = title
        self.message = message
    }

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(L("Show More About \(title)"))
        .accessibilityLabel(title)
        .accessibilityHint(L("Shows details"))
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(14)
            .frame(width: 280, alignment: .leading)
        }
    }
}
