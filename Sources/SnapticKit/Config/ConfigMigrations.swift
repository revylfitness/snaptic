import Foundation

// One-time migrations (lead; 0.3 §4.6, R5-2). Markers live in their own store (`SnapticMigrationsV1`), which 0.2
// never reads or writes, so a 0.3 → 0.2 → 0.3 round trip re-runs nothing. Migrations are pure functions over
// decoded values that ModuleHost runs in a fixed order; decoders never migrate (M2 excepted: a pure mapping
// applied only while the new key is absent).

package enum MigrationID: String, CaseIterable, Sendable {
    case fromDisplays = "fromDisplays.v1", fromDisplaysToast = "fromDisplays.toast"
    case newModuleCards = "newModuleCards.v1", menuShortcuts = "menuShortcuts.v1"
    case showNits = "showNits.v1", powerSwitch = "powerSwitch.v1"
}

/// The migrations that already ran. Raw strings, so an id a newer Snaptic wrote survives this version's saves.
package struct MigrationLedger: ConfigModel {
    package static let key = "SnapticMigrationsV1"
    package static let maxIDs = 256
    package static let maxIDLength = 64

    package var done: Set<String>

    package init() { done = [] }

    private enum CodingKeys: String, CodingKey { case done }

    /// Element-wise: one bad element is dropped, the rest kept.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ids: [String] = c.lossyArray(.done, [])
        done = Set(ids)
    }

    /// Sorted, so the same ledger always encodes to the same bytes.
    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(done.sorted(), forKey: .done)
    }

    package func has(_ id: MigrationID) -> Bool { done.contains(id.rawValue) }

    package mutating func record(_ id: MigrationID) { done.insert(id.rawValue) }

    /// ≤ 256 ids of ≤ 64 printable ASCII characters; known ids are always kept.
    package func sanitized() -> MigrationLedger {
        var c = MigrationLedger()
        let known = Set(MigrationID.allCases.map(\.rawValue))
        let valid = done.filter { id in
            !id.isEmpty && id.utf8.count <= Self.maxIDLength && id.utf8.allSatisfy { (0x21...0x7E).contains($0) }
        }
        let kept = valid.filter { known.contains($0) }
        let others = valid.subtracting(kept).sorted().prefix(max(0, Self.maxIDs - kept.count))
        c.done = kept.union(others)
        return c
    }
}
