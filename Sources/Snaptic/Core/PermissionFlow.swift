import AppKit
import SwiftUI
import SnapticKit
import SnapticShims

enum PermissionStatus: Equatable { case granted, denied, unknown }

/// One guided request per permission (PLAN §1.1, R3C §5.5, macos27.md §1a):
/// 1. the system prompt once per flow; 2. the Privacy pane always opened too; 3. the exact
/// app path with "Show Snaptic in Finder" and "Click +"; 4. polling at 1.5 s while needed,
/// resumed on app activation, stopped on grant, when every requester's lifetime ends, or
/// after 10 minutes ("Check again"); 5. "Relaunch Snaptic" as soon as the pane was opened.
/// Callers coalesce; the guide window opens by itself at most once per launch.
@MainActor final class PermissionFlow: ObservableObject {
    static let pollInterval: TimeInterval = 1.5
    static let pollLimit: TimeInterval = 10 * 60
    static let staleGrantDelay: TimeInterval = 30

    @Published private(set) var granted: Set<Permission> = []

    /// Set by the host; used by "Relaunch Snaptic".
    var relauncher: Relauncher?
    /// While onboarding runs, automatic requests poll quietly instead of opening a guide:
    /// permissions are asked for afterwards, only for what was chosen (PLAN §3.7).
    var holdAutomaticGuides = false
    /// Snaptic ran for this user before (set by the host). A missing Accessibility grant
    /// then most likely means macOS still lists an older copy (W5).
    var launchedBefore = false

    private var flows: [Permission: Flow] = [:]
    private var shownThisLaunch: Set<Permission> = []
    /// Guides waiting for the open one to close: one guide window at a time.
    private var guideQueue: [Permission] = []
    private var observers: [(id: UInt64, handler: @MainActor (Permission, Bool) -> Void)] = []
    private var observerSerial: UInt64 = 0
    private var activationToken: NSObjectProtocol?

    init(relauncher: Relauncher? = nil) {
        self.relauncher = relauncher
        granted = Set(Permission.allCases.filter { Self.isGranted($0) })
        activationToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applicationBecameActive() }
        }
    }

    // MARK: API

    func state(_ permission: Permission) -> PermissionStatus {
        Self.isGranted(permission) ? .granted : .denied
    }

    /// Coalesced per permission; never blocks. The guide opens at most once per launch by
    /// itself; later requests poll quietly until the grant or until `lifetime` ends.
    func request(_ permission: Permission, reason: String, lifetime: Lifetime) {
        refresh()
        guard !granted.contains(permission), !lifetime.isEnded else { return }
        let flow = flow(for: permission)
        flow.add(reason: reason)
        flow.addRequester(lifetime) { [weak self] in self?.requesterEnded(permission) }
        if !shownThisLaunch.contains(permission) && !holdAutomaticGuides {
            shownThisLaunch.insert(permission)
            begin(flow, showGuide: true)
        } else {
            begin(flow, showGuide: false)
        }
    }

    /// User-initiated ("Grant…" in Settings or the menu): always shows the guide.
    func presentGuide(_ permission: Permission, reason: String? = nil) {
        refresh()
        let flow = flow(for: permission)
        if let reason { flow.add(reason: reason) }
        shownThisLaunch.insert(permission)
        begin(flow, showGuide: true)
    }

    /// Calls `handler(permission, granted)` on every change until `lifetime` ends.
    func observe(lifetime: Lifetime, _ handler: @escaping @MainActor (Permission, Bool) -> Void) {
        guard !lifetime.isEnded else { return }
        observerSerial &+= 1
        let id = observerSerial
        observers.append((id, handler))
        lifetime.onEnd { [weak self] in self?.observers.removeAll { $0.id == id } }
    }

    /// Re-reads both permissions (cheap); called by polling, app activation and menus.
    func refresh() {
        let now = Set(Permission.allCases.filter { Self.isGranted($0) })
        guard now != granted else { return }
        let changed = now.symmetricDifference(granted)
        granted = now
        for permission in Permission.allCases where changed.contains(permission) {
            let isGranted = now.contains(permission)
            EventLog.shared.record(.permissions, "\(permission.rawValue) \(isGranted ? "granted" : "revoked")")
            if isGranted, let flow = flows[permission] { finish(flow, granted: true) }
            for observer in observers { observer.handler(permission, isGranted) }
        }
    }

    // MARK: Flows

    private func flow(for permission: Permission) -> Flow {
        if let existing = flows[permission] { return existing }
        let flow = Flow(permission: permission)
        if HostUIRules.showsReAddStepsAtOnce(permission, launchedBefore: launchedBefore,
                                             granted: Self.isGranted(permission)) {
            flow.model.reAddAtOnce = true
        }
        flow.model.onOpenPane = { [weak self, weak flow] in
            guard let flow else { return }
            self?.openPane(flow)
        }
        flow.model.onRelaunch = { [weak self] in
            self?.relauncher?.relaunch(reason: "permission granted")
        }
        flow.model.onCheckAgain = { [weak self, weak flow] in
            guard let self, let flow else { return }
            self.refresh()
            if !self.granted.contains(flow.permission) { self.startPolling(flow) }
        }
        flow.model.onWindowClosed = { [weak self, weak flow] in
            guard let self, let flow else { return }
            flow.window = nil
            if !flow.hasLiveRequesters { self.finish(flow, granted: false) }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.showNextGuide() }
            }
        }
        flows[permission] = flow
        return flow
    }

    private func begin(_ flow: Flow, showGuide: Bool) {
        if !flow.prompted {
            flow.prompted = true
            // Once per flow, never per tick. On macOS 27 this may show nothing, so the
            // pane is opened as well.
            switch flow.permission {
            case .accessibility: Permissions.promptAccessibility()
            case .screenRecording: Permissions.requestScreenRecording()
            }
        }
        if showGuide {
            if flows.values.contains(where: { $0.window != nil && $0 !== flow }) {
                if !guideQueue.contains(flow.permission) { guideQueue.append(flow.permission) }
            } else {
                showWindow(flow)
                if flow.model.paneOpenedAt == nil { openPane(flow) }
            }
        }
        startPolling(flow)
    }

    /// Shows the next queued guide whose permission is still missing.
    private func showNextGuide() {
        guard !flows.values.contains(where: { $0.window != nil }) else { return }
        while !guideQueue.isEmpty {
            let permission = guideQueue.removeFirst()
            guard !granted.contains(permission), let flow = flows[permission] else { continue }
            showWindow(flow)
            if flow.model.paneOpenedAt == nil { openPane(flow) }
            return
        }
    }

    private func openPane(_ flow: Flow) {
        switch flow.permission {
        case .accessibility: Permissions.openAccessibilitySettings()
        case .screenRecording: Permissions.openScreenRecordingSettings()
        }
        if flow.model.paneOpenedAt == nil { flow.model.paneOpenedAt = Date() }
    }

    private func startPolling(_ flow: Flow) {
        flow.pollStarted = Date()
        flow.model.timedOut = false
        guard flow.timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self, weak flow] _ in
            MainActor.assumeIsolated {
                guard let self, let flow else { return }
                self.tick(flow)
            }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        flow.timer = timer
    }

    private func tick(_ flow: Flow) {
        refresh()
        guard flows[flow.permission] === flow else { return }
        if let opened = flow.model.paneOpenedAt, Date().timeIntervalSince(opened) > Self.staleGrantDelay {
            flow.model.showStaleHint = true
        }
        if Date().timeIntervalSince(flow.pollStarted) > Self.pollLimit {
            flow.stopTimer()
            flow.model.timedOut = true
            if flow.window == nil && !flow.hasLiveRequesters { finish(flow, granted: false) }
        }
    }

    private func requesterEnded(_ permission: Permission) {
        guard let flow = flows[permission], !flow.hasLiveRequesters, flow.window == nil else { return }
        finish(flow, granted: false)
    }

    private func finish(_ flow: Flow, granted: Bool) {
        flow.stopTimer()
        if granted, flow.permission == .screenRecording, flow.window != nil {
            // Capture needs a fresh process after the grant; keep the window for Relaunch.
            flow.model.granted = true
            return
        }
        let hadWindow = flow.window != nil
        flow.window?.close()
        flow.window = nil
        flows[flow.permission] = nil
        guideQueue.removeAll { $0 == flow.permission }
        if hadWindow {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.showNextGuide() }
            }
        }
    }

    private func applicationBecameActive() {
        refresh()
        for flow in flows.values where flow.model.timedOut { startPolling(flow) }
    }

    private func showWindow(_ flow: Flow) {
        if flow.window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = Self.paneName(flow.permission)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PermissionGuideView(model: flow.model))
            window.center()
            let delegate = GuideWindowDelegate { [weak flow] in flow?.model.onWindowClosed?() }
            window.delegate = delegate
            flow.windowDelegate = delegate
            flow.window = window
        }
        NSApp.activate()
        flow.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Facts

    static func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility: return Permissions.accessibility
        case .screenRecording: return Permissions.screenRecording
        }
    }

    static var isMacOS27OrLater: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }

    /// The pane's name on this macOS version.
    static func paneName(_ permission: Permission) -> String {
        switch permission {
        case .accessibility:
            return isMacOS27OrLater ? L("Device Control and Data Access") : L("Accessibility")
        case .screenRecording:
            return L("Screen & System Audio Recording")
        }
    }

    static func purpose(_ permission: Permission) -> String {
        switch permission {
        case .accessibility:
            return L("Lets Snaptic see its shortcuts, list and switch windows, and read display keys.")
        case .screenRecording:
            return L("Lets Snaptic show window thumbnails and previews, and picture in picture.")
        }
    }

    /// The running bundle (what the user must add with +).
    static var bundlePath: String { Bundle.main.bundlePath }

    /// "ad-hoc", "Developer ID Application: …" or "unsigned" (R5.7).
    static var signer: String { SNProcess.signerDescriptionOfSelf() }

    /// Another program running as this user could replace a bundle in a folder the user
    /// can write to, and inherit the grant (R5.7: warn before a grant).
    static var bundleIsUserWritable: Bool {
        let path = bundlePath
        let parent = (path as NSString).deletingLastPathComponent
        if access(path, W_OK) == 0 || access(parent, W_OK) == 0 { return true }
        var info = stat()
        if lstat(path, &info) == 0, info.st_uid == getuid() { return true }
        return false
    }

    static var isTranslocated: Bool { KitArgs.isTranslocated(bundlePath) }
}

// MARK: - Flow state

@MainActor private final class Flow {
    let permission: Permission
    let model: GuideModel
    var prompted = false
    var timer: Timer?
    var pollStarted = Date()
    var window: NSWindow?
    var windowDelegate: GuideWindowDelegate?
    private var requesters: [Lifetime] = []

    init(permission: Permission) {
        self.permission = permission
        model = GuideModel(permission: permission)
    }

    var hasLiveRequesters: Bool { requesters.contains { !$0.isEnded } }

    func add(reason: String) {
        let text = TextSanitizer.clean(reason, maxScalars: 200)
        if !text.isEmpty, !model.reasons.contains(text) { model.reasons.append(text) }
    }

    func addRequester(_ lifetime: Lifetime, onEnd: @escaping @MainActor () -> Void) {
        requesters.removeAll { $0.isEnded }
        guard !requesters.contains(where: { $0 === lifetime }) else { return }
        requesters.append(lifetime)
        lifetime.onEnd(onEnd)
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

private final class GuideWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: @MainActor () -> Void
    init(onClose: @escaping @MainActor () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { onClose() }
    }
}

@MainActor private final class GuideModel: ObservableObject {
    let permission: Permission
    @Published var reasons: [String] = []
    @Published var paneOpenedAt: Date?
    @Published var showStaleHint = false
    /// The remove-and-add-again steps show from the start (W5).
    @Published var reAddAtOnce = false
    @Published var timedOut = false
    @Published var granted = false
    var onOpenPane: (@MainActor () -> Void)?
    var onRelaunch: (@MainActor () -> Void)?
    var onCheckAgain: (@MainActor () -> Void)?
    var onWindowClosed: (@MainActor () -> Void)?

    let path = PermissionFlow.bundlePath
    let signer = PermissionFlow.signer
    let userWritable = PermissionFlow.bundleIsUserWritable
    let translocated = PermissionFlow.isTranslocated

    init(permission: Permission) { self.permission = permission }
}

private struct PermissionGuideView: View {
    @ObservedObject var model: GuideModel

    private var pane: String { PermissionFlow.paneName(model.permission) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("Allow Snaptic in ") + pane)
                    .font(.title2.weight(.semibold))
                Text(PermissionFlow.purpose(model.permission))
                    .foregroundStyle(.secondary)
                if !model.reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.reasons, id: \.self) { reason in
                            Label(reason, systemImage: "checkmark.circle").font(.callout)
                        }
                    }
                }
                if model.translocated {
                    warning(L("Snaptic is running from a temporary location macOS picked (App Translocation). Quit it, move Snaptic.app to the Applications folder, and open it from there before you grant access."))
                }
                if model.reAddAtOnce && !model.granted {
                    Label(L("Snaptic ran on this Mac before. If it is already listed and switched on, macOS is holding on to an older copy: select Snaptic in the list, remove it with −, then add it again with + and switch it on."),
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout)
                }
                if model.granted {
                    Label(L("Access granted. Relaunch Snaptic so it takes effect."), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        step(1, L("Open System Settings → Privacy & Security → ") + pane + ".")
                        Button(L("Open System Settings")) { model.onOpenPane?() }
                        Text(L("If System Settings was already open, the link may not switch panes. Quit System Settings and click the button again."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        step(2, L("If Snaptic isn't listed, click +, then choose this copy of Snaptic:"))
                        Text(model.path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(3)
                        Button(L("Show Snaptic in Finder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: model.path)])
                        }
                        step(3, L("Switch Snaptic on."))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                LabeledContent {
                    Text(model.signer)
                } label: {
                    Text(L("Signed by"))
                }
                .font(.caption)
                if model.userWritable {
                    warning(L("Snaptic is in a folder your account can change, so another program could replace it and inherit this permission. Prefer a signed release, or install with INSTALL=1 (owned by root)."))
                }

                if model.showStaleHint && !model.reAddAtOnce {
                    Text(L("Already switched on but this window stays? Select Snaptic in the list, remove it with −, then add it again with +."))
                        .font(.callout)
                }

                HStack {
                    if model.paneOpenedAt != nil || model.granted {
                        Button(L("I turned it on — Relaunch Snaptic")) { model.onRelaunch?() }
                            .keyboardShortcut(.defaultAction)
                    }
                    if model.timedOut {
                        Button(L("Check again")) { model.onCheckAgain?() }
                    }
                    Spacer()
                }
                if PermissionFlow.isMacOS27OrLater && model.permission == .accessibility {
                    Text(L("On macOS 27 the change often only takes effect after Snaptic relaunches."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 560)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).").fontWeight(.semibold)
            Text(text)
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .font(.callout)
    }
}
