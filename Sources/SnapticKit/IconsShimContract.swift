import Foundation

// The Native shim's contract (lead; PLAN 0.4 §4.2.2, H8, H12, B1): the five encodings `PrivateMenuBarAPI` checks
// before it marks `SNMenuBarVisibility` verified, the shim state reported in diagnostics and by
// `--selftest-launch`, and that self-test's verdict. Any mismatch means unavailable; there is no compile flag.

package enum IconsShimState: String, CaseIterable, Sendable {
    case available, unavailable, poisoned
}

package enum IconsShimContract {
    package static let configurationClass = "MBAssessmentModeConfiguration"
    package static let assertionClass = "MBAssessmentModeAssertion"

    package struct Requirement: Equatable, Sendable {
        package var className: String
        package var encoding: KitEncoding.Requirement

        package init(_ className: String, _ selector: String, _ expected: String) {
            self.className = className
            encoding = KitEncoding.Requirement(selector, expected)
        }

        /// "Class selector", as diagnostics and the self-test name it.
        package var name: String { className + " " + encoding.selector }
    }

    /// Verified on 27.2 (26B123), S0-1.
    package static let requirements: [Requirement] = [
        Requirement(configurationClass, "initWithAllowedSystemItems:allowedBundleIdentifiers:", "@32@0:8@16@24"),
        Requirement(configurationClass, "initWithUnrestrictedMenuBarItems", "@16@0:8"),
        Requirement(assertionClass, "init", "@16@0:8"),
        Requirement(assertionClass, "activateWithConfiguration:completionHandler:", "v32@0:8@16@?24"),
        Requirement(assertionClass, "invalidate", "v16@0:8"),
    ]

    /// The requirements whose selector is missing or whose encoding differs, in table order (empty: all match).
    package static func mismatches(actual: (_ className: String, _ selector: String) -> String?) -> [Requirement] {
        requirements.filter { r in
            guard let a = actual(r.className, r.encoding.selector) else { return true }
            return !KitEncoding.matches(actual: a, expected: r.encoding.expected)
        }
    }

    /// Poisoned wins; otherwise available only when the classes are present and every encoding matched.
    package static func state(present: Bool, poisoned: Bool, mismatches: [Requirement]) -> IconsShimState {
        if poisoned { return .poisoned }
        return present && mismatches.isEmpty ? .available : .unavailable
    }

    /// The H8 line.
    package static func launchLine(_ state: IconsShimState) -> String { "selftest-launch: icons shim " + state.rawValue }

    /// `SNAPTIC_SELFTEST_EXPECT_ICONS_SHIM`: CI (macOS 15) sets `unavailable`; a 27.2 run may set `available`.
    package static let expectVariable = "SNAPTIC_SELFTEST_EXPECT_ICONS_SHIM"

    /// H8's verdict. It fails on poisoned, on an encoding mismatch while the classes are present, on an expectation
    /// it can't read, and on a state other than the expected one.
    package static func selfTestProblems(state: IconsShimState, present: Bool, mismatches: [Requirement],
                                         expect: String?) -> [String] {
        var problems: [String] = []
        if state == .poisoned { problems.append("the icons shim is poisoned") }
        if present && !mismatches.isEmpty {
            problems.append("icons shim encodings changed: " + mismatches.map(\.name).joined(separator: ", "))
        }
        if let expect {
            if let wanted = IconsShimState(rawValue: expect), wanted != .poisoned {
                if wanted != state { problems.append("expected the icons shim \(wanted.rawValue), found \(state.rawValue)") }
            } else {
                problems.append("\(expectVariable) must be available or unavailable")
            }
        }
        return problems
    }

    /// The forced-exception check (debug builds): afterwards the shim must be poisoned and unavailable.
    package static func poisonProblems(poisoned: Bool, available: Bool) -> [String] {
        var problems: [String] = []
        if !poisoned { problems.append("a forced exception didn't poison the icons shim") }
        if available { problems.append("the poisoned icons shim still reports available") }
        return problems
    }

    /// Diagnostics rows (H12): the shim state and one y/n per encoding. No bundle ids.
    package static func diagnosticsRows(state: IconsShimState, mismatches: [Requirement]) -> [(String, String)] {
        [("Icons shim", state.rawValue)] + requirements.map { r in
            (r.name, mismatches.contains(r) ? "n" : "y")
        }
    }
}
