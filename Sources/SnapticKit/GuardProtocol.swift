import Foundation

// Parent ↔ guard messages, JSON lines (owner: B). R2C §4.4 + PLAN §4.5 + R5.2.

package enum GuardMessage: Codable, Equatable, Sendable {
    case hello(protocolVersion: Int, build: String)
    case armTrial(id: UInt64, undo: [UndoOp], deadlineSeconds: Double)
    case extend(id: UInt64, seconds: Double)
    case commitIntent(id: UInt64)
    case commit(id: UInt64)
    case disarm(id: UInt64)
    case long(undo: [UndoOp], restoreColorSync: Bool)
    case busy(seconds: Double)
    case classification([GuardDisplayClass])
    case heartbeat(mainAgeMillis: UInt64)
    case shutdown
}

package enum GuardReply: Codable, Equatable, Sendable {
    case ready(protocolVersion: Int, canMonitorPanel: Bool)
    case ack(id: UInt64)
    case reverted(trial: UInt64?, applied: Int, skipped: Int)
    case failed(String)
}

package enum GuardProtocol {
    package static let version = 1
}
