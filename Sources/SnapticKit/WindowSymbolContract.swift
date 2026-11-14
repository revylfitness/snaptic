import Foundation

// The C-symbol contract for the window services (lead; PLAN 0.5 §4.12, H3, H6; B1b): the symbols, their images and
// features, the OS gate, the result classes, the probe and poison state machine, each feature's fallback, and the
// `--selftest-launch` lines. `PrivateWindowAPI` (app) owns the C names and the lookups; nothing here calls macOS.

/// Per-feature kill switches (H6): `Windows.disable.<rawValue>` = true in Snaptic's persistent domain turns the
/// feature off, read with `KillSwitches.read(domain, prefix: "Windows", as: WindowFeature.self)` once per batch. One
/// key per feature, not per symbol (P2-8). Declaration order is §4.12's table order, which the §4.17 rows follow.
package enum WindowFeature: String, Codable, CaseIterable, Sendable {
    case hwCapture, axWindowID, raise, spaces, symbolicHotKeys, layoutType

    /// The §4.17 display name, used inside "\(feature) stopped after a problem in macOS. …".
    package var displayName: String {
        switch self {
        case .hwCapture: return L("Thumbnails of minimized windows and windows on other Spaces")
        case .axWindowID: return L("Matching cards to their windows")
        case .raise: return L("Bringing windows forward from other Spaces")
        case .spaces: return L("Showing windows on other Spaces")
        case .symbolicHotKeys: return L("Using ⌘⇥ for the Window Switcher")
        case .layoutType: return L("Reading the keyboard layout")
        }
    }

    /// The feature's stopped row shows on the Window Switcher page only (§4.17); the rest show on both pages.
    package var switcherPageOnly: Bool { self == .symbolicHotKeys || self == .layoutType }

    package var killSwitchKey: String { KillSwitches.key(prefix: "Windows", id: rawValue) }
}

/// The system image a symbol must come from (§4.12 step 1; S0-5). Every path is `/System/Library/…/Versions/A/…`.
package enum WindowSymbolImage: String, CaseIterable, Sendable {
    case skyLight = "SkyLight"
    case hiServices = "HIServices"
    case hiToolbox = "HIToolbox"

    /// `dladdr`'s `dli_fname` only: an alias's `dli_sname` names the SLS twin at the same address (S0-5).
    package func matches(path: String?) -> Bool {
        guard let path, path.hasPrefix("/System/Library/") else { return false }
        return (path as NSString).lastPathComponent == rawValue
    }
}

/// One entry of §4.12's symbol table. The raw value names the crash marker (`inflight/<rawValue>`) and the defaults
/// keys (`Windows.*Build.<rawValue>`); the C names live in `PrivateWindowAPI` only (L2).
package enum WindowSymbolID: String, CaseIterable, Sendable {
    case hwCapture
    case axGetWindow
    case getProcessForPID
    case setFrontProcess
    case postEventRecord
    case mainConnection
    case copySpaces
    case isSymbolicHotKeyEnabled
    case setSymbolicHotKeyEnabled
    case layoutType
    case kbdType

    package var feature: WindowFeature {
        switch self {
        case .hwCapture: return .hwCapture
        case .axGetWindow: return .axWindowID
        case .getProcessForPID, .setFrontProcess, .postEventRecord: return .raise
        case .mainConnection, .copySpaces: return .spaces
        case .isSymbolicHotKeyEnabled, .setSymbolicHotKeyEnabled: return .symbolicHotKeys
        case .layoutType, .kbdType: return .layoutType
        }
    }

    package var image: WindowSymbolImage {
        switch self {
        case .axGetWindow, .getProcessForPID: return .hiServices
        case .layoutType, .kbdType: return .hiToolbox
        default: return .skyLight
        }
    }

    /// The Read-only column. Only read-only symbols stop writing their marker once verified (X2-4).
    package var readOnly: Bool {
        switch self {
        case .axGetWindow, .mainConnection, .copySpaces, .isSymbolicHotKeyEnabled, .layoutType, .kbdType: return true
        case .hwCapture, .getProcessForPID, .setFrontProcess, .postEventRecord, .setSymbolicHotKeyEnabled: return false
        }
    }

    /// Its use is new in 0.5, so it runs only on a verified major (X3-1). Everything else 0.4 already calls.
    package var newIn05: Bool { self == .hwCapture }

    /// Looked up as `SLS…` in SkyLight first, then `CGS…`; the selftest line names the variant found.
    package var hasAlias: Bool {
        switch self {
        case .mainConnection, .copySpaces, .isSymbolicHotKeyEnabled, .setSymbolicHotKeyEnabled: return true
        default: return false
        }
    }

    /// Checked for presence only at the probe step: the raise trio (a probe would move windows), the hotkey pair
    /// (the setter's read-back runs at the first take) and `LMGetKbdType` (the layout probe uses its value).
    package var presenceOnlyProbe: Bool {
        switch self {
        case .getProcessForPID, .setFrontProcess, .postEventRecord,
             .isSymbolicHotKeyEnabled, .setSymbolicHotKeyEnabled, .kbdType: return true
        default: return false
        }
    }

    package static func symbols(for feature: WindowFeature) -> [WindowSymbolID] {
        allCases.filter { $0.feature == feature }
    }
}

package enum WindowSymbolVariant: String, Sendable {
    case sls = "SLS"
    case cgs = "CGS"
}

/// §4.12: a feature works while every symbol it needs is `available`.
package enum WindowSymbolState: String, CaseIterable, Sendable {
    case available, unavailable, disabled, poisoned
}

/// The OS gate (§4.12 step 2; X2-2, X3-1): only what's new in 0.5 waits for a verified major.
package enum WindowOSGate {
    /// Majors S0 has run on (15 and 27 in 0.5.0). 14 and 26 join only when STEP0-NOTES records their legs.
    package static let verifiedMajors: Set<Int> = [15, 27]
    /// 0.4's floor: its symbols run on every major from here up, verified or not.
    package static let minimumMajor = 14

    package static func isVerified(major: Int) -> Bool { verifiedMajors.contains(major) }

    package static func allows(_ id: WindowSymbolID, major: Int) -> Bool {
        guard major >= minimumMajor else { return false }
        return id.newIn05 ? isVerified(major: major) : true
    }
}

/// What `PrivateWindowAPI` found for one symbol at lookup.
package struct WindowSymbolLookup: Equatable, Sendable {
    package var present: Bool
    /// `dli_fname`; nil when `dladdr` gave nothing.
    package var imagePath: String?
    package var variant: WindowSymbolVariant?

    package init(present: Bool, imagePath: String? = nil, variant: WindowSymbolVariant? = nil) {
        self.present = present
        self.imagePath = imagePath
        self.variant = variant
    }

    package static let absent = WindowSymbolLookup(present: false)
}

/// One symbol's state as diagnostics and the selftest report it.
package struct WindowSymbolReport: Equatable, Sendable {
    /// The C name (an alias pair's name without its `SLS`/`CGS` prefix).
    package var name: String
    package var state: WindowSymbolState
    package var variant: WindowSymbolVariant?
    /// Found outside its image (reported on an unverified major; `unavailable` on a verified one).
    package var imageMoved: Bool

    package init(name: String, state: WindowSymbolState, variant: WindowSymbolVariant? = nil, imageMoved: Bool = false) {
        self.name = name
        self.state = state
        self.variant = variant
        self.imageMoved = imageMoved
    }
}

/// §4.12 step 5 (X2-1): every result is one of three classes. Only `impossible` counts toward poisoning.
package enum WindowResultClass: String, Sendable {
    case answer, noAnswer, impossible
}

/// The shape of a `CFArray` result, read by the app and classified here.
package enum WindowArrayShape: Equatable, Sendable {
    case null
    case notArray
    case empty
    /// Every element has the expected type; the sizes are `CGImage` widths and heights (capture only).
    case elements([WindowImageSize])
    /// At least one element has another type.
    case wrongElement
}

package struct WindowImageSize: Equatable, Sendable {
    package var width: Int
    package var height: Int

    package init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// The capture probe's result as the app read it.
package struct WindowCaptureProbeResult: Equatable, Sendable {
    package var shape: WindowArrayShape
    /// The first image downsampled to `CapturePattern.sampleSide`² greyscale; nil when it couldn't be read.
    package var sample: [UInt8]?

    package init(shape: WindowArrayShape, sample: [UInt8]?) {
        self.shape = shape
        self.sample = sample
    }
}

package enum WindowResults {
    /// `kAXErrorCannotComplete`, `InvalidUIElement`, `APIDisabled`, `NotImplemented`, `AttributeUnsupported`.
    package static let axNoAnswerErrors: Set<Int32> = [-25204, -25202, -25211, -25208, -25205]

    /// `'ANSI'`, `'ISO '`, `'JIS '` (`KBGetLayoutType`), and `'????'` (`kKeyboardUnknown`), which is no answer.
    package static let layoutANSI: UInt32 = 0x414E_5349
    package static let layoutISO: UInt32 = 0x4953_4F20
    package static let layoutJIS: UInt32 = 0x4A49_5320
    package static let layoutUnknown: UInt32 = 0x3F3F_3F3F

    /// `_AXUIElementGetWindow`: the target app answers, so nothing counts. The id is checked against the window
    /// server's owner list by `WindowCatalogRules.trustedWindowID`, and a mismatch drops that one id.
    package static func ax(error: Int32, windowID: UInt32) -> WindowResultClass {
        error == 0 && windowID != 0 ? .answer : .noAnswer
    }

    /// The AX probe on our own probe window, sent from the probe queue: one result per element of our `AXWindows`.
    /// An error or an empty list is no answer; calls that succeed but never name the probe window are impossible.
    package static func axProbe(_ results: [(error: Int32, windowID: UInt32)], expected: UInt32) -> WindowResultClass {
        if results.contains(where: { $0.error == 0 && $0.windowID == expected && expected != 0 }) { return .answer }
        return results.contains(where: { $0.error == 0 }) ? .impossible : .noAnswer
    }

    /// `SLS`/`CGSMainConnectionID`: 0 is impossible.
    package static func mainConnection(_ value: Int32) -> WindowResultClass { value == 0 ? .impossible : .answer }

    /// The probe: nonzero, and equal to the twin when both variants exist.
    package static func mainConnectionProbe(sls: Int32?, cgs: Int32?) -> WindowResultClass {
        let values = [sls, cgs].compactMap { $0 }
        guard let first = values.first else { return .noAnswer }
        if values.contains(0) { return .impossible }
        return values.allSatisfy { $0 == first } ? .answer : .impossible
    }

    /// `SLS`/`CGSCopySpacesForWindows`: NULL or empty (a window with no Space, or gone) is no answer; anything but
    /// an array of `CFNumber` is impossible.
    package static func copySpaces(_ shape: WindowArrayShape) -> WindowResultClass {
        switch shape {
        case .null, .empty: return .noAnswer
        case .notArray, .wrongElement: return .impossible
        case .elements: return .answer
        }
    }

    /// `SLS`/`CGSSetSymbolicHotKeyEnabled`: a nonzero `CGError`, or a read-back that disagrees, is impossible.
    package static func setSymbolicHotKey(error: Int32, readBack: Bool?, wanted: Bool) -> WindowResultClass {
        if error != 0 { return .impossible }
        if let readBack, readBack != wanted { return .impossible }
        return .answer
    }

    /// `KBGetLayoutType` (X3-6): `'????'` is no answer and reads as ANSI; an unknown value is impossible.
    package static func layout(_ value: UInt32) -> WindowResultClass {
        switch value {
        case layoutANSI, layoutISO, layoutJIS: return .answer
        case layoutUnknown: return .noAnswer
        default: return .impossible
        }
    }

    /// The raise trio: any error is no answer.
    package static func raise(error: Int32) -> WindowResultClass { error == 0 ? .answer : .noAnswer }

    /// §4.9 shape: at most 4× the window's pixels at the largest screen scale. Nil when the bounds or scale can't
    /// give a limit (the check is then skipped).
    package static func pixelLimit(windowWidth: Double, windowHeight: Double, maxScale: Double) -> Double? {
        let limit = 4 * (windowWidth * maxScale) * (windowHeight * maxScale)
        return limit.isFinite && limit > 0 ? limit : nil
    }

    /// `CGSHWCaptureWindowList` (X2-1, PC-2): NULL or empty (closed, or on no display) is no answer; not an array
    /// of `CGImage`, a zero width, or more pixels than `pixelLimit` is impossible.
    package static func capture(_ shape: WindowArrayShape, pixelLimit: Double?) -> WindowResultClass {
        switch shape {
        case .null, .empty: return .noAnswer
        case .notArray, .wrongElement: return .impossible
        case .elements(let sizes):
            for size in sizes {
                if size.width <= 0 || size.height <= 0 { return .impossible }
                if let pixelLimit, Double(size.width) * Double(size.height) > pixelLimit { return .impossible }
            }
            return .answer
        }
    }

    /// The capture probe (PC-1): the shape first, then the pattern. An image that doesn't match is impossible.
    package static func captureProbe(_ result: WindowCaptureProbeResult, pixelLimit: Double?) -> WindowResultClass {
        let shape = capture(result.shape, pixelLimit: pixelLimit)
        guard shape == .answer else { return shape }
        guard let sample = result.sample else { return .noAnswer }
        return CapturePattern.passes(sample: sample) ? .answer : .impossible
    }
}

/// The capture probe window's two-colour pattern (PC-1): vertical stripes, black first, so a vertical flip of the
/// image reads the same. Compared as a 16 × 16 greyscale downsample; it passes under 10% mean absolute difference.
package enum CapturePattern {
    package static let side = 64
    package static let stripeWidth = 16
    package static let sampleSide = 16
    package static let passBelow = 0.10

    /// Whether the window's column `x` (0 ..< side, in points from the left) is white.
    package static func isWhite(column x: Int) -> Bool { (x / stripeWidth) % 2 == 1 }

    /// The expected downsample, row by row.
    package static var expectedSample: [UInt8] {
        let cell = side / sampleSide
        let row = (0..<sampleSide).map { isWhite(column: $0 * cell + cell / 2) ? UInt8(255) : UInt8(0) }
        return Array((0..<sampleSide).map { _ in row }.joined())
    }

    /// Mean absolute difference from the expected sample, 0…1; nil for a sample of the wrong size.
    package static func difference(sample: [UInt8]) -> Double? {
        let expected = expectedSample
        guard sample.count == expected.count else { return nil }
        let total = zip(sample, expected).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(total) / Double(expected.count * 255)
    }

    package static func passes(sample: [UInt8]) -> Bool {
        guard let d = difference(sample: sample) else { return false }
        return d < passBelow
    }
}

/// One symbol's probe and poison bookkeeping (§4.12 steps 4–5; P2-14, X3-3, X3-6). Times are injected seconds on a
/// monotonic clock; nothing here reads a clock.
package struct WindowSymbolHealth: Equatable, Sendable {
    /// A probe with no answer is retried at the next use, at most this often (X3-6).
    package static let noAnswerRetry: Double = 60
    /// A poisoned symbol is probed again after this long; a pass clears it (P2-14).
    package static let poisonRetry: Double = 600
    /// Impossible results in a row that poison (X2-1).
    package static let impossibleRunToPoison = 2

    package enum Phase: Equatable, Sendable {
        case needsProbe
        case probing
        case passed
        case retry(at: Double)
    }

    /// What the next real use does.
    package enum Use: Equatable, Sendable {
        /// Make the private call.
        case call
        /// Run the probe first (this caller owns it); the caller takes the fallback, except the capture, which waits.
        case probe
        /// Take the fallback for this call.
        case fallback
    }

    package enum ProbeOutcome: Equatable, Sendable {
        /// Cache `Windows.probedBuild.<symbol>`; `clearedPoison` when it ended a poisoning.
        case passed(clearedPoison: Bool)
        case noAnswer
        /// The symbol is now poisoned; `lasting` when this was its second poisoning.
        case poisoned(lasting: Bool)
    }

    package private(set) var phase: Phase
    package private(set) var poisoned = false
    /// A second poisoning, or a forced one: it lasts until Snaptic quits.
    package private(set) var lasting = false
    package private(set) var poisonings = 0
    package private(set) var impossibleRun = 0

    /// A pass on this OS build, cached in `Windows.probedBuild.<symbol>`, skips the probe (X3-3). Presence-only
    /// symbols have nothing to probe.
    package init(_ id: WindowSymbolID, probedBuild: String?, currentBuild: String) {
        let cached = !currentBuild.isEmpty && probedBuild == currentBuild
        phase = cached || id.presenceOnlyProbe ? .passed : .needsProbe
    }

    package mutating func nextUse(now: Double) -> Use {
        if lasting { return .fallback }
        switch phase {
        case .passed: return .call
        case .probing: return .fallback
        case .needsProbe:
            phase = .probing
            return .probe
        case .retry(let at):
            guard now >= at else { return .fallback }
            phase = .probing
            return .probe
        }
    }

    /// The probe's verdict. No answer isn't a failure; only an impossible result fails it.
    package mutating func probeFinished(_ result: WindowResultClass, now: Double) -> ProbeOutcome {
        if lasting { return .poisoned(lasting: true) }
        switch result {
        case .answer:
            let cleared = poisoned
            poisoned = false
            impossibleRun = 0
            phase = .passed
            return .passed(clearedPoison: cleared)
        case .noAnswer:
            phase = .retry(at: now + Self.noAnswerRetry)
            return .noAnswer
        case .impossible:
            return .poisoned(lasting: poison(now: now))
        }
    }

    /// A real call's result. Only `.answer` ends a run of impossible results; no answers never count either way.
    /// Returns true when this result poisoned the symbol.
    @discardableResult
    package mutating func record(_ result: WindowResultClass, now: Double) -> Bool {
        guard !poisoned, !lasting else { return false }
        switch result {
        case .answer: impossibleRun = 0
        case .noAnswer: break
        case .impossible:
            impossibleRun += 1
            if impossibleRun >= Self.impossibleRunToPoison {
                poison(now: now)
                return true
            }
        }
        return false
    }

    /// Poisons now: the first time for `poisonRetry`, the second until quit. Returns whether it lasts.
    @discardableResult
    package mutating func poison(now: Double) -> Bool {
        poisonings += 1
        poisoned = true
        impossibleRun = 0
        if poisonings >= 2 {
            lasting = true
            phase = .retry(at: .infinity)
        } else {
            phase = .retry(at: now + Self.poisonRetry)
        }
        return lasting
    }

    /// The setter's read-back at the first take, and the DEBUG selftest: poisoned for the process.
    package mutating func poisonForProcess() {
        poisonings = max(poisonings, 2)
        poisoned = true
        lasting = true
        impossibleRun = 0
        phase = .retry(at: .infinity)
    }
}

/// `IsSecureEventInputEnabled` (X2-2): `unknown` when the symbol is missing.
package enum SecureInputState: String, Sendable {
    case off, on, unknown

    /// The selftest's view: the symbol was found or not.
    package var launchValue: String { self == .unknown ? "unknown" : "available" }
}

/// `watchSecureInput`'s decision (X2-2): `on` gives ⌘⇥ back and cancels the switcher, `unknown` only gives ⌘⇥
/// back, and a stopped tap or a lost trust does both, as in 0.4.
package struct SecureInputVerdict: Equatable, Sendable {
    package var suspendTake: Bool
    package var cancel: Bool

    package init(suspendTake: Bool, cancel: Bool) {
        self.suspendTake = suspendTake
        self.cancel = cancel
    }

    package static func decide(_ state: SecureInputState, tapEnabled: Bool, trusted: Bool) -> SecureInputVerdict {
        let blind = !tapEnabled || !trusted
        return SecureInputVerdict(suspendTake: state != .off || blind, cancel: state == .on || blind)
    }
}

/// Each feature's fallback (§4.12 table). The fallbacks run in M6, M16 and the S0 harness.
package enum WindowFallback: String, Sendable {
    /// Last-seen, then the icon.
    case lastSeenThenIcon
    /// Match by title and frame; cards without a match offer only Bring Forward.
    case matchByTitleAndFrame
    /// `kAXRaiseAction` plus activate, with `yieldActivation` first when needed (S0-27). Another Space then only
    /// activates the app.
    case axRaiseThenActivate
    /// The other-Space list is dropped (P-19).
    case dropOtherSpaces
    /// macOS keeps ⌘⇥; giving it back always runs, except under its own crash guard (H6).
    case systemKeepsCommandTab
    /// The ANSI layout.
    case ansiLayout
}

package enum WindowSymbolContract {
    package static func fallback(for feature: WindowFeature) -> WindowFallback {
        switch feature {
        case .hwCapture: return .lastSeenThenIcon
        case .axWindowID: return .matchByTitleAndFrame
        case .raise: return .axRaiseThenActivate
        case .spaces: return .dropOtherSpaces
        case .symbolicHotKeys: return .systemKeepsCommandTab
        case .layoutType: return .ansiLayout
        }
    }

    /// The image check (§4.12 step 1). On a verified major a moved image is `unavailable`; elsewhere it's only
    /// reported, so 0.4's symbols keep working on a newer macOS.
    package static func imageMoved(_ id: WindowSymbolID, lookup: WindowSymbolLookup) -> Bool {
        lookup.present && !id.image.matches(path: lookup.imagePath)
    }

    /// Poisoned wins, then disabled (crash guard or kill switch), then unavailable (absent, moved image on a verified
    /// major, or the OS gate).
    package static func state(_ id: WindowSymbolID, lookup: WindowSymbolLookup, major: Int,
                              disabled: Bool, poisoned: Bool) -> WindowSymbolState {
        if poisoned { return .poisoned }
        if disabled { return .disabled }
        if !lookup.present || !WindowOSGate.allows(id, major: major) { return .unavailable }
        if WindowOSGate.isVerified(major: major) && imageMoved(id, lookup: lookup) { return .unavailable }
        return .available
    }

    /// A feature works while every symbol it needs is available.
    package static func featureWorks(_ feature: WindowFeature,
                                     states: [WindowSymbolID: WindowSymbolState]) -> Bool {
        WindowSymbolID.symbols(for: feature).allSatisfy { states[$0] == .available }
    }

    // MARK: Selftest (P-8, P2-7, P2-18, D2-12)

    /// `SNAPTIC_SELFTEST_EXPECT_WINDOWS_API`: unset, the lines are only reported. CI on macOS 15 sets `available`.
    package static let expectVariable = "SNAPTIC_SELFTEST_EXPECT_WINDOWS_API"

    package static func launchLine(_ report: WindowSymbolReport) -> String {
        var line = "selftest-launch: windows " + report.name + " " + report.state.rawValue
        if let variant = report.variant { line += " " + variant.rawValue }
        return line
    }

    /// One line per symbol, in table order, then the secure-input line.
    package static func launchLines(_ reports: [WindowSymbolReport], secureInput: SecureInputState) -> [String] {
        reports.map(launchLine) + ["selftest-launch: windows secureInput " + secureInput.launchValue]
    }

    /// Fails on any poisoned symbol; with the expectation set, on any other state, on secure input `unknown` when
    /// `available` is expected, and on an expectation it can't read.
    package static func selfTestProblems(_ reports: [WindowSymbolReport], secureInput: SecureInputState,
                                         expect: String?) -> [String] {
        var problems = reports.filter { $0.state == .poisoned }.map { "window symbol " + $0.name + " is poisoned" }
        guard let expect else { return problems }
        guard let wanted = WindowSymbolState(rawValue: expect), wanted != .poisoned else {
            return problems + [expectVariable + " must be available, unavailable or disabled"]
        }
        for report in reports where report.state != wanted && report.state != .poisoned {
            problems.append("expected window symbol " + report.name + " " + wanted.rawValue
                            + ", found " + report.state.rawValue)
        }
        if wanted == .available && secureInput == .unknown {
            problems.append("expected secureInput available, found unknown")
        }
        return problems
    }

    /// The forced-poison check (debug builds): every symbol poisoned, none available.
    package static func poisonProblems(_ reports: [WindowSymbolReport]) -> [String] {
        var problems: [String] = []
        if reports.isEmpty { problems.append("no window symbols were reported") }
        for report in reports where report.state != .poisoned {
            problems.append("window symbol " + report.name + " reports " + report.state.rawValue + " after poisoning")
        }
        return problems
    }

    package static func poisonLine(_ problems: [String]) -> String {
        "selftest-launch: windows poison path " + (problems.isEmpty ? "ok" : "failed")
    }
}
