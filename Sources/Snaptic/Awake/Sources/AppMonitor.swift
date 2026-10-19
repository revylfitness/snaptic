import AppKit
import Combine
import SnapticKit

// Running and frontmost apps (owner: J; PLAN 0.3 §2.8): events only. NSWorkspace's runningApplications KVO covers
// regular and accessory apps (the launch notification skips LSUIElement apps); the activation notification gives the
// frontmost app. Bundle ids only; the picker list is sorted by name with Snaptic excluded. No TCC.

@MainActor final class AppMonitor: CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [.app] }

    /// One row of the app picker.
    struct AppChoice: Equatable {
        let bundleID: String
        let name: String
    }

    weak var context: AwakeContext?
    private let changes = ChangeFanout()
    private var active = false
    private var sinks: [AnyCancellable] = []
    private var observers: [NSObjectProtocol] = []

    /// Bundle ids of running regular and accessory apps; nil while inactive.
    private(set) var running: Set<String>?
    /// Outer nil = unknown (inactive); inner nil = no frontmost app.
    private(set) var frontmost: String??

    init() {}

    /// Running apps the user can pick (regular and accessory, Snaptic excluded), sorted by name.
    func choices() -> [AppChoice] {
        let own = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var out: [AppChoice] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            guard let id = app.bundleIdentifier, id != own, seen.insert(id).inserted else { continue }
            out.append(AppChoice(bundleID: id, name: app.localizedName ?? id))
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// true/false while active; nil while inactive (unknown).
    func isRunning(_ bundleID: String) -> Bool? { running.map { $0.contains(bundleID) } }

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        let workspace = NSWorkspace.shared
        workspace.publisher(for: \.runningApplications)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.read() } }
            .store(in: &sinks)
        observers.append(workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        })
        read()
    }

    func deactivate() {
        guard active else { return }
        active = false
        sinks.removeAll()
        for token in observers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        observers = []
        running = nil
        frontmost = nil
        context = nil
    }

    // MARK: CriterionSource

    func contribute(to facts: inout CriterionFacts) {
        guard active else { return }
        facts.runningApps = running
        facts.frontmostApp = frontmost
    }

    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }

    // MARK: Reading

    private func read() {
        guard active else { return }
        let workspace = NSWorkspace.shared
        var ids = Set<String>()
        for app in workspace.runningApplications where app.activationPolicy != .prohibited && !app.isTerminated {
            if let id = app.bundleIdentifier { ids.insert(id) }
        }
        let front: String?? = .some(workspace.frontmostApplication?.bundleIdentifier)
        guard ids != running || front != frontmost else { return }
        running = ids
        frontmost = front
        changes.fire()
    }
}
