import Foundation
import SnapticKit
import SnapticShims

/// Hidden Icons' private API gate (lead; PLAN 0.4 §4.2.2, H3, H8, H12; B1). The framework and classes are looked up
/// only inside `SNMenuBarVisibility` (lint rule 11); this file checks the five encodings against Kit's
/// `IconsShimContract`, marks the shim verified when every one matches (all or nothing), and reads the
/// `Icons.disable.*` kill switches. `NativeBackend` (A2) drives the shim through this gate's result only.
enum PrivateMenuBarAPI {
    /// One probe: whether the classes exist, which encodings differ, and the shim state after marking.
    struct Probe: Equatable {
        let present: Bool
        let mismatches: [IconsShimContract.Requirement]
        let state: IconsShimState
    }

    private static let lock = NSLock()
    private static var checked: (present: Bool, mismatches: [IconsShimContract.Requirement])?

    /// Checks the encodings once per process and marks the shim verified when all match; later calls report the
    /// same check with the live state (the shim can be poisoned at any time). It never activates an assertion and
    /// never touches Accessibility, so `--selftest-launch` may call it (lint rule 9).
    static func verify() -> Probe {
        lock.lock()
        defer { lock.unlock() }
        let check: (present: Bool, mismatches: [IconsShimContract.Requirement])
        if let checked {
            check = checked
        } else {
            let present = SNMenuBarVisibility.isPresent()
            let mismatches = present
                ? IconsShimContract.mismatches { SNMenuBarVisibility.rawEncoding(className: $0, selector: $1) }
                : IconsShimContract.requirements
            if present && mismatches.isEmpty {
                for r in IconsShimContract.requirements {
                    SNMenuBarVisibility.markVerified(className: r.className, selector: r.encoding.selector)
                }
            }
            check = (present, mismatches)
            checked = check
        }
        return Probe(present: check.present, mismatches: check.mismatches,
                     state: IconsShimContract.state(present: check.present, poisoned: SNMenuBarVisibility.isPoisoned(),
                                                    mismatches: check.mismatches))
    }

    /// The current state without re-probing (poisoning can happen at any time).
    static var state: IconsShimState {
        if SNMenuBarVisibility.isPoisoned() { return .poisoned }
        return SNMenuBarVisibility.isAvailable() ? .available : .unavailable
    }

    /// `Icons.disable.<feature>` from Hidden Icons' defaults domain (H3).
    @MainActor static func killSwitches(_ defaults: UserDefaults = .standard) -> Set<IconsFeature> {
        KillSwitches.read(defaults.persistentDomain(forName: ConfigStore<IconsConfig>.persistentDomainName),
                          prefix: IconsFeature.prefix, as: IconsFeature.self)
    }

    /// `--selftest-launch` only (debug builds): poisons the shim through its own exception handler, then reports
    /// whether it is poisoned and still available. The shim stays poisoned for the rest of the process.
    static func forcePoisonForSelfTest() -> (poisoned: Bool, available: Bool) {
        SNMenuBarVisibility.simulateExceptionForSelfTest()
        return (SNMenuBarVisibility.isPoisoned(), SNMenuBarVisibility.isAvailable())
    }

    /// Diagnostics rows (H12): the shim state and the encodings matched (y/n).
    static func diagnosticsRows() -> [(String, String)] {
        let probe = verify()
        return IconsShimContract.diagnosticsRows(state: state, mismatches: probe.mismatches)
    }
}
