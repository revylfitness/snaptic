import Foundation

// Transaction risk from the changes themselves (owner: B). PLAN §4.3: the queue uses
// max(caller risk, classifier). Known-good sets are per display, by full ModeRef.

/// Kit mirror of the app's TransactionRisk (same order).
package enum RiskLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    case low, restore, trial
    package static func < (a: RiskLevel, b: RiskLevel) -> Bool { a.rawValue < b.rawValue }
}

/// "Confirm resolution changes" (PLAN §4.3).
package enum ConfirmResolutionChanges: String, Codable, CaseIterable, Sendable {
    /// Ask for modes that aren't known-good (default).
    case newModesOnly
    /// Ask for every mode change.
    case always
    /// Never ask for modes from the public list; CGS (hidden) modes still ask.
    case neverForPublic
}

/// What the classifier knows about one display's modes.
package struct ModeFacts: Equatable, Sendable {
    /// Native, default, kept, and (built-in panels) every usable mode at the current refresh.
    package var knownGood: Set<ModeRef>
    /// Every mode in the public list (CGDisplayCopyAllDisplayModes).
    package var publicModes: Set<ModeRef>

    package init(knownGood: Set<ModeRef> = [], publicModes: Set<ModeRef> = []) {
        self.knownGood = knownGood
        self.publicModes = publicModes
    }

    package func isKnownGood(_ m: ModeRef) -> Bool { knownGood.contains { $0 == m || $0.sameShape(as: m) } }
    package func isPublic(_ m: ModeRef) -> Bool { publicModes.contains { $0 == m || $0.sameShape(as: m) } }
}

package enum RiskClassifier {
    /// The known-good set for a display (PLAN §4.3).
    package static func knownGood(modes: [DisplayModeDescriptor], current: ModeRef?, isBuiltin: Bool,
                                  kept: Set<ModeRef>) -> Set<ModeRef> {
        var set = kept
        for m in modes where m.isNative || m.isDefault { set.insert(m.ref) }
        if isBuiltin, let current {
            for m in modes where m.isUsableForDesktop && m.cgsModeNumber == nil
                && abs(m.ref.refreshMilliHz - current.refreshMilliHz) <= 10 {
                set.insert(m.ref)
            }
        }
        if let current { set.insert(current) }
        return set
    }

    /// The risk of one change.
    package static func classify(_ change: DisplayChange, current: LayoutSnapshot, facts: ModeFacts,
                                 setting: ConfirmResolutionChanges) -> RiskLevel {
        switch change {
        case .origin:
            return .low
        case .main(let id):
            return Invariants.stronglyVisible(current).contains(id) ? .low : .trial
        case .mode(let id, let m):
            if let live = current.entry(id)?.mode, live == m || live.sameShape(as: m) { return .low }
            guard facts.isPublic(m) else { return .trial }          // CGS / hidden modes always confirm
            switch setting {
            case .always: return .trial
            case .neverForPublic: return .low
            case .newModesOnly: return facts.isKnownGood(m) ? .low : .trial
            }
        case .mirror(let id, let source):
            return current.entry(id)?.mirrorOf == source ? .low : .trial
        case .enabled(let id, let on):
            return current.entry(id)?.isEnabled == on ? .low : .trial
        case .rotation(let id, let degrees):
            return current.entry(id)?.rotation == Invariants.normalizedRotation(degrees) ? .low : .trial
        case .underscan(let id, let value):
            if let live = current.entry(id)?.underscan, abs(live - value) < 0.001 { return .low }
            return .trial
        case .hdr(let id, let on):
            return current.entry(id)?.hdrEnabled == on ? .low : .trial
        }
    }

    /// The highest risk over a request (empty requests are low).
    package static func classify(_ changes: [DisplayChange], current: LayoutSnapshot,
                                 facts: (UInt32) -> ModeFacts, setting: ConfirmResolutionChanges) -> RiskLevel {
        changes.map { classify($0, current: current, facts: facts($0.displayID), setting: setting) }.max() ?? .low
    }
}
