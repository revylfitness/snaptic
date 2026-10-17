import Foundation

// Saved layouts (owner: D). PLAN §9.7 (≤ 32 layouts).

package struct LayoutsConfig: ConfigModel {
    package var layouts: [SavedLayout]
    /// Show "Undo" after an automatic apply.
    package var undoToast: Bool

    package init() {
        layouts = []
        undoToast = true
    }

    private enum CodingKeys: String, CodingKey { case layouts, undoToast }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layouts = (try? c.decodeIfPresent(TolerantArray<SavedLayout>.self, forKey: .layouts))?.values ?? []
        undoToast = c.lossy(.undoToast, true)
    }

    package func sanitized() -> LayoutsConfig {
        var c = self
        var ids = Set<StableID>()
        c.layouts = layouts.filter { ids.insert($0.id).inserted }.prefix(LayoutPresetModel.maxLayouts).map { $0.sanitized() }
        return c
    }

    package func layout(_ id: StableID) -> SavedLayout? { layouts.first { $0.id == id } }

    /// Layouts in menu order (actions 1–9 follow this order).
    package var ordered: [SavedLayout] { layouts }
}
