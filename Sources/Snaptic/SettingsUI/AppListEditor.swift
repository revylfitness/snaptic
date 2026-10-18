import SwiftUI
import SnapticKit

// Stub (owner: H). Hand-written by the lead in step 0 from PLAN 0.3 §4.1 + R5-13 (kind S): plain controls with the
// contract signatures; H replaces the bodies in step 1.

/// Moved from Switcher AppListSection; used by Switcher and PIP.
struct AppListEditor: View {
    let title: String
    let help: String?
    let bundleIDs: Binding<[String]>
    let anchor: ControlID?

    init(_ title: String, help: String?, bundleIDs: Binding<[String]>, anchor: ControlID?) {
        self.title = title
        self.help = help
        self.bundleIDs = bundleIDs
        self.anchor = anchor
    }

    var body: some View {
        LabeledContent(title) {
            Text(String(bundleIDs.wrappedValue.count))
        }
    }
}
