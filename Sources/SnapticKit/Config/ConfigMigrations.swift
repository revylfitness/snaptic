import Foundation

// One-time migrations (lead; 0.3 §4.6, R5-2). Markers live in their own store (`SnapticMigrationsV1`), which 0.2
// never reads or writes, so a 0.3 → 0.2 → 0.3 round trip re-runs nothing. Migrations are pure functions over
// decoded values that ModuleHost runs in a fixed order; decoders never migrate (M2 excepted: a pure mapping
// applied only while the new key is absent).

package enum MigrationID: String, CaseIterable, Sendable {
    case fromDisplays = "fromDisplays.v1", fromDisplaysToast = "fromDisplays.toast"
    case newModuleCards = "newModuleCards.v1", menuShortcuts = "menuShortcuts.v1"
    case showNits = "showNits.v1", powerSwitch = "powerSwitch.v1"
    /// The §2.13 upgrader decision (Awake inserted off) was made: recorded on every install's first 0.3 launch,
    /// whether or not it inserted anything, so a fresh install (whose module settings never hold an Awake entry)
    /// is not taken for an upgrader on its second launch or after General › Reset.
    case awakeUpgrade = "awakeUpgrade.v1"
    /// 0.3.1 E1a: the first 0.3.1 launch happened (recorded for every install), and the welcome card for upgraders
    /// is finished (recorded at once for new users, and when an upgrader is done with the card).
    case v031Welcome = "v031Welcome.v1", v031WelcomeDone = "v031Welcome.done"
}

extension MigrationLedger {
    /// E1a: run once per install, at the first 0.3.1 launch. An upgrader is someone whose module settings
    /// (`SnapticModulesV1`) existed before this launch; 0.3.0 stored no last-run version, so nothing else tells them
    /// apart. Returns whether this launch recorded the marker.
    @discardableResult
    package mutating func recordV031Welcome(upgrader: Bool) -> Bool {
        guard !has(.v031Welcome) else { return false }
        record(.v031Welcome)
        if !upgrader { record(.v031WelcomeDone) }
        return true
    }

    /// E1a: who counts as an upgrader at the first 0.3.1 launch: module settings existed (0.3.0), or an earlier
    /// version ran (`SnapticDidLaunchBefore`: 0.1 and 0.2 users, whose upgrade defaults skip onboarding, so the card
    /// is the only place they're asked; r2 C2-1).
    package static func isV031Upgrader(modulesExisted: Bool, launchedBefore: Bool) -> Bool {
        modulesExisted || launchedBefore
    }

    /// E1a: the welcome card is due (an upgrader who isn't done with it).
    package var showsV031Welcome: Bool { has(.v031Welcome) && !has(.v031WelcomeDone) }
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
