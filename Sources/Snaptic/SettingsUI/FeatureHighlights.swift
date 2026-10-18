import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// Shown under the header while a module or feature group is off: 2–3 "what this does" rows.
struct FeatureHighlights: View {
    let rows: [FeatureHighlight]

    init(_ rows: [FeatureHighlight]) { self.rows = rows }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                Label {
                    VStack(alignment: .leading) {
                        Text(row.title)
                        Text(row.text).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: row.symbol)
                }
            }
        }
    }
}
