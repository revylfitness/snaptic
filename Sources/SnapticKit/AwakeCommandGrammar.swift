import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.10 (kind S): safe returns.

package enum PresetSelector: Equatable, Sendable {
    /// 1-based.
    case index(Int)
    /// ≤ 64 scalars.
    case name(String)
}

package enum AwakeCommand: Equatable, Sendable {
    case status(json: Bool)
    /// nil = 1 h (C10).
    case start(AwakeDurationRequest?, displayMaySleep: Bool)
    /// --pid N (> 1), --max <duration> (≤ 24 h).
    case hold(pid: Int32?, maxSeconds: Int?)
    case preset(PresetSelector)
    case extend(seconds: Int)
    case stop
    /// ≤ 24 h, nil = 1 h.
    case pause(seconds: Int?)
}

package enum AwakeStatusSource: String, Sendable { case manual, automatic, holds }

package struct AwakeStatusFacts: Equatable, Sendable {
    package var active: Bool
    package var source: AwakeStatusSource?
    package var kind: AwakeHistoryKind?
    package var display: AwakeDisplayPolicy?
    package var endUnix: Double?
    package var remaining: Double?
    package var triggerNumber: Int?
    package var holdPIDs: [Int32]

    package init(active: Bool, source: AwakeStatusSource?, kind: AwakeHistoryKind?, display: AwakeDisplayPolicy?,
                 endUnix: Double?, remaining: Double?, triggerNumber: Int?, holdPIDs: [Int32]) {
        self.active = active
        self.source = source
        self.kind = kind
        self.display = display
        self.endUnix = endUnix
        self.remaining = remaining
        self.triggerNumber = triggerNumber
        self.holdPIDs = holdPIDs
    }
}

package enum AwakeCommandGrammar {
    /// nil = usage error (exit 2). Never traps. Stub: nil.
    package static func parse(verb: String, args: [String]) -> AwakeCommand? { nil }
    /// `awake status` line. Stub: "inactive".
    package static func statusLine(_ s: AwakeStatusFacts) -> String { "inactive" }
    /// Stub: an inactive object.
    package static func statusJSON(_ s: AwakeStatusFacts) -> String { #"{"active":false}"# }
    /// First reply line of a hold. Stub: "".
    package static func holdReply(pid: Int32?, capSeconds: Int) -> String { "" }
}
