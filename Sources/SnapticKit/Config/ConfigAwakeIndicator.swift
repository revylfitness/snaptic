import Foundation

// Stub (owner: G). Hand-written by the lead in step 0 from PLAN 0.3 §2.14 (kind S).

/// Menu Bar page "Time" pop-up: Don't Show / Time Remaining / End Time (.icon = Don't Show).
package enum AwakeIndicatorStyle: String, Codable, CaseIterable, Sendable { case icon, iconAndTime, iconAndEndTime }

package enum AwakeGlyphFamily: String, Codable, CaseIterable, Sendable {
    /// cup.and.saucer / eye / lightbulb, outline idle, .fill active.
    case cup, eye, lightbulb

    package var idle: String {
        switch self {
        case .cup: return "cup.and.saucer"
        case .eye: return "eye"
        case .lightbulb: return "lightbulb"
        }
    }

    package var active: String { idle + ".fill" }
}

package struct AwakeIndicatorConfig: ConfigModel {
    package var style: AwakeIndicatorStyle
    package var glyph: AwakeGlyphFamily

    package init() {
        style = .icon
        glyph = .cup
    }

    private enum CodingKeys: String, CodingKey { case style, glyph }

    /// Lossy per field (R5-3); an unknown glyph decodes as `.cup`.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = c.lossy(.style, .icon)
        glyph = c.lossy(.glyph, .cup)
    }

    package func sanitized() -> AwakeIndicatorConfig { self }
}
