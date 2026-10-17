import Combine
import Foundation
import SnapticKit

/// One persisted settings model under one UserDefaults key. Owned by the host for the
/// app's lifetime (one store per key); modules receive it, never create it (R5.1).
/// Reads only the persistent domain, never launch arguments (PLAN §3.4).
/// Changes made outside Snaptic (`defaults write`, another process) are picked up through
/// a DefaultsKeyObserver; our own writes are recognised and ignored (loop guard).
@MainActor final class ConfigStore<T: ConfigModel>: ObservableObject {
    @Published var value: T {
        didSet { if value != oldValue && !applyingExternal { scheduleSave() } }
    }

    let key: String
    /// Bumped each time the stored value changed outside Snaptic.
    @Published private(set) var externalChanges = 0
    /// Old and new value of an outside change (for "changed outside Snaptic" notices).
    var onExternalChange: (@MainActor (_ old: T, _ new: T) -> Void)?

    private var pendingSave: DispatchWorkItem?
    private var lastWritten: Data?
    private var applyingExternal = false
    private var observer: DefaultsKeyObserver?

    init(key: String) {
        precondition(!key.contains("."), "KVO treats '.' as a key path separator")
        self.key = key
        if let data = Self.persistentData(forKey: key) {
            if let decoded = try? JSONDecoder().decode(T.self, from: data) {
                value = decoded.sanitized()
                lastWritten = data
            } else {
                // Unreadable (e.g. written by a newer version): keep a copy before the
                // first save replaces it, and say so in the log.
                UserDefaults.standard.set(data, forKey: key + "Unreadable")
                EventLog.shared.record(.modules, "Settings \(key) could not be read; saved a copy and started from defaults")
                value = T()
            }
        } else {
            value = T()
        }
        observer = DefaultsKeyObserver(key: key) { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.storedValueChanged() } }
        }
    }

    /// Re-reads after an outside change. Our own writes match `lastWritten` and are ignored.
    private func storedValueChanged() {
        guard let data = Self.persistentData(forKey: key), data != lastWritten,
              data.count <= 4 * 1024 * 1024,
              let decoded = try? JSONDecoder().decode(T.self, from: data) else { return }
        lastWritten = data
        let new = decoded.sanitized()
        guard new != value else { return }
        let old = value
        applyingExternal = true
        value = new
        applyingExternal = false
        externalChanges &+= 1
        EventLog.shared.record(.modules, "Settings \(key) changed outside Snaptic")
        onExternalChange?(old, new)
    }

    /// Writes any pending change now (quit, stop).
    func flush() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        save()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingSave = nil
                self?.save()
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(value), data != lastWritten else { return }
        lastWritten = data
        UserDefaults.standard.set(data, forKey: key)
    }

    /// UserDefaults.standard writes to the bundle's domain; unbundled debug runs use the
    /// process name, which is what `standard` uses then too.
    static var persistentDomainName: String { Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName }

    static func persistentData(forKey key: String) -> Data? {
        guard let values = UserDefaults.standard.persistentDomain(forName: persistentDomainName) else { return nil }
        return values[key] as? Data
    }
}
