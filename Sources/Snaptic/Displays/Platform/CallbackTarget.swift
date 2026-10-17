import Foundation

/// A retained box with a weak target, passed as a C callback refcon. Queued hops
/// keep the box alive, never the target (R2C §8 c4).
final class CallbackTarget<T: AnyObject>: @unchecked Sendable {
    /// Read only on the main thread.
    weak var target: T?
    init(_ target: T) { self.target = target }
}
