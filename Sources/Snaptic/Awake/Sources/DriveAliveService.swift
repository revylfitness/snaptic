import AppKit
import SnapticKit

// Stub (owner: J). Hand-written by the lead in step 0 from PLAN 0.3 §2.9 (kind S): writes nothing.

@MainActor final class DriveAliveService: ObservableObject, AwakeServiceLifecycle {
    struct VolumeState: Equatable {
        let uuid: VolumeUUIDKey
        let name: String
        var lastWrite: Date?
        var lastError: DriveAliveError?
    }

    @Published private(set) var volumes: [VolumeState] = []
    weak var context: AwakeContext?

    init() {}

    /// Writes start/stop per volume. Stub: none.
    func setTargets(_ uuids: Set<VolumeUUIDKey>, interval: TimeInterval) {}

    /// When the user turns a volume off. Stub: nothing was written.
    func removeKeepAliveFile(_ uuid: VolumeUUIDKey) {}

    func activate(_ context: AwakeContext, lifetime: Lifetime) { self.context = context }

    func deactivate() {
        volumes = []
        context = nil
    }
}
