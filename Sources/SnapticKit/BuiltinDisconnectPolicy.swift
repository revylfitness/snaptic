import Foundation

// Built-in display disconnect hazards and auto-disconnect rules (owner: D). R5.7, R5.8.

/// The last DDC power reading of an external display (VCP 0xD6).
package enum ExternalPowerReading: String, Codable, Sendable {
    /// Read recently and reported "on" (0xD6 = 1).
    case on
    /// Read recently and reported standby/off.
    case off
    /// The display answers DDC but the read failed or is stale.
    case unknown
    /// The display has no DDC path (or DDC isn't effective).
    case notReadable
}

package enum BuiltinDisconnectVerdict: Equatable, Sendable {
    case allowed
    case refused(String)

    package var isAllowed: Bool { self == .allowed }
}

package enum BuiltinDisconnectPolicy {
    /// Base-M3 models where reconnecting the built-in panel may need a restart [U list].
    package static let hazardModels: Set<String> = ["Mac15,3", "Mac15,4", "Mac15,5", "Mac15,12", "Mac15,13"]
    /// Apple silicon iMac identifiers that don't start with "iMac" [U list].
    package static let appleSiliconIMacs: Set<String> = ["Mac15,4", "Mac15,5", "Mac16,2", "Mac16,3"]

    package static let hazardReason = L("Reconnecting may need a restart on this Mac")

    package static func isIMac(modelIdentifier: String, modelName: String? = nil) -> Bool {
        if modelIdentifier.hasPrefix("iMac") || appleSiliconIMacs.contains(modelIdentifier) { return true }
        return modelName?.range(of: "iMac", options: .caseInsensitive) != nil
    }

    /// Whether disconnecting the **built-in** panel is offered at all (R5.8 hazard table).
    package static func builtinAvailability(modelIdentifier: String, modelName: String? = nil) -> BuiltinDisconnectVerdict {
        if isIMac(modelIdentifier: modelIdentifier, modelName: modelName) || hazardModels.contains(modelIdentifier) {
            return .refused(hazardReason)
        }
        return .allowed
    }

    /// Whether auto-disconnect of the built-in display is available on this Mac (static facts).
    package static func autoDisconnectAvailability(modelIdentifier: String, modelName: String? = nil,
                                                   isAppleSilicon: Bool) -> BuiltinDisconnectVerdict {
        guard isAppleSilicon else { return .refused(L("Needs a Mac with Apple silicon")) }
        return builtinAvailability(modelIdentifier: modelIdentifier, modelName: modelName)
    }

    /// The runtime check for one auto-disconnect (PLAN §9.6, R5.7). `lidOpen` nil = unknown.
    package static func autoDisconnectDecision(modelIdentifier: String, modelName: String? = nil, isAppleSilicon: Bool,
                                               lidOpen: Bool?, externalStronglyVisible: Bool,
                                               externalPower: ExternalPowerReading, externalIsAppleNative: Bool,
                                               userSaysNoDDC: Bool, builtinIgnored: Bool) -> BuiltinDisconnectVerdict {
        let base = autoDisconnectAvailability(modelIdentifier: modelIdentifier, modelName: modelName, isAppleSilicon: isAppleSilicon)
        guard base.isAllowed else { return base }
        if builtinIgnored { return .refused(L("This display is excluded from auto-disconnect")) }
        guard lidOpen == true else { return .refused(L("The lid state is unknown or closed")) }
        guard externalStronglyVisible else { return .refused(L("No external display is visible")) }
        if externalIsAppleNative { return .allowed }
        switch externalPower {
        case .on: return .allowed
        case .off: return .refused(L("The external display reports standby"))
        case .unknown:
            return .refused(L("The external display's power state couldn't be read; try again in a moment"))
        case .notReadable:
            return userSaysNoDDC ? .allowed
                : .refused(L("The external display's power state can't be read over DDC"))
        }
    }
}
