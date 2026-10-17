import Foundation

// UI size matching across displays (owner: D). PLAN §9.1, R5.4 ("Match UI size…").
// One point should cover the same physical length on every display: pick, per target,
// the mode whose millimetres-per-point is closest to the reference display's.

package struct ScaleMatchDisplay: Equatable, Sendable {
    package var key: DisplayKey
    /// Physical width of the panel along the current mode's horizontal axis (after rotation).
    package var widthMM: Double
    package var current: ModeRef
    /// Modes the user could pick (public, desktop-usable).
    package var candidates: [ModeRef]

    package init(key: DisplayKey, widthMM: Double, current: ModeRef, candidates: [ModeRef]) {
        self.key = key
        self.widthMM = widthMM
        self.current = current
        self.candidates = candidates
    }
}

package struct ScaleMatchProposal: Equatable, Sendable {
    package var key: DisplayKey
    package var from: ModeRef
    package var to: ModeRef
    /// to's mm-per-point divided by the reference's (1.0 = perfect).
    package var ratio: Double

    package init(key: DisplayKey, from: ModeRef, to: ModeRef, ratio: Double) {
        self.key = key
        self.from = from
        self.to = to
        self.ratio = ratio
    }
}

package enum ScaleMatch {
    package static let defaultTolerance = 0.10

    /// Millimetres one point covers on this display in this mode.
    package static func mmPerPoint(widthMM: Double, mode: ModeRef) -> Double? {
        guard widthMM.isFinite, widthMM > 1, mode.pointWidth > 0 else { return nil }
        return widthMM / Double(mode.pointWidth)
    }

    /// The candidate closest to `targetMMPerPoint`. Prefers the current refresh rate and
    /// HiDPI class, then the closest size; ties go to the larger desktop.
    package static func bestMode(targetMMPerPoint: Double, widthMM: Double, current: ModeRef,
                                 candidates: [ModeRef]) -> (mode: ModeRef, ratio: Double)? {
        guard targetMMPerPoint.isFinite, targetMMPerPoint > 0 else { return nil }
        var best: (mode: ModeRef, ratio: Double, score: Double)?
        for c in candidates {
            guard let mm = mmPerPoint(widthMM: widthMM, mode: c) else { continue }
            let ratio = mm / targetMMPerPoint
            // Log distance treats 0.9× and 1.11× alike.
            var score = abs(log(ratio))
            if c.isHiDPI != current.isHiDPI { score += 0.05 }
            if c.refreshMilliHz != current.refreshMilliHz { score += 0.02 }
            if let b = best {
                if score < b.score - 1e-9 || (abs(score - b.score) <= 1e-9 && c.pointWidth > b.mode.pointWidth) {
                    best = (c, ratio, score)
                }
            } else {
                best = (c, ratio, score)
            }
        }
        return best.map { ($0.mode, $0.ratio) }
    }

    /// Proposals that bring each target within `tolerance` of the reference. Targets already
    /// within tolerance, or without a better mode, get no proposal.
    package static func plan(reference: ScaleMatchDisplay, targets: [ScaleMatchDisplay],
                             tolerance: Double = defaultTolerance) -> [ScaleMatchProposal] {
        guard let refMM = mmPerPoint(widthMM: reference.widthMM, mode: reference.current) else { return [] }
        let tol = min(0.5, max(0.01, tolerance.isFinite ? tolerance : defaultTolerance))
        var result: [ScaleMatchProposal] = []
        for t in targets where t.key != reference.key {
            guard let currentMM = mmPerPoint(widthMM: t.widthMM, mode: t.current) else { continue }
            let currentError = abs(log(currentMM / refMM))
            if currentError <= log(1 + tol) { continue }
            guard let pick = bestMode(targetMMPerPoint: refMM, widthMM: t.widthMM, current: t.current, candidates: t.candidates),
                  pick.mode != t.current, abs(log(pick.ratio)) < currentError else { continue }
            result.append(ScaleMatchProposal(key: t.key, from: t.current, to: pick.mode, ratio: pick.ratio))
        }
        return result
    }
}
