import Foundation

// Parent ↔ virtual host messages, JSON lines (owner: D). PLAN §9.3, R5.6.
// One host process per virtual screen: it creates exactly one CGVirtualDisplay and
// keeps it alive until `shutdown` or EOF on stdin (parent death).

/// Backing reserved by the descriptor (`maxPixelsWide/High`).
package struct VirtualBacking: Codable, Equatable, Sendable {
    package var pixelsWide: Int
    package var pixelsHigh: Int
    package init(pixelsWide: Int, pixelsHigh: Int) {
        self.pixelsWide = pixelsWide
        self.pixelsHigh = pixelsHigh
    }
}

package enum VirtualHostMessage: Codable, Equatable, Sendable {
    case hello(protocolVersion: Int, build: String)
    /// `serial`: unsalted (spec id or the physical display's fingerprint, §4.10(7)).
    case create(requestID: UInt64, spec: VirtualScreenSpec, initialMode: VirtualMode, serial: UInt32, backing: VirtualBacking)
    /// Applies additional modes to the live display (Beta); the parent then selects one.
    case setModes(requestID: UInt64, modes: [VirtualMode])
    case shutdown
}

package enum VirtualHostReply: Codable, Equatable, Sendable {
    case ready(protocolVersion: Int)
    case created(requestID: UInt64, displayID: UInt32)
    case modesSet(requestID: UInt64)
    case failed(requestID: UInt64?, reason: VirtualHostFailure)
}

/// Why a host refused or failed a request. Closed set: hosts never send free text.
package enum VirtualHostFailure: String, Codable, CaseIterable, Sendable {
    case unavailable          // CGVirtualDisplay classes or selectors missing / wrong encoding
    case invalidRequest       // failed validation
    case alreadyCreated       // one display per host
    case notCreated           // setModes before create
    case refused              // WindowServer returned nil / applySettings failed
    case protocolMismatch

    package var message: String {
        switch self {
        case .unavailable: return L("Virtual displays aren't available on this Mac")
        case .invalidRequest: return L("The virtual display settings are out of range")
        case .alreadyCreated: return L("The virtual display already exists")
        case .notCreated: return L("The virtual display isn’t running")
        case .refused: return L("macOS refused to create the virtual display")
        case .protocolMismatch: return L("Restart Snaptic to finish updating")
        }
    }
}

/// Why a host process couldn't be started (FIXES-R2 N11): each cause has its own text, so
/// "helpers are still starting" never reads as "restart to update".
package enum VirtualHostSpawnFailure: Equatable, Sendable {
    /// Snaptic's helper identity isn't ready yet (transient, right after launch).
    case helpersStarting
    /// Helpers can't run in this launch; the spawner's own reason (already user text).
    case helpersUnavailable(String)
    /// The app on disk no longer matches the running one: a restart finishes the update.
    case appChanged
    /// The helper failed a post-spawn check (not stopped, wrong responsible process).
    case checkFailed
    /// The process or its pipes could not be created.
    case launchFailed

    package var message: String {
        switch self {
        case .helpersStarting: return L("Snaptic is still starting. Try again in a moment.")
        case .helpersUnavailable(let reason):
            let clean = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? L("The virtual display helper can’t run right now.") : clean
        case .appChanged: return L("Restart Snaptic to finish updating")
        case .checkFailed: return L("The virtual display helper failed a safety check and was stopped. Try again.")
        case .launchFailed: return L("The virtual display helper couldn’t start. Try again.")
        }
    }

    /// Whether trying again later in this launch can work.
    package var isTransient: Bool {
        switch self {
        case .helpersStarting, .checkFailed, .launchFailed: return true
        case .helpersUnavailable, .appChanged: return false
        }
    }
}

package enum VirtualHostProtocol {
    package static let version = 1
    /// Seconds the parent waits for `ready` and for each reply.
    package static let replyTimeout: Double = 5
    /// shutdown → this many seconds → SIGKILL (R5.6).
    package static let shutdownGrace: Double = 1

    package static func encode(_ message: VirtualHostMessage) -> Data? { try? JSONEncoder().encode(message) }
    package static func encode(_ reply: VirtualHostReply) -> Data? { try? JSONEncoder().encode(reply) }
    package static func decodeMessage(_ line: Data) -> VirtualHostMessage? { try? JSONDecoder().decode(VirtualHostMessage.self, from: line) }
    package static func decodeReply(_ line: Data) -> VirtualHostReply? { try? JSONDecoder().decode(VirtualHostReply.self, from: line) }

    /// Host-side validation of a create request. Returns nil when it is acceptable.
    /// The host re-checks what the parent already checked: it trusts nothing on stdin.
    package static func validate(spec: VirtualScreenSpec, initialMode: VirtualMode, backing: VirtualBacking,
                                 maxDimension: Int) -> VirtualHostFailure? {
        let limit = max(0, maxDimension)
        guard initialMode.width >= VirtualScreenSpec.minModeDimension, initialMode.height >= VirtualScreenSpec.minModeDimension,
              initialMode.refreshMilliHz >= VirtualScreenSpec.minRefreshMilliHz,
              initialMode.refreshMilliHz <= VirtualScreenSpec.maxRefreshMilliHz,
              initialMode.pixelWidth <= backing.pixelsWide, initialMode.pixelHeight <= backing.pixelsHigh,
              backing.pixelsWide > 0, backing.pixelsHigh > 0, backing.pixelsWide <= limit, backing.pixelsHigh <= limit,
              spec.sizeInches >= VirtualScreenSpec.minSizeInches, spec.sizeInches <= VirtualScreenSpec.maxSizeInches,
              spec.name.unicodeScalars.count <= VirtualScreenSpec.maxNameScalars
        else { return .invalidRequest }
        if initialMode.hiDPI && !spec.hiDPI { return .invalidRequest }
        return nil
    }

    /// Validation of a setModes request: every mode must fit the existing backing.
    package static func validate(modes: [VirtualMode], backing: VirtualBacking) -> VirtualHostFailure? {
        guard !modes.isEmpty, modes.count <= VirtualScreenSpec.maxModesLoDPI else { return .invalidRequest }
        for m in modes {
            guard m.width >= VirtualScreenSpec.minModeDimension, m.height >= VirtualScreenSpec.minModeDimension,
                  m.pixelWidth <= backing.pixelsWide, m.pixelHeight <= backing.pixelsHigh,
                  m.refreshMilliHz >= VirtualScreenSpec.minRefreshMilliHz, m.refreshMilliHz <= VirtualScreenSpec.maxRefreshMilliHz
            else { return .invalidRequest }
        }
        return nil
    }

    /// Parent-side HiDPI check after creation (R5.6): a HiDPI mode must be backed 2×.
    package static func hiDPIVerified(requested: VirtualMode, pixelWidth: Int, pointWidth: Int) -> Bool {
        guard requested.hiDPI else { return true }
        return pointWidth > 0 && pixelWidth == pointWidth * 2
    }
}
