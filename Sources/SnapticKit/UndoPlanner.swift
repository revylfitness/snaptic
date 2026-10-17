import Foundation

// Compare-and-swap undo operations (owner: B). See R2C §5.1 and PLAN R5.2.

package enum DisplayProperty: String, Codable, Sendable { case enabled, mirrorOf, mode, origin, main, rotation, underscan, hdr }

package enum PropertyValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case display(UInt32?)
    case mode(ModeRef)
    case point(x: Int32, y: Int32)
    case degrees(Int)
    case fraction(Double)
}

package struct UndoOp: Codable, Equatable, Sendable {
    package var displayID: UInt32
    /// Re-resolves the id if the display was replugged.
    package var fingerprint: String
    package var property: DisplayProperty
    /// The value to put back.
    package var restore: PropertyValue
    /// The value the transaction applied; revert only if the live value still equals it.
    package var expected: PropertyValue

    package init(displayID: UInt32, fingerprint: String, property: DisplayProperty, restore: PropertyValue, expected: PropertyValue) {
        self.displayID = displayID
        self.fingerprint = fingerprint
        self.property = property
        self.restore = restore
        self.expected = expected
    }

    /// Directions allowed when replaying a journal at launch (§4.6).
    package var isSafeDirection: Bool {
        switch (property, restore) {
        case (.enabled, .bool(true)), (.mirrorOf, .display(nil)): return true
        default: return false
        }
    }
}

package enum UndoPlanner {
    /// Undo ops for a request, computed from the request and the before-snapshot.
    package static func undo(for changes: [DisplayChange], before: LayoutSnapshot) -> [UndoOp] { [] }

    /// Ops whose live value still equals what the transaction applied (compare-and-swap).
    package static func pending(_ ops: [UndoOp], live: LayoutSnapshot) -> [UndoOp] { [] }

    /// The single undo order (R5.2): enable → un-mirror → MonitorPanel (rotation before HDR)
    /// → modes/origins/main.
    package static func order(_ ops: [UndoOp]) -> [UndoOp] { ops }
}
