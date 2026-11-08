import AppKit
import ApplicationServices
import SnapticKit

/// Other apps' menu bar extras, read through Accessibility (lead; PLAN 0.4 §4.2.6, §4.2.2, §4.12, A2): Kit's
/// `IconsInventoryPort`. The running apps are listed on main; every AX call runs on one serial background queue
/// with Kit's budgets (`IconsReadBudget`: 0.15 s a call, 0.5 s an app, 1.2 s a read, 50 extras an app), and the
/// result comes back on main. Snaptic's own process is never asked (its main thread would answer). Frames are
/// converted to AppKit's global space (R3-12). Titles go to the hidden list only and are never logged (§4.15).
@MainActor final class AXInventory: @preconcurrency IconsInventoryPort {
    /// `icons.inventoryTimeout` (once per read that ran out of budget), for the host.
    var onCount: ((IconsCounter) -> Void)?

    private let queue = DispatchQueue(label: "com.snaptic.icons.inventory", qos: .userInitiated)
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    /// Pids that had extras in the last read go first next time. Touched on `queue` only.
    nonisolated(unsafe) private var preferred: Set<Int32> = []

    init() {}

    // MARK: IconsInventoryPort

    /// Every app is read whatever the scope: the resolver decides which frames it trusts (R2-5).
    func read(scope: IconsReadScope, completion: @escaping (IconsInventory) -> Void) {
        guard AXIsProcessTrusted(), let primaryHeight = LengthBackend.primaryHeight else {
            let now = Self.wallClock()
            DispatchQueue.main.async { completion(.failure(readAt: now)) }
            return
        }
        let apps = runningApps()
        queue.async { [weak self] in
            let (inventory, timedOut) = Self.readAll(apps, primaryHeight: primaryHeight,
                                                      preferred: self?.preferred ?? [])
            self?.preferred = Set(inventory.apps.filter { !$0.extras.isEmpty }.map(\.pid))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { if timedOut { self?.onCount?(.inventoryTimeout) } }
                completion(inventory)
            }
        }
    }

    func readSystemIdentifiers(completion: @escaping (Set<String>?) -> Void) {
        let agents = runningApps().filter { IconsSystemIdentity.isMenuBarAgent(bundleID: $0.bundleID,
                                                                                bundlePath: $0.bundlePath) }
        guard AXIsProcessTrusted(), let agent = agents.first, let primaryHeight = LengthBackend.primaryHeight else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        queue.async {
            let now = Self.uptime()
            let (read, ids) = Self.readApp(agent, deadline: IconsReadBudget.appDeadline(
                appStart: now, readDeadline: now + IconsReadBudget.total), primaryHeight: primaryHeight)
            let result = read.result == .ok ? ids : nil
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: AXPress (§4.8, A6)

    /// Presses the app's extra at `index` among its `AXExtrasMenuBar` children, off main. `false` when it no longer
    /// exists or the app refused; the caller checks `Icons.disable.axpress` first.
    func press(pid: Int32, index: Int, completion: @escaping (Bool) -> Void) {
        guard pid != ownPID, index >= 0, AXIsProcessTrusted() else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        queue.async {
            let app = AXUIElementCreateApplication(pid)
            Self.limit(app)
            var ok = false
            if case .value(let bar) = Self.element(app, kAXExtrasMenuBarAttribute) {
                let children = Self.children(bar)
                if case .value(let list) = children, index < list.count {
                    Self.limit(list[index])
                    ok = AXUIElementPerformAction(list[index], kAXPressAction as CFString) == .success
                }
            }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    // MARK: Snapshot (main)

    struct App: Sendable {
        let pid: Int32
        let bundleID: String?
        let bundlePath: String?
    }

    private func runningApps() -> [App] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated, app.processIdentifier > 0, app.processIdentifier != ownPID else { return nil }
            return App(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                       bundlePath: app.bundleURL?.standardizedFileURL.path)
        }
    }

    // MARK: Read (queue)

    nonisolated private static func readAll(_ apps: [App], primaryHeight: Double,
                                            preferred: Set<Int32>) -> (IconsInventory, Bool) {
        let start = uptime()
        let readDeadline = start + IconsReadBudget.total
        let byPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var reads: [IconsAppRead] = []
        var systemIDs: Set<String>?
        var timedOut = false
        for pid in IconsReadBudget.order(apps.map(\.pid), preferred: preferred) {
            guard let app = byPID[pid] else { continue }
            let now = uptime()
            guard now < readDeadline else {
                timedOut = true
                reads.append(IconsAppRead(pid: pid, bundleID: app.bundleID, bundlePath: app.bundlePath,
                                          result: .timedOut))
                continue
            }
            let (read, ids) = readApp(app, deadline: IconsReadBudget.appDeadline(appStart: now,
                                                                                readDeadline: readDeadline),
                                      primaryHeight: primaryHeight)
            if read.result == .timedOut { timedOut = true }
            if read.result == .ok, IconsSystemIdentity.isMenuBarAgent(bundleID: app.bundleID,
                                                                      bundlePath: app.bundlePath) {
                systemIDs = ids
            }
            reads.append(read)
        }
        let failed = IconsReadBudget.failed(reads.map(\.result))
        return (IconsInventory(apps: reads, failed: failed, readAt: wallClock(), systemIdentifiers: systemIDs),
                timedOut)
    }

    /// One app: its extras (up to 50) and, for MenuBarAgent's kind of items, their `com.apple.menuextra.*` ids.
    nonisolated private static func readApp(_ app: App, deadline: Double,
                                            primaryHeight: Double) -> (IconsAppRead, Set<String>) {
        func done(_ result: IconsReadResult, _ extras: [IconsExtra] = []) -> IconsAppRead {
            IconsAppRead(pid: app.pid, bundleID: app.bundleID, bundlePath: app.bundlePath, result: result,
                         extras: extras)
        }
        let element = AXUIElementCreateApplication(app.pid)
        limit(element)
        let bar: AXUIElement
        switch Self.element(element, kAXExtrasMenuBarAttribute) {
        case .value(let v): bar = v
        case .error(let code): return (done(IconsAXError.result(code)), [])
        }
        let children: [AXUIElement]
        switch Self.children(bar) {
        case .value(let v): children = v
        case .error(let code): return (done(IconsAXError.result(code)), [])
        }
        guard !children.isEmpty else { return (done(.noExtras), []) }
        let wantIDs = IconsSystemIdentity.isMenuBarAgent(bundleID: app.bundleID, bundlePath: app.bundlePath)
        var extras: [IconsExtra] = []
        var ids: Set<String> = []
        for (index, child) in children.prefix(IconsReadBudget.maxExtras).enumerated() {
            guard uptime() < deadline else { return (done(.timedOut), []) }
            limit(child)
            let position = point(child), size = sizeOf(child)
            if case .error(let code) = position, IconsAXError.result(code) == .timedOut { return (done(.timedOut), []) }
            if case .error(let code) = size, IconsAXError.result(code) == .timedOut { return (done(.timedOut), []) }
            guard case .value(let p) = position, case .value(let s) = size,
                  let frame = IconsAXGeometry.appKitRect(x: Double(p.x), y: Double(p.y), width: Double(s.width),
                                                         height: Double(s.height), primaryHeight: primaryHeight)
            else { continue }
            let title = string(child, kAXTitleAttribute) ?? string(child, kAXDescriptionAttribute)
            extras.append(IconsExtra(pid: app.pid, bundleID: app.bundleID, index: index, frame: frame,
                                     title: title?.isEmpty == false ? title : nil))
            if wantIDs {
                var first: String?
                if case .value(let kids) = Self.children(child), let kid = kids.first {
                    limit(kid)
                    first = string(kid, kAXIdentifierAttribute)
                }
                if let id = IconsSystemIdentity.identifier(firstChild: first, own: string(child, kAXIdentifierAttribute)) {
                    ids.insert(id)
                }
            }
        }
        return (done(.ok, extras), ids)
    }

    // MARK: AX calls (queue)

    private enum Answer<T> {
        case value(T)
        case error(Int32)
    }

    nonisolated private static func limit(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, Float(IconsReadBudget.perCall))
    }

    nonisolated private static func copy(_ element: AXUIElement, _ attribute: String) -> Answer<CFTypeRef> {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success else { return .error(err.rawValue) }
        guard let value else { return .error(IconsAXError.noValue) }
        return .value(value)
    }

    nonisolated private static func element(_ element: AXUIElement, _ attribute: String) -> Answer<AXUIElement> {
        switch copy(element, attribute) {
        case .error(let code): return .error(code)
        case .value(let v):
            // An app controls what it returns: only an element may reach calls that expect one.
            guard CFGetTypeID(v) == AXUIElementGetTypeID() else { return .error(IconsAXError.noValue) }
            return .value(v as! AXUIElement)
        }
    }

    nonisolated private static func children(_ element: AXUIElement) -> Answer<[AXUIElement]> {
        switch copy(element, kAXChildrenAttribute) {
        case .error(let code): return .error(code)
        case .value(let v):
            guard let array = v as? [AnyObject] else { return .error(IconsAXError.noValue) }
            return .value(array.compactMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil })
        }
    }

    nonisolated private static func point(_ element: AXUIElement) -> Answer<CGPoint> {
        switch copy(element, kAXPositionAttribute) {
        case .error(let code): return .error(code)
        case .value(let v):
            var p = CGPoint.zero
            guard CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetValue(v as! AXValue, .cgPoint, &p) else {
                return .error(IconsAXError.noValue)
            }
            return .value(p)
        }
    }

    nonisolated private static func sizeOf(_ element: AXUIElement) -> Answer<CGSize> {
        switch copy(element, kAXSizeAttribute) {
        case .error(let code): return .error(code)
        case .value(let v):
            var s = CGSize.zero
            guard CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetValue(v as! AXValue, .cgSize, &s) else {
                return .error(IconsAXError.noValue)
            }
            return .value(s)
        }
    }

    nonisolated private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        if case .value(let v) = copy(element, attribute) { return v as? String }
        return nil
    }

    nonisolated private static func uptime() -> Double { ProcessInfo.processInfo.systemUptime }
    nonisolated private static func wallClock() -> Double { Date().timeIntervalSinceReferenceDate }
}
