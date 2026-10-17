import Foundation

// Virtual-screen templates ("Recipes") and aspect presets (owner: D). PLAN §9.4.

package enum RecipeKind: String, Codable, CaseIterable, Sendable {
    case headless, recording, teleprompter, portrait

    package var title: String {
        switch self {
        case .headless: return L("Headless")
        case .recording: return L("Recording 16:9")
        case .teleprompter: return L("Teleprompter")
        case .portrait: return L("Portrait")
        }
    }

    package var summary: String {
        switch self {
        case .headless:
            return L("A HiDPI desktop for a Mac without a monitor (remote access). It reconnects at launch and keeps the Mac usable when no display is attached.")
        case .recording:
            return L("A 1920 × 1080 desktop for screen recordings, placed below-right of the main display so the pointer doesn't drift into it.")
        case .teleprompter:
            return L("A screen with the target display's shape, streamed flipped onto it.")
        case .portrait:
            return L("A 9:16 HiDPI desktop for portrait use.")
        }
    }
}

/// An aspect-ratio preset for the "New virtual screen" sheet.
package struct AspectPreset: Equatable, Sendable {
    package let title: String
    package let aspectWidth: Int
    package let aspectHeight: Int
    package let sizeInches: Double

    package init(_ title: String, _ aspectWidth: Int, _ aspectHeight: Int, sizeInches: Double = 27) {
        self.title = title
        self.aspectWidth = aspectWidth
        self.aspectHeight = aspectHeight
        self.sizeInches = sizeInches
    }
}

package enum Recipes {
    /// Aspect presets (parity catalog §3.1).
    package static let presets: [AspectPreset] = [
        AspectPreset("16:9", 16, 9),
        AspectPreset("16:10", 16, 10),
        AspectPreset("4:3", 4, 3, sizeInches: 20),
        AspectPreset("17:9 (DCI)", 256, 135),
        AspectPreset("21.3:9 (ultrawide)", 64, 27, sizeInches: 34),
        AspectPreset("21.5:9 (ultrawide)", 43, 18, sizeInches: 34),
        AspectPreset("24:10 (ultrawide)", 12, 5, sizeInches: 38),
        AspectPreset("32:10 (super ultrawide)", 16, 5, sizeInches: 49),
        AspectPreset("32:9 (super ultrawide)", 32, 9, sizeInches: 49),
        AspectPreset("1:1", 1, 1, sizeInches: 24),
        AspectPreset("3:2", 3, 2, sizeInches: 14),
        AspectPreset("5:4", 5, 4, sizeInches: 19),
        AspectPreset("iPad 4:3", 4, 3, sizeInches: 10.2),
        AspectPreset("iPad mini 15.2:10", 38, 25, sizeInches: 8.3),
        AspectPreset("iPad Air 14.4:10", 36, 25, sizeInches: 10.9),
        AspectPreset("iPad Pro 11\" 14.3:10", 143, 100, sizeInches: 11),
    ]

    /// A new user screen from a preset (or a custom aspect): standard mode ladder, HiDPI on.
    package static func spec(preset: AspectPreset, name: String? = nil, hiDPI: Bool = true, soc: SoCClass = .appleEntry,
                             id: StableID = StableID()) -> VirtualScreenSpec {
        VirtualScreenSpec(id: id, name: name ?? L("Virtual \(preset.title)"), aspectWidth: preset.aspectWidth,
                          aspectHeight: preset.aspectHeight, sizeInches: preset.sizeInches, hiDPI: hiDPI,
                          modes: VirtualScreenSpec.ladder(aspectWidth: preset.aspectWidth, aspectHeight: preset.aspectHeight,
                                                          hiDPI: hiDPI, soc: soc))
            .sanitized(soc: soc)
    }

    /// The spec for a recipe. `target` is the display a teleprompter streams onto (its
    /// aspect is used when known).
    package static func spec(for kind: RecipeKind, soc: SoCClass = .appleEntry, id: StableID = StableID(),
                             target: DisplayKey? = nil, targetAspect: (width: Int, height: Int)? = nil) -> VirtualScreenSpec {
        switch kind {
        case .headless:
            return VirtualScreenSpec(
                id: id, name: L("Headless"), aspectWidth: 16, aspectHeight: 9, sizeInches: 27, hiDPI: true,
                modes: [VirtualMode(width: 2560, height: 1440, hiDPI: true), VirtualMode(width: 1920, height: 1080, hiDPI: true)],
                recreateOnLaunch: true, headlessPrimary: true
            ).sanitized(soc: soc)
        case .recording:
            return VirtualScreenSpec(
                id: id, name: L("Recording"), aspectWidth: 16, aspectHeight: 9, sizeInches: 24, hiDPI: false,
                modes: [VirtualMode(width: 1920, height: 1080, hiDPI: false)],
                placement: .belowRightOfMain, wantsPIP: true
            ).sanitized(soc: soc)
        case .teleprompter:
            let aspect = reduced(targetAspect ?? (16, 9))
            var spec = VirtualScreenSpec(
                id: id, name: L("Teleprompter"), aspectWidth: aspect.width, aspectHeight: aspect.height, sizeInches: 24,
                hiDPI: false,
                modes: VirtualScreenSpec.ladder(aspectWidth: aspect.width, aspectHeight: aspect.height, hiDPI: false, soc: soc)
            )
            if let target {
                spec.associations = [VirtualAssociation(target: target, autoConnect: .whilePresent, presentation: .flippedStream)]
                spec.recreateOnLaunch = true
            }
            return spec.sanitized(soc: soc)
        case .portrait:
            return VirtualScreenSpec(
                id: id, name: L("Portrait"), aspectWidth: 9, aspectHeight: 16, sizeInches: 27, hiDPI: true,
                modes: VirtualScreenSpec.ladder(aspectWidth: 9, aspectHeight: 16, hiDPI: true, soc: soc)
            ).sanitized(soc: soc)
        }
    }

    /// `recreateOnLaunch` defaults on only with an association or PIP (§9.2).
    package static func defaultRecreateOnLaunch(_ spec: VirtualScreenSpec) -> Bool {
        spec.headlessPrimary || !spec.associations.isEmpty || spec.wantsPIP
    }

    /// Reduces an aspect ratio by its greatest common divisor (1920×1080 → 16:9).
    package static func reduced(_ aspect: (width: Int, height: Int)) -> (width: Int, height: Int) {
        let w = max(1, abs(aspect.width)), h = max(1, abs(aspect.height))
        var a = w, b = h
        while b != 0 { (a, b) = (b, a % b) }
        let g = max(1, a)
        let rw = w / g, rh = h / g
        if rw > VirtualScreenSpec.maxAspectComponent || rh > VirtualScreenSpec.maxAspectComponent { return (16, 9) }
        return (rw, rh)
    }
}
