import Foundation

// A display mode as plain values (owner: B).

package struct DisplayModeDescriptor: Codable, Hashable, Sendable {
    package var ref: ModeRef
    package var isNative: Bool
    package var isDefault: Bool
    package var isUsableForDesktop: Bool
    package var ioFlags: UInt32
    package var bitDepth: Int

    package init(ref: ModeRef, isNative: Bool, isDefault: Bool, isUsableForDesktop: Bool, ioFlags: UInt32, bitDepth: Int) {
        self.ref = ref
        self.isNative = isNative
        self.isDefault = isDefault
        self.isUsableForDesktop = isUsableForDesktop
        self.ioFlags = ioFlags
        self.bitDepth = bitDepth
    }

    package var isHiDPI: Bool { ref.isHiDPI }
}
