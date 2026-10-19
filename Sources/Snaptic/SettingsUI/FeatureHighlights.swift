import SwiftUI
import SnapticKit

/// Shown under the header while a module or feature group is off: 2–3 "what this does" rows, each a symbol, a
/// bold title and one line (the Screen Time / Siri off state).
struct FeatureHighlights: View {
    let rows: [FeatureHighlight]

    init(_ rows: [FeatureHighlight]) { self.rows = rows }

    var body: some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row.symbol)
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).fontWeight(.semibold)
                            Text(row.text)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
