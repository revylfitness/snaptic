import Foundation

// Dock Previews' live counters (lead; PLAN 0.5 §4.22, P3-2). A6a adds them and the selftest line; A3 (observer), A4a
// (panel, timers) and A5 (clickTap, keys) count up when they create one and down when they tear it down. The app
// holds the one instance (`DockPreviewsModule.live`), beside `WindowServices.liveLeases`.

/// One kind of thing the module creates only while it runs (ground rule 1).
package enum DockLiveCounter: String, CaseIterable, Sendable {
    /// The Dock's AX observer (A3).
    case observer
    /// The listen-only mouse tap for Dock click actions (A5).
    case clickTap
    /// The keys tap, from the first show with keys on until the module stops (A5).
    case keys
    /// The preview panel (A4a).
    case panel
    /// Hover, dismissal and linger timers (A4a).
    case timers
}

/// The live counts. Every increment is matched by a decrement, so with the module off (and in the selftest, where
/// no module starts) each count is 0.
package struct DockLive: Equatable, Sendable {
    package private(set) var counts: [DockLiveCounter: Int] = [:]
    /// Decrements that found their count at 0: a teardown without a matching setup. They never go below 0.
    package private(set) var underflows = 0

    package init() {}

    package subscript(_ counter: DockLiveCounter) -> Int { counts[counter] ?? 0 }

    package mutating func increment(_ counter: DockLiveCounter) {
        counts[counter] = self[counter] + 1
    }

    package mutating func decrement(_ counter: DockLiveCounter) {
        let now = self[counter]
        if now == 0 {
            underflows += 1
        } else {
            // A count back at 0 leaves no key, so a balanced value equals `DockLive()`.
            counts[counter] = now == 1 ? nil : now - 1
        }
    }

    /// Every count is 0 and nothing was torn down twice.
    package var isBalanced: Bool { underflows == 0 && DockLiveCounter.allCases.allSatisfy { self[$0] == 0 } }

    /// `selftest-launch: dock live observer=0 clickTap=0 keys=0 panel=0 timers=0 leases=0` (§4.22), `leases` being
    /// `WindowServices.liveLeases`.
    package func launchLine(leases: Int) -> String {
        let values = DockLiveCounter.allCases.map { "\($0.rawValue)=\(self[$0])" } + ["leases=\(leases)"]
        return "selftest-launch: dock live " + values.joined(separator: " ")
    }

    /// The selftest's verdict: no module starts there, so each count and the leases must be 0.
    package func launchProblems(leases: Int) -> [String] {
        var problems = DockLiveCounter.allCases.filter { self[$0] != 0 }.map {
            "Dock Previews held \(self[$0]) \($0.rawValue) before start()"
        }
        if underflows != 0 { problems.append("Dock Previews tore down \(underflows) things it never created") }
        if leases != 0 { problems.append("a module held \(leases) WindowServices leases before start()") }
        return problems
    }
}
