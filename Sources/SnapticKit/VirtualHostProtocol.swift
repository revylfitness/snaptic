import Foundation

// Parent ↔ virtual host messages, JSON lines (owner: D). PLAN §9.3, R5.6.

package enum VirtualHostMessage: Codable, Equatable, Sendable {
    case hello(protocolVersion: Int, build: String)
    case create(requestID: UInt64, spec: VirtualScreenSpec, initialMode: VirtualMode, serial: UInt32)
    case setModes(requestID: UInt64, modes: [VirtualMode])
    case shutdown
}

package enum VirtualHostReply: Codable, Equatable, Sendable {
    case ready(protocolVersion: Int)
    case created(requestID: UInt64, displayID: UInt32)
    case modesSet(requestID: UInt64)
    case failed(requestID: UInt64?, reason: String)
}

package enum VirtualHostProtocol {
    package static let version = 1
}
