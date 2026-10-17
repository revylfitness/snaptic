import Foundation

/// Actions that must run even if the main thread is hung (signal path). Each must be
/// thread-safe, fast and idempotent (R2C §2.3).
final class EmergencyActions: @unchecked Sendable {
    static let shared = EmergencyActions()

    struct Token: Hashable, Sendable { fileprivate let id: UInt64 }

    private let lock = NSLock()
    private var actions: [(id: UInt64, name: String, run: @Sendable () -> Void)] = []
    private var next: UInt64 = 0

    private init() {}

    @discardableResult
    func add(_ name: String, _ run: @escaping @Sendable () -> Void) -> Token {
        lock.lock(); defer { lock.unlock() }
        next &+= 1
        actions.append((next, name, run))
        return Token(id: next)
    }

    func remove(_ token: Token) {
        lock.lock(); defer { lock.unlock() }
        actions.removeAll { $0.id == token.id }
    }

    func runAll() {
        lock.lock()
        let copy = actions
        lock.unlock()
        for action in copy.reversed() { action.run() }
    }
}
