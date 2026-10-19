import AppKit
import CoreGraphics
import SnapticKit

// Online displays for the display criterion (owner: J; PLAN 0.3 §2.7, §2.8): events only, through
// CGDisplayRegisterReconfigurationCallback (CallbackTarget refcon), debounced 1 s. Each online display gets a salted
// FingerprintRecord from CG facts (vendor, model, serial, UUID, built-in: tiers t2, t3, t5) via B's DisplayIdentity,
// so Awake works with the Displays module off. Removes its callback in `deactivate`.

@MainActor final class DisplayPresence: CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [.display] }
    static let debounceSeconds: TimeInterval = 1

    /// One row of the display picker ("When this display is connected").
    struct DisplayChoice: Equatable {
        let record: FingerprintRecord
        let name: String
        let isBuiltin: Bool
    }

    weak var context: AwakeContext?
    private let changes = ChangeFanout()
    private var active = false
    private var refcon: UnsafeMutableRawPointer?
    private let debounce = SourceTimer()

    private(set) var displays: [DisplayFact]?
    private(set) var mirroring: Bool?
    private(set) var choices: [DisplayChoice] = []

    init() {}

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        let box = Unmanaged.passRetained(CallbackTarget(self)).toOpaque()
        if CGDisplayRegisterReconfigurationCallback(Self.reconfigure, box) == .success {
            refcon = box
        } else {
            Unmanaged<CallbackTarget<DisplayPresence>>.fromOpaque(box).release()
        }
        read()
    }

    func deactivate() {
        guard active else { return }
        active = false
        if let box = refcon {
            CGDisplayRemoveReconfigurationCallback(Self.reconfigure, box)
            Unmanaged<CallbackTarget<DisplayPresence>>.fromOpaque(box).release()
        }
        refcon = nil
        debounce.cancel()
        displays = nil
        mirroring = nil
        choices = []
        context = nil
    }

    // MARK: CriterionSource

    func contribute(to facts: inout CriterionFacts) {
        guard active else { return }
        facts.displays = displays
        facts.mirroring = mirroring
    }

    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }

    // MARK: Reading

    private static let reconfigure: CGDisplayReconfigurationCallBack = { _, flags, refcon in
        guard let refcon, !flags.contains(.beginConfigurationFlag) else { return }
        let box = Unmanaged<CallbackTarget<DisplayPresence>>.fromOpaque(refcon).takeUnretainedValue()
        DispatchQueue.main.async { MainActor.assumeIsolated { box.target?.scheduleRead() } }
    }

    private func scheduleRead() {
        guard active else { return }
        debounce.once(after: Self.debounceSeconds) { [weak self] in self?.read() }
    }

    private func read() {
        guard active else { return }
        guard let ids = CGDirectDisplayID.onlineOrNil() else { return publish(nil, nil, []) }
        let salt = DisplayIdentity.salt()
        let names = Self.screenNames()
        var facts: [DisplayFact] = []
        var rows: [DisplayChoice] = []
        var mirrored = false
        for id in ids {
            let builtin = CGDisplayIsBuiltin(id) != 0
            if CGDisplayIsInMirrorSet(id) != 0 { mirrored = true }
            var uuid: String?
            if let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
                uuid = CFUUIDCreateString(kCFAllocatorDefault, cf) as String?
            }
            let identity = DisplayIdentityFacts(uuid: uuid, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                                serial: CGDisplaySerialNumber(id), isBuiltin: builtin)
            let record = DisplayIdentity.record(for: identity, salt: salt)
            facts.append(DisplayFact(record: record, isBuiltin: builtin))
            let name = names[id] ?? (builtin ? L("Built-in Display") : L("Display"))
            rows.append(DisplayChoice(record: record, name: name, isBuiltin: builtin))
        }
        publish(facts, mirrored, rows)
    }

    private func publish(_ facts: [DisplayFact]?, _ mirrored: Bool?, _ rows: [DisplayChoice]) {
        choices = rows
        guard facts != displays || mirrored != mirroring else { return }
        displays = facts
        mirroring = mirrored
        changes.fire()
    }

    /// NSScreen.localizedName per display id (only displays with a screen; mirrored members may have none).
    private static func screenNames() -> [CGDirectDisplayID: String] {
        var out: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            out[CGDirectDisplayID(n.uint32Value)] = screen.localizedName
        }
        return out
    }
}
