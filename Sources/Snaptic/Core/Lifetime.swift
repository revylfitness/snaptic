import Foundation

/// Bounds async work and registrations to one start…stop of a module, service or
/// controller (R2C §2.3). A new Lifetime per start; never revived.
@MainActor final class Lifetime {
    private(set) var isEnded = false
    private var tasks: [UInt64: Task<Void, Never>] = [:]
    private var children: [Lifetime] = []
    private var next: UInt64 = 0
    private var endHandlers: [(id: UInt64, run: @MainActor () -> Void)] = []
    private var nextHandler: UInt64 = 0

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
        _ = addEndHandler(handler)
    }

    /// `onEnd` that can be taken back: long-lived lifetimes (the host's) would otherwise
    /// collect a handler per short-lived registration (a toast). Nil when it already ran.
    func addEndHandler(_ handler: @escaping @MainActor () -> Void) -> UInt64? {
        if isEnded {
            handler()
            return nil
        }
        nextHandler &+= 1
        endHandlers.append((nextHandler, handler))
        return nextHandler
    }

    /// Drops a handler from `addEndHandler` that hasn't run. Idempotent.
    func removeEndHandler(_ id: UInt64?) {
        guard let id else { return }
        endHandlers.removeAll { $0.id == id }
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
        handlers.reversed().forEach { $0.run() }
    }
}
