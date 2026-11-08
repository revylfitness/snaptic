import AppKit
import SnapticKit
import SnapticShims

/// The Native engine's restriction (lead; PLAN 0.4 §4.2.2, A2): Kit's `IconsVisibilityPort` over `SNMenuBarVisibility`.
/// The core owns tokens, timeouts and the order of activate/invalidate; this only translates. A refused call
/// (`activate` returns NO) still answers the core, once, on the next main-queue turn, with the shim's reason; the
/// shim's duplicate-handler count is drained into `icons.dupCompletion` after every completion.
@MainActor final class NativeBackend: @preconcurrency IconsVisibilityPort {
    /// `icons.dupCompletion` and the like, for the host (A5 wires it to `IconsEngineHost.count`).
    var onCount: ((IconsCounter) -> Void)?
    /// After each successful activation: the watchdog's DEBUG hang hook (M12).
    var onActivated: (() -> Void)?

    init() {}

    /// `PrivateMenuBarAPI.verify()` ran and every encoding matched, and nothing poisoned the shim since.
    var isAvailable: Bool { PrivateMenuBarAPI.state == .available }

    func activate(systemItems: Range<Int>, bundles: [String], token: UInt64,
                  completion: @escaping (Result<Void, IconsActivationError>) -> Void) {
        let accepted = SNMenuBarVisibility.activate(
            systemItemsFrom: systemItems.lowerBound, to: systemItems.upperBound, bundles: bundles, token: token
        ) { [weak self] raw in
            // The shim delivers this at most once, on main, and only while the token is held.
            MainActor.assumeIsolated {
                self?.drainDuplicates()
                let result = IconsShimResult.completion(raw.rawValue)
                if case .success = result { self?.onActivated?() }
                completion(result)
            }
        }
        guard !accepted else { return }
        let reason = IconsShimResult.refusal(SNMenuBarVisibility.lastRefusal().rawValue)
        // Never re-entrant: the core finishes its own bookkeeping for this token first.
        DispatchQueue.main.async { completion(.failure(reason)) }
    }

    func invalidate(token: UInt64) {
        SNMenuBarVisibility.invalidate(token: token)
    }

    func invalidateAll() {
        SNMenuBarVisibility.invalidateAll()
    }

    /// Tokens the shim holds right now (diagnostics, the watchdog).
    nonisolated static var heldCount: Int { Int(SNMenuBarVisibility.heldCount()) }

    private func drainDuplicates() {
        let n = SNMenuBarVisibility.takeDuplicateCompletions()
        for _ in 0..<n { onCount?(.dupCompletion) }
    }
}

/// The identity check (§4.2.1, Y-5): Native acts only from the copy macOS resolves for Snaptic's bundle id, never
/// translocated. Asked at start and before every activation (the policy's gate, A5).
enum IconsIdentity {
    @MainActor static func passes(bundle: Bundle = .main, workspace: NSWorkspace = .shared) -> Bool {
        let own = bundle.bundleURL.resolvingSymlinksInPath().path
        let resolved = bundle.bundleIdentifier
            .flatMap { workspace.urlForApplication(withBundleIdentifier: $0) }?
            .resolvingSymlinksInPath().path
        return IconsIdentityCheck.passes(translocated: PermissionFlow.isTranslocated, resolvedPath: resolved,
                                         ownPath: own)
    }
}
