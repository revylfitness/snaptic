import Foundation
import SnapticKit

/// Host facts modules read (lead; PLAN 0.3 §2.11). One instance, owned by ModuleHost.
@MainActor final class HostSignals: ObservableObject {
    /// The window switcher panel is on screen (A sets it; Awake suppresses pointer nudges meanwhile).
    @Published var switcherVisible = false
    /// ModuleHost.shutdown() sets it before any module stops (code M9): Awake keeps its snapshot for a relaunch.
    var isTerminating = false
    /// The "start at launch" session ran in this process (code M9), so re-enabling Awake doesn't start it again.
    var launchSessionStarted = false

    init() {}
}
