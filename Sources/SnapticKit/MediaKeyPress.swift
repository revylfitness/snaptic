import Foundation

/// One NX_SYSDEFINED media-key event (subtype 8), decoded from its `data1` word: the key
/// code in the high 16 bits, the key state in bits 8–15 (0xA down, 0xB up) and the repeat
/// flag in bit 0. Shared by the media-key tap and the untrusted-press monitor.
package struct MediaKeyPress: Equatable, Sendable {
    package enum Key: Sendable, Hashable, CaseIterable {
        case brightnessUp, brightnessDown, volumeUp, volumeDown, mute
    }

    /// NSEvent.EventSubtype raw value of auxiliary (media) key events.
    package static let auxiliaryKeySubtype = 8

    package var key: Key
    package var isDown: Bool
    package var isRepeat: Bool

    package init(key: Key, isDown: Bool, isRepeat: Bool) {
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
    }

    /// NX_KEYTYPE_* codes we handle.
    package static func key(forCode code: Int) -> Key? {
        switch code {
        case 0: return .volumeUp
        case 1: return .volumeDown
        case 2: return .brightnessUp
        case 3: return .brightnessDown
        case 7: return .mute
        default: return nil
        }
    }

    /// Nil for other subtypes, other keys, and states other than down (0xA) / up (0xB).
    package static func parse(subtype: Int, data1: Int) -> MediaKeyPress? {
        guard subtype == auxiliaryKeySubtype else { return nil }
        let code = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        guard let key = key(forCode: code), state == 0xA || state == 0xB else { return nil }
        return MediaKeyPress(key: key, isDown: state == 0xA, isRepeat: data1 & 0x1 != 0)
    }
}

/// "Brightness keys need Accessibility" (FIXES-R2 W4): shown once, on the first press the
/// keys feature would have handled while Snaptic isn't trusted. Never for key-ups,
/// repeats or presses macOS keeps anyway, and never again after it was shown or once the
/// permission arrives.
package struct UntrustedKeyNotice: Equatable, Sendable {
    package private(set) var shown = false

    package init() {}

    /// `wouldAct`: the keys feature's verdict for the press is not "pass".
    package mutating func shouldShow(_ press: MediaKeyPress, trusted: Bool, wouldAct: Bool) -> Bool {
        guard !shown, !trusted, press.isDown, !press.isRepeat, wouldAct else { return false }
        shown = true
        return true
    }

    /// Whether watching presses is still useful (nothing to say once shown or trusted).
    package func wantsPresses(trusted: Bool) -> Bool { !shown && !trusted }
}
