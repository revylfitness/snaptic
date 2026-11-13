import Foundation

/// Other apps that show Dock previews (PLAN 0.5 §4.15; ids from S0-15, `docs/design/0.5/STEP0-NOTES.md`). A fixed
/// table: the pause status names the table's app, never the running app's own name. A match is by exact bundle id.
/// Team ids are added at R from `codesign -dv` (§R4 S0-15); until then this table carries bundle ids only.
/// Snaptic's own id is never listed.
package struct KnownDockTool: Equatable, Sendable {
    /// The name shown in "Paused while DockDoor runs".
    package let name: String
    package let bundleID: String

    package init(name: String, bundleID: String) {
        self.name = name
        self.bundleID = bundleID
    }
}

package enum KnownDockTools {
    package static let all: [KnownDockTool] = [
        KnownDockTool(name: "DockDoor", bundleID: "com.ethanbills.DockDoor"),
        KnownDockTool(name: "DockDoor Pro", bundleID: "com.ejbills.DockDoorPro"),
        KnownDockTool(name: "HyperDock", bundleID: "de.bahoom.HyperDock"),
        KnownDockTool(name: "Dock Mate", bundleID: "com.macenhance.dockmate"),
        KnownDockTool(name: "DockView 2", bundleID: "com.macplus-software.com.DockView-2"),
    ]

    /// The first listed tool a running app is, or nil. Exact match only: no prefixes, no case folding.
    package static func match(bundleID: String?) -> KnownDockTool? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        return all.first { $0.bundleID == bundleID }
    }
}
