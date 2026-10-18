import Foundation

/// The Mac Snaptic runs on, as Kit sees it (from sysctl on the app side).
package struct HostDescription: Equatable, Sendable {
    /// `hw.model`, e.g. "Mac16,6".
    package var modelIdentifier: String
    /// `machdep.cpu.brand_string`, e.g. "Apple M5 Max".
    package var chipName: String
    package var osMajor: Int
    package var osMinor: Int

    package init(modelIdentifier: String, chipName: String, osMajor: Int, osMinor: Int) {
        self.modelIdentifier = modelIdentifier
        self.chipName = chipName
        self.osMajor = osMajor
        self.osMinor = osMinor
    }

    package var isAppleSilicon: Bool { chipName.hasPrefix("Apple ") }
}

/// Macs where a platform bug makes a brightness method unreliable (PLAN §6.1, §1.1.6).
/// No upper OS bound: entries stay until a fix is verified on hardware.
package enum AffectedModels {
    package enum Issue: String, Codable, CaseIterable, Sendable {
        /// `CGSetDisplayTransferByTable` succeeds and reads back but changes nothing
        /// (FB22273782, macOS 26.3+ on M5 Pro/Max and MacBook Neo).
        case gammaNoOp
    }

    package struct Entry: Equatable, Sendable {
        package var chipPrefix: String?
        package var modelPrefix: String?
        package var minimumMajor: Int
        package var minimumMinor: Int
        package var issue: Issue

        package init(chipPrefix: String?, modelPrefix: String?, minimumMajor: Int, minimumMinor: Int, issue: Issue) {
            self.chipPrefix = chipPrefix
            self.modelPrefix = modelPrefix
            self.minimumMajor = minimumMajor
            self.minimumMinor = minimumMinor
            self.issue = issue
        }
    }

    package static let entries: [Entry] = [
        Entry(chipPrefix: "Apple M5 Pro", modelPrefix: nil, minimumMajor: 26, minimumMinor: 3, issue: .gammaNoOp),
        Entry(chipPrefix: "Apple M5 Max", modelPrefix: nil, minimumMajor: 26, minimumMinor: 3, issue: .gammaNoOp),
        // MacBook Neo [U]: identified by its A-series chip until the model id is verified.
        Entry(chipPrefix: "Apple A18", modelPrefix: nil, minimumMajor: 26, minimumMinor: 3, issue: .gammaNoOp),
    ]

    package static func issues(for host: HostDescription) -> Set<Issue> {
        var result: Set<Issue> = []
        for entry in entries where matches(entry, host) { result.insert(entry.issue) }
        return result
    }

    package static func gammaIsUnreliable(_ host: HostDescription) -> Bool {
        issues(for: host).contains(.gammaNoOp)
    }

    package static func reason(_ issue: Issue) -> String {
        switch issue {
        case .gammaNoOp:
            return L("Color tables have no visible effect on this Mac (a macOS bug); overlay dimming is used instead.")
        }
    }

    /// XDR extra brightness availability from static host facts only (PLAN §6.4): it needs
    /// Apple silicon (EDR + gamma > 1 and the EDR overlay are verified only there). Whether a
    /// given display has EDR headroom is checked per display, where the method is chosen.
    /// Nil when available, else the reason.
    package static func xdrUnavailableReason(_ host: HostDescription) -> String? {
        if host.isAppleSilicon { return nil }
        // `machdep.cpu.brand_string` can be empty; Apple silicon-only model ids ("Mac14,6") still tell.
        if host.chipName.isEmpty, isAppleSiliconOnlyModel(host.modelIdentifier) { return nil }
        return L("Extra brightness needs a Mac with Apple silicon")
    }

    /// "MacNN,M" model ids (2022 on) exist only on Apple silicon.
    package static func isAppleSiliconOnlyModel(_ modelIdentifier: String) -> Bool {
        guard modelIdentifier.hasPrefix("Mac") else { return false }
        let rest = modelIdentifier.dropFirst(3)
        guard let comma = rest.firstIndex(of: ","), let major = Int(rest[rest.startIndex..<comma]) else { return false }
        return major >= 13 && Int(rest[rest.index(after: comma)...]) != nil
    }

    private static func matches(_ entry: Entry, _ host: HostDescription) -> Bool {
        if let chip = entry.chipPrefix {
            guard host.chipName.lowercased().hasPrefix(chip.lowercased()) else { return false }
        }
        if let model = entry.modelPrefix {
            guard host.modelIdentifier.hasPrefix(model) else { return false }
        }
        if entry.chipPrefix == nil && entry.modelPrefix == nil { return false }
        if host.osMajor != entry.minimumMajor { return host.osMajor > entry.minimumMajor }
        return host.osMinor >= entry.minimumMinor
    }
}
