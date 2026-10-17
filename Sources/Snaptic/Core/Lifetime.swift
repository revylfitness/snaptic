import Foundation

/// Bounds async work and registrations to one start…stop of a module, service or
/// controller (R2C §2.3). A new Lifetime per start; never revived.
@MainActor final class Lifetime {
    private(set) var isEnded = false
    private var tasks: [UInt64: Task<Void, Never>] = [:]
    private var children: [Lifetime] = []
    private var next: UInt64 = 0
    private var endHandlers: [@MainActor () -> Void] = []

    init() {}

    /// Starts work bound to this lifetime; the task removes itself when done.
    @discardableResult
    func spawn(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never>? {
        guard !isEnded else { return nil }
        next &+= 1
        let id = next
        let task = Task { @MainActor [weak self] in
            await operation()
            self?.tasks[id] = nil
        }
        tasks[id] = task
        return task
    }

    func child() -> Lifetime {
        let c = Lifetime()
        if isEnded {
            c.end()
        } else {
            children.removeAll { $0.isEnded }
            children.append(c)
        }
        return c
    }

    /// Runs `handler` when the lifetime ends (immediately if it already has).
    func onEnd(_ handler: @escaping @MainActor () -> Void) {
        if isEnded { handler() } else { endHandlers.append(handler) }
    }

    func end() {
        guard !isEnded else { return }
        isEnded = true
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        children.forEach { $0.end() }
        children = []
        let handlers = endHandlers
        endHandlers = []
        handlers.reversed().forEach { $0() }
    }
}
