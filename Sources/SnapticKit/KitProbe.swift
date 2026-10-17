import Foundation

/// Proves the build setup: `package` access across modules (including the
/// universal XCBuild path) and LossyMap round-trips on Linux and macOS.
package enum KitProbe {
    package enum Color: String, Codable, CaseIterable, Sendable { case red, green }

    package struct Sample: Codable, Equatable, Sendable {
        package var map: LossyMap<Color, Int>
        package init(map: LossyMap<Color, Int>) { self.map = map }
    }

    /// Returns true when an encode/decode round-trip preserves the sample.
    package static func selfCheck() -> Bool {
        let sample = Sample(map: LossyMap([.red: 1, .green: 2]))
        guard let data = try? JSONEncoder().encode(sample),
              let decoded = try? JSONDecoder().decode(Sample.self, from: data) else { return false }
        return decoded == sample
    }
}
