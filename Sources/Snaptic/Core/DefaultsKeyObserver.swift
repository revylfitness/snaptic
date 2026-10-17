import Foundation

/// Calls back when one UserDefaults key changes, in this process or another (R2C §2.7).
/// String KVO treats "." as a key-path separator, so keys must not contain dots.
final class DefaultsKeyObserver: NSObject, @unchecked Sendable {
    private let key: String
    private let onChange: @Sendable () -> Void
    private let lock = NSLock()
    private var observing = false

    /// Returns nil for a key containing a dot (it would never fire).
    init?(key: String, onChange: @escaping @Sendable () -> Void) {
        guard !key.isEmpty, !key.contains(".") else { return nil }
        self.key = key
        self.onChange = onChange
        super.init()
        UserDefaults.standard.addObserver(self, forKeyPath: key, options: [], context: nil)
        observing = true
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        onChange()   // any thread; the closure hops to main
    }

    /// Idempotent.
    func invalidate() {
        lock.lock()
        let wasObserving = observing
        observing = false
        lock.unlock()
        if wasObserving { UserDefaults.standard.removeObserver(self, forKeyPath: key) }
    }

    deinit { invalidate() }
}
