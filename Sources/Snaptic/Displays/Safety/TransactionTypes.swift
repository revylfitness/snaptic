import Foundation
import SnapticKit

// Transaction app types (owner: B, R5.1). A layout change is data (R2C §5.4); the queue
// computes undo, risk and invariants from it.

enum TransactionRisk: Int, Comparable, Sendable {
    case low, restore, trial
    static func < (a: TransactionRisk, b: TransactionRisk) -> Bool { a.rawValue < b.rawValue }

    init(_ level: RiskLevel) {
        switch level {
        case .low: self = .low
        case .restore: self = .restore
        case .trial: self = .trial
        }
    }

    var level: RiskLevel {
        switch self {
        case .low: return .low
        case .restore: return .restore
        case .trial: return .trial
        }
    }
}

enum TransactionOutcome: Equatable {
    case applied
    case kept
    case reverted(String)
    case refused([InvariantViolation])
    case busy
    case failed(String)
}

/// A layout change as data (R2C §5.4). Main actor only (holds closures).
struct TransactionRequest {
    let label: String
    let risk: TransactionRisk
    let changes: [DisplayChange]
    let finalScope: FinalScope
    let automatic: Bool
    /// Runs inside the queue before the snapshot (e.g. create a virtual display).
    var prepare: (@MainActor () async throws -> Void)?
    var afterRevert: (@MainActor () async -> Void)?
    var afterKeep: (@MainActor () async -> Void)?
    /// Automatic requests from one ConnectPlanner plan share an id: the rate limiter counts
    /// plans, not requests (invariant 6). Nil = each request is its own plan.
    var planID: UInt64?
    /// Shows the confirm panel as key (UI-triggered changes only, PLAN §4.4). Defaults to !automatic.
    var interactive: Bool
    /// FIXES-R3 1: a command-line request with `--yes` that the user allowed ("Let commands
    /// skip the confirmation panel"; the server filters it). A trial keeps right after settle
    /// instead of showing the panel; it is journaled and guard-armed exactly as any trial.
    /// Ignored for automatic requests (`TrialPanelChoice.withoutPanel`).
    var skipConfirmation: Bool

    init(label: String, risk: TransactionRisk, changes: [DisplayChange], finalScope: FinalScope = .permanently,
         automatic: Bool = false, prepare: (@MainActor () async throws -> Void)? = nil,
         afterRevert: (@MainActor () async -> Void)? = nil, afterKeep: (@MainActor () async -> Void)? = nil,
         planID: UInt64? = nil, interactive: Bool? = nil, skipConfirmation: Bool = false) {
        self.label = label
        self.risk = risk
        self.changes = changes
        self.finalScope = finalScope
        self.automatic = automatic
        self.prepare = prepare
        self.afterRevert = afterRevert
        self.afterKeep = afterKeep
        self.planID = planID
        self.interactive = interactive ?? !automatic
        self.skipConfirmation = skipConfirmation
    }
}

/// What observers of the queue hear after each transaction (D's protection and persisted
/// choice learn from these; diagnostics show the last few).
struct TransactionReport {
    let label: String
    let changes: [DisplayChange]
    let before: LayoutSnapshot
    let risk: TransactionRisk
    let automatic: Bool
    let outcome: TransactionOutcome
    /// Uptime seconds.
    let at: Double
}

/// How a pending trial ended.
enum TrialResolution: Equatable {
    case keep
    case revert(String)
}
