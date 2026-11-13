import AppKit
import ApplicationServices
import SnapticKit

/// What one AX read of the Dock gave (§4.8).
enum DockRead<Value> {
    case value(Value)
    /// `kAXErrorCannotComplete`: the 0.15 s timeout ran out. Counts toward the back-off.
    case timedOut
    /// `kAXErrorInvalidUIElement`: the element is gone (the Dock restarted or rebuilt its list).
    case invalid
    case failed

    init(failure error: AXError) {
        switch error {
        case .cannotComplete: self = .timedOut
        case .invalidUIElement: self = .invalid
        default: self = .failed
        }
    }
}

/// Reads the Dock through AX (lead; PLAN 0.5 §4.8, A3): its `AXList`, the selected item, the item → app match and the
/// Dock's frame. Runs on `DockObserver`'s thread only, never on main. Every element it reads gets the 0.15 s timeout
/// (P-24, X-15), and item reads are one multi-attribute call. Nothing it reads is logged.
final class DockReader {
    static let bundleID = "com.apple.dock"
    /// Bundle ids read from `Info.plist`, by path; cleared when full.
    static let maxBundleIDs = 256
    /// More list children than this aren't read for the Dock's frame.
    static let maxItems = 200
    /// When a selected item falls outside the Dock's frame (an item was added, or the Dock moved), the frame is read
    /// again, at most this often.
    static let frameInterval: Double = 2

    private static let itemAttributes = [kAXSubroleAttribute, "AXIsApplicationRunning", kAXURLAttribute,
                                         kAXTitleAttribute, kAXPositionAttribute, kAXSizeAttribute]

    let pid: pid_t
    private let app: AXUIElement
    private(set) var list: AXUIElement?
    /// The union of the item frames (§R4 S0-1), in AppKit global coordinates.
    private(set) var listFrame: DockRect?
    /// Each item's frame at the last list-frame read, in AppKit global coordinates (A4a: the hit band's neighbours
    /// and the at-rest thickness, §4.1, §4.7).
    private(set) var itemFrames: [DockRect] = []
    private var frameReadAt: Double?
    private var bundleIDs: [String: String] = [:]   // "" when the bundle has none

    init(pid: pid_t) {
        self.pid = pid
        app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, WindowServices.axTimeout)
    }

    /// The Dock's application element (A4a: the Dock menu's open and close notifications, §2.4).
    var appElement: AXUIElement { app }

    private static func timed(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, WindowServices.axTimeout)
        return element
    }

    /// Finds the Dock's `AXList` among the app's children.
    func findList() -> DockRead<AXUIElement> {
        let read = AX.read(app, kAXChildrenAttribute)
        guard read.error == .success else { return DockRead(failure: read.error) }
        for child in AX.elements(in: read.value) where AX.string(Self.timed(child), kAXRoleAttribute) == kAXListRole {
            list = child
            return .value(child)
        }
        return .failed
    }

    /// The list's selected child: the item under the pointer, or nil when none is.
    func selectedChild() -> DockRead<AXUIElement?> {
        guard let list else { return .failed }
        let read = AX.read(list, kAXSelectedChildrenAttribute)
        switch read.error {
        case .success: return .value(AX.elements(in: read.value).first.map(Self.timed))
        case .noValue: return .value(nil)
        default: return DockRead(failure: read.error)
        }
    }

    /// One item as a `DockSelection`: its kind, its running app's pid (§4.8 item → app; §R4 S0-1) and its frame.
    func selection(of item: AXUIElement, apps: [DockRunningApp], primaryHeight: Double,
                   now: Double) -> DockRead<DockSelection> {
        let read = AX.values(item, Self.itemAttributes)
        guard read.error == .success else { return DockRead(failure: read.error) }
        let v = read.values
        let kind = DockReaderRules.kind(subrole: v[0] as? String)
        var pid: Int32?
        if kind == .app {
            let urlPath = (v[2] as? URL)?.path
            pid = DockReaderRules.pid(running: (v[1] as? NSNumber)?.boolValue, urlPath: urlPath,
                                      title: v[3] as? String, apps: apps,
                                      bundleIDAtURL: { self.bundleID(atPath: urlPath) })
        }
        let frame = Self.rect(v[4], v[5]).map { DockGeometry.cocoaRect(fromAX: $0, primaryHeight: primaryHeight) }
            ?? .zero
        if listFrame == nil || (!frame.isDegenerate && listFrame?.contains(frame) == false
                                && now - (frameReadAt ?? -.infinity) >= Self.frameInterval) {
            _ = readListFrame(primaryHeight: primaryHeight, now: now)
        }
        return .value(DockSelection(kind: kind, pid: pid, itemFrame: frame, listFrame: listFrame ?? frame))
    }

    /// Reads the Dock's frame again: the union of its item frames. Keeps the last frame when a read times out.
    @discardableResult
    func readListFrame(primaryHeight: Double, now: Double) -> DockRead<DockRect> {
        guard let list else { return .failed }
        frameReadAt = now
        let read = AX.read(list, kAXChildrenAttribute)
        guard read.error == .success else { return DockRead(failure: read.error) }
        var frames: [DockRect] = []
        for child in AX.elements(in: read.value).prefix(Self.maxItems) {
            let values = AX.values(Self.timed(child), [kAXPositionAttribute, kAXSizeAttribute])
            if values.error == .cannotComplete { return .timedOut }
            if let rect = Self.rect(values.values[0], values.values[1]) { frames.append(rect) }
        }
        guard let union = DockGeometry.dockFrame(items: frames) else { return .failed }
        let frame = DockGeometry.cocoaRect(fromAX: union, primaryHeight: primaryHeight)
        listFrame = frame
        itemFrames = frames.filter { !$0.isDegenerate }.map {
            DockGeometry.cocoaRect(fromAX: $0, primaryHeight: primaryHeight)
        }
        return .value(frame)
    }

    /// An AX frame (top-left origin) from a position and a size value.
    private static func rect(_ position: CFTypeRef?, _ size: CFTypeRef?) -> DockRect? {
        guard let p = AX.point(in: position), let s = AX.size(in: size) else { return nil }
        return DockRect(x: Double(p.x), y: Double(p.y), width: Double(s.width), height: Double(s.height))
    }

    /// The bundle id in `<path>/Contents/Info.plist` (step 2 of the match), read once per path.
    private func bundleID(atPath path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let key = DockReaderRules.normalizedPath(path)
        if let cached = bundleIDs[key] { return cached.isEmpty ? nil : cached }
        let plist = URL(fileURLWithPath: key).appendingPathComponent("Contents/Info.plist")
        let id = (NSDictionary(contentsOf: plist)?["CFBundleIdentifier"] as? String) ?? ""
        if bundleIDs.count >= Self.maxBundleIDs { bundleIDs.removeAll() }
        bundleIDs[key] = id
        return id.isEmpty ? nil : id
    }
}
