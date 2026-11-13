import Foundation

// The private capture path's pure rules (A2b; PLAN 0.5 §4.9, §4.12, §4.17; X-5, X2-8, X3-9): the content check and
// its recheck, the scale-down, and the Window Switcher page's stopped rows. `Windows/WindowCapture.swift` takes the
// pictures and `Windows/PrivateWindowAPI.swift` runs the probe; nothing here reads a clock, a window or a default.

/// §4.9's content check (X-5, X2-8, X3-9). A capture whose 16 × 16 luma has a standard deviation under 2 is
/// *suspect*: the card keeps its last-seen thumbnail or the icon. Three suspects in a row, from at least two windows,
/// run the probe-window capture again; a pattern pass makes those windows plain (their suspects are accepted from
/// then on), a shape-only pass accepts nothing, and a failed probe poisons the symbol (`WindowSymbolHealth`). Any
/// capture that isn't suspect resets the counter.
package struct CaptureContentCheck: Equatable, Sendable {
    /// The luma sample's side, as `CapturePattern.sampleSide`.
    package static let sampleSide = 16
    /// Under this standard deviation (0–255 luma) a capture is suspect.
    package static let suspectBelow = 2.0
    /// Suspects in a row that run the probe again…
    package static let recheckRun = 3
    /// …when they came from at least this many windows.
    package static let recheckWindows = 2

    /// What the caller does with one capture.
    package enum Verdict: Equatable, Sendable {
        /// Show and keep it.
        case accept
        /// Drop it: the card keeps its last-seen thumbnail or the icon.
        case suspect
        /// Drop it, and run the probe-window capture again (then call `recheckFinished`).
        case suspectRecheck
    }

    /// How the probe-window capture went when it ran again (§4.12 step 4).
    package enum Recheck: Equatable, Sendable {
        /// The image matched the pattern: the path works.
        case patternPass
        /// The result's shape passed, with no pattern check (X3-9). Never reached on 27.2, where S0-4 recorded that
        /// our own off-screen window captures, so the probe always checks the pattern.
        case shapeOnlyPass
        /// No answer, or the probe couldn't run (Safe Mode, a kill switch, the crash guard). Not a failure (X3-6).
        case noAnswer
        /// An impossible result: `WindowSymbolHealth` poisons the symbol (§4.12 step 5).
        case failed
    }

    /// Suspects in a row.
    package private(set) var run = 0
    /// The windows those suspects came from.
    package private(set) var runWindows: Set<UInt32> = []
    /// Windows a pattern pass showed are plain: their suspects are accepted.
    package private(set) var plain: Set<UInt32> = []
    /// The windows of the run that started a recheck still under way; nil when none is.
    package private(set) var rechecking: Set<UInt32>?

    package init() {}

    // MARK: The luma test

    /// The population standard deviation of a luma sample; nil for an empty one.
    package static func standardDeviation(_ sample: [UInt8]) -> Double? {
        guard !sample.isEmpty else { return nil }
        let count = Double(sample.count)
        let mean = sample.reduce(0.0) { $0 + Double($1) } / count
        let variance = sample.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / count
        return variance.squareRoot()
    }

    /// Suspect: a standard deviation under 2, or no sample at all (the image couldn't be read). A fully transparent
    /// capture (alpha 0, S0-10) draws as one flat value, so it's suspect too.
    package static func isSuspect(_ sample: [UInt8]?) -> Bool {
        guard let sample, let deviation = standardDeviation(sample) else { return true }
        return deviation < suspectBelow
    }

    // MARK: The counter

    /// One private capture of `window`. A suspect from a plain window is accepted and leaves the counter as it is.
    package mutating func record(window: UInt32, suspect: Bool) -> Verdict {
        guard suspect else {
            resetRun()
            return .accept
        }
        if plain.contains(window) { return .accept }
        run += 1
        runWindows.insert(window)
        guard rechecking == nil, run >= Self.recheckRun, runWindows.count >= Self.recheckWindows else {
            return .suspect
        }
        rechecking = runWindows
        return .suspectRecheck
    }

    /// The recheck's result. Every outcome resets the counter; a failure also forgets every plain window, since the
    /// path will have to prove itself again once the poisoning ends.
    package mutating func recheckFinished(_ result: Recheck) {
        guard let windows = rechecking else { return }
        switch result {
        case .patternPass: plain.formUnion(windows)
        case .shapeOnlyPass, .noAnswer: break
        case .failed: plain = []
        }
        rechecking = nil
        resetRun()
    }

    /// Windows that are gone lose their plain mark, so a reused id proves itself again.
    package mutating func keepPlain(_ windows: Set<UInt32>) {
        plain.formIntersection(windows)
    }

    private mutating func resetRun() {
        run = 0
        runWindows = []
    }
}

/// §4.9 Pacing: the private path runs one capture at a time at 1x, scaled down at once to the client's largest card
/// size × scale (`maxPixels` on the longer side). It never scales up.
package enum PrivateCaptureScaling {
    /// The pixel size to draw a `width` × `height` capture at; nil for an empty one.
    package static func scaledSize(width: Int, height: Int, maxPixels: Double) -> (width: Int, height: Int)? {
        guard width > 0, height > 0 else { return nil }
        let factor = scaleFactor(width: width, height: height, maxPixels: maxPixels)
        guard factor < 1 else { return (width, height) }
        return (max(1, Int((Double(width) * factor).rounded())), max(1, Int((Double(height) * factor).rounded())))
    }

    /// `min(1, maxPixels / longer side)`; 1 when `maxPixels` isn't a usable size.
    package static func scaleFactor(width: Int, height: Int, maxPixels: Double) -> Double {
        let longer = Double(max(width, height))
        guard longer > 0, maxPixels.isFinite, maxPixels >= 1 else { return 1 }
        return min(1, maxPixels / longer)
    }
}

// MARK: Diagnostics (§4.12 step 4, §4.13)

/// The Diagnostics report's window-capture lines (M1, M33). The state words are the plan's, unlocalized like the
/// symbol name they follow.
package enum PrivateCaptureDiagnostics {
    /// `safeMode` first; then a refused symbol's state (`unavailable`, `disabled`, `poisoned`); then the probe's
    /// phase: `notProbed` until the first private capture that passes every gate, `probing`, `passed` (also a pass
    /// cached for this build), or `noAnswer` while a probe with no answer waits for its retry.
    package static func hwCapture(safeMode: Bool, state: WindowSymbolState, phase: WindowSymbolHealth.Phase) -> String {
        if safeMode { return "safeMode" }
        guard state == .available else { return state.rawValue }
        switch phase {
        case .needsProbe: return "notProbed"
        case .probing: return "probing"
        case .passed: return "passed"
        case .retry: return "noAnswer"
        }
    }

    package static func lines(hwCapture: String, privateCaptures: Int) -> [String] {
        ["hwCapture: " + hwCapture, L("Private captures") + ": " + String(privateCaptures)]
    }
}

// MARK: Stopped rows (§4.17)

extension WindowFeature {
    /// The crash guard's row (§4.17; X2-24, D2-9), with [Try Again].
    package var crashGuardRowText: String {
        L("\(displayName) stopped after a problem in macOS. Snaptic tries again after a macOS update.")
    }

    /// A second poisoning's row (§4.12 step 5), with no button.
    package var poisonedRowText: String {
        L("\(displayName) stopped because macOS answered in a way Snaptic didn’t expect. Quit and reopen Snaptic to try again.")
    }
}

/// One added row on the Window Switcher page for a stopped window feature or the ⌘⇥ give-back.
package struct WindowStopRow: Equatable, Sendable {
    package enum Action: String, Sendable {
        /// `PrivateWindowAPI.tryAgain(feature)`: clears that feature's disabled builds.
        case tryAgain
        /// `SystemHotkeys.tryAgainGiveBack()`: clears only the give-back's disabled build and gives ⌘⇥ back now.
        case tryAgainGiveBack
    }

    /// The stopped feature; nil for the give-back row.
    package var feature: WindowFeature?
    package var text: String
    package var help: String?
    package var action: Action?

    package init(feature: WindowFeature?, text: String, help: String? = nil, action: Action?) {
        self.feature = feature
        self.text = text
        self.help = help
        self.action = action
    }
}

package enum WindowStopRows {
    /// The Window Switcher page's stopped rows (§4.17): every feature shows there, crash-guard stops first, then
    /// second poisonings, each in §4.12's table order. A feature the crash guard stopped shows only that row.
    package static func switcherPage(crashGuard: Set<WindowFeature>, poisoned: Set<WindowFeature>) -> [WindowStopRow] {
        let stopped = WindowFeature.allCases.filter { crashGuard.contains($0) }
        let lasting = WindowFeature.allCases.filter { poisoned.contains($0) && !crashGuard.contains($0) }
        return stopped.map { WindowStopRow(feature: $0, text: $0.crashGuardRowText, action: .tryAgain) }
            + lasting.map { WindowStopRow(feature: $0, text: $0.poisonedRowText, action: nil) }
    }

    /// The Dock Previews page's share (§4.17): only the features shown on both pages, in the same order and with the
    /// same rule (a feature the crash guard stopped isn't listed as poisoned). `DockPageRules` builds the rows from
    /// their display names.
    package static func dockPage(crashGuard: Set<WindowFeature>,
                                 poisoned: Set<WindowFeature>) -> (crashGuard: [WindowFeature], poisoned: [WindowFeature]) {
        let shown = WindowFeature.allCases.filter { !$0.switcherPageOnly }
        return (shown.filter { crashGuard.contains($0) },
                shown.filter { poisoned.contains($0) && !crashGuard.contains($0) })
    }

    /// The "⌘⇥ not given back" row (§4.12 step 6; X3-2, G3-2): on the Window Switcher page only, whatever the
    /// switcher's state, while `Windows.pendingGiveBack` holds a list. The text follows S0-5b's logout result.
    package static func giveBack(pending: Bool, comesBackAtLogout: Bool) -> WindowStopRow? {
        guard pending else { return nil }
        let text = comesBackAtLogout
            ? L("⌘⇥ may not switch apps until you log out, because Snaptic couldn’t turn it back on after a problem in macOS.")
            : L("⌘⇥ doesn’t switch apps, because Snaptic couldn’t turn it back on after a problem in macOS.")
        return WindowStopRow(feature: nil, text: text, help: L("This also affects ⌘⇧⇥ and ⌘ with the key above Tab."),
                             action: .tryAgainGiveBack)
    }
}
