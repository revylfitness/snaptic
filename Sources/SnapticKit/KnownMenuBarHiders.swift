import Foundation

/// Other menu bar apps that hide icons (PLAN 0.4 §4.10; ids verified in S0-15, `docs/design/0.4/STEP0-NOTES.md`).
/// A fixed table: the pause status names the table's app, never the running app's own name. A match needs the bundle
/// id (Thaw: the prefix, for its build suffixes) **and** the code-signing team when one is known; a nil team matches
/// by bundle id only. Known forks with their own ids aren't listed.
package struct KnownMenuBarHider: Equatable, Sendable {
    /// The name shown in "Paused while Hidden Bar runs".
    package let name: String
    package let bundleID: String
    /// `bundleID` is a prefix: `com.stonerl.Thaw` matches `com.stonerl.Thaw` and `com.stonerl.Thaw.<suffix>`.
    package let isPrefix: Bool
    /// The Team ID the app is signed with, or nil while unverified (the match is then by bundle id only).
    package let teamID: String?

    package init(name: String, bundleID: String, isPrefix: Bool = false, teamID: String?) {
        self.name = name
        self.bundleID = bundleID
        self.isPrefix = isPrefix
        self.teamID = teamID
    }

    /// Whether a running app with `bundleID`, signed by `teamID` (nil: unsigned or unreadable), is this hider.
    package func matches(bundleID candidate: String, teamID candidateTeam: String?) -> Bool {
        let idMatches = isPrefix
            ? candidate == bundleID || candidate.hasPrefix(bundleID + ".")
            : candidate == bundleID
        guard idMatches else { return false }
        guard let teamID else { return true }
        return candidateTeam == teamID
    }
}

package enum KnownMenuBarHiders {
    package static let all: [KnownMenuBarHider] = [
        KnownMenuBarHider(name: "Hidden Bar", bundleID: "com.dwarvesv.minimalbar", teamID: "W777S7V8TN"),
        // Team id pending: `codesign -dv` at R (STEP0-NOTES, carried S0-15).
        KnownMenuBarHider(name: "Bartender", bundleID: "com.surteesstudios.Bartender", teamID: nil),
        KnownMenuBarHider(name: "Ice", bundleID: "com.jordanbaird.Ice", teamID: "K2ATHQPJDP"),
        KnownMenuBarHider(name: "Thaw", bundleID: "com.stonerl.Thaw", isPrefix: true, teamID: "A7CKWF99ML"),
    ]

    /// The first listed hider a running app is, or nil.
    package static func match(bundleID: String?, teamID: String?) -> KnownMenuBarHider? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        return all.first { $0.matches(bundleID: bundleID, teamID: teamID) }
    }
}
