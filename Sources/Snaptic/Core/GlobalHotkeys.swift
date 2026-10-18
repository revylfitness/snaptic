import AppKit
import Carbon.HIToolbox
import SnapticKit

/// 'SNPT': marks Snaptic's Carbon hot keys.
private let hotKeySignature: OSType = 0x534E_5054

/// One Carbon handler for every hot key. Carbon delivers on the main thread; the action
/// still runs in its own main-queue turn, outside Carbon's dispatch.
private let hotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr, hotKeyID.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
    let box = Unmanaged<CallbackTarget<GlobalHotkeys>>.fromOpaque(userData).takeUnretainedValue()
    let id = hotKeyID.id
    DispatchQueue.main.async { MainActor.assumeIsolated { box.target?.fire(id) } }
    return noErr
}

/// System-wide shortcuts through Carbon `RegisterEventHotKey` (PLAN §8.2): no TCC
/// permission, and they fire under Secure Event Input. Registrations end with their
/// lifetime; two Snaptic owners can't take the same combo.
@MainActor final class GlobalHotkeys {
    typealias Combo = HotkeyCombo
    struct Token: Hashable { let id: UInt32 }
    enum RegisterError: Error, Equatable {
        case conflict(owner: String)
        case systemRefused(Int32)
        /// The combo breaks a rule (`HotkeyRules.problem`); the text says which.
        case invalid(String)
        /// The lifetime had already ended.
        case ended
    }

    private struct Entry {
        let combo: Combo
        let owner: String
        let ref: EventHotKeyRef
        let action: @MainActor () -> Void
    }

    private var entries: [UInt32: Entry] = [:]
    private var nextID: UInt32 = 0
    private var handlerRef: EventHandlerRef?
    private var box: Unmanaged<CallbackTarget<GlobalHotkeys>>?

    init() {}

    func register(_ combo: Combo, owner: String, lifetime: Lifetime,
                  action: @escaping @MainActor () -> Void) throws -> Token {
        guard !lifetime.isEnded else { throw RegisterError.ended }
        let c = HotkeyRules.normalized(combo)
        if let problem = HotkeyRules.problem(c) { throw RegisterError.invalid(HotkeyRules.message(problem)) }
        if let existing = entries.values.first(where: { $0.combo == c }) {
            throw RegisterError.conflict(owner: existing.owner)
        }
        try installHandlerIfNeeded()
        nextID &+= 1
        if nextID == 0 { nextID = 1 }
        let id = nextID
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(c.keyCode, c.carbonModifiers, EventHotKeyID(signature: hotKeySignature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            if entries.isEmpty { removeHandler() }
            throw RegisterError.systemRefused(status)
        }
        entries[id] = Entry(combo: c, owner: owner, ref: ref, action: action)
        let token = Token(id: id)
        lifetime.onEnd { [weak self] in self?.unregister(token) }
        EventLog.shared.record(.keys, "Shortcut registered for \(owner)")
        return token
    }

    func unregister(_ token: Token) {
        guard let entry = entries.removeValue(forKey: token.id) else { return }
        UnregisterEventHotKey(entry.ref)
        if entries.isEmpty { removeHandler() }
    }

    func owner(of combo: Combo) -> String? {
        let c = HotkeyRules.normalized(combo)
        return entries.values.first { $0.combo == c }?.owner
    }

    /// Owners and display strings of everything registered (diagnostics, conflict notes).
    var registrations: [(owner: String, shortcut: String)] {
        entries.keys.sorted().compactMap { id in
            entries[id].map { ($0.owner, HotkeyRules.displayString($0.combo)) }
        }
    }

    fileprivate func fire(_ id: UInt32) {
        entries[id]?.action()
    }

    private func installHandlerIfNeeded() throws {
        guard handlerRef == nil else { return }
        let retained = Unmanaged.passRetained(CallbackTarget(self))
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, retained.toOpaque(), &ref)
        guard status == noErr, let ref else {
            retained.release()
            throw RegisterError.systemRefused(status)
        }
        handlerRef = ref
        box = retained
    }

    private func removeHandler() {
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        // Hops already queued hold the box (retained by their blocks); its target is weak.
        box?.release()
        box = nil
    }
}
