import Foundation

// Virtual screen specification (owner: D). PLAN §9.2, R5.6.

package struct VirtualMode: Codable, Hashable, Sendable {
    /// Points.
    package var width: Int
    package var height: Int
    package var hiDPI: Bool
    package var refreshMilliHz: Int
    package init(width: Int, height: Int, hiDPI: Bool, refreshMilliHz: Int = 60_000) {
        self.width = width
        self.height = height
        self.hiDPI = hiDPI
        self.refreshMilliHz = refreshMilliHz
    }
}

package struct VirtualScreenSpec: Codable, Equatable, Sendable {
    package var id: StableID
    package var name: String
    package var aspectWidth: Int
    package var aspectHeight: Int
    package var sizeInches: Double
    package var hiDPI: Bool
    package var modes: [VirtualMode]
    package var portrait: Bool
    package var recreateOnLaunch: Bool
    package var headlessPrimary: Bool

    package init(id: StableID = StableID(), name: String, aspectWidth: Int, aspectHeight: Int, sizeInches: Double,
                 hiDPI: Bool, modes: [VirtualMode], portrait: Bool = false, recreateOnLaunch: Bool = false,
                 headlessPrimary: Bool = false) {
        self.id = id
        self.name = name
        self.aspectWidth = aspectWidth
        self.aspectHeight = aspectHeight
        self.sizeInches = sizeInches
        self.hiDPI = hiDPI
        self.modes = modes
        self.portrait = portrait
        self.recreateOnLaunch = recreateOnLaunch
        self.headlessPrimary = headlessPrimary
    }

    /// Our virtual displays' vendor id: bit 15 set, so never a valid PNP id.
    package static let vendorID: UInt32 = 0xD354
    package static let productID: UInt32 = 0x0001
}
