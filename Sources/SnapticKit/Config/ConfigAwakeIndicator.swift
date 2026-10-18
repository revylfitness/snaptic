import Foundation

// Awake status item settings (owner: G; PLAN 0.3 §2.14, §5.3). Edited on the Menu Bar page. Unknown legacy values
// (r1 drafts' mug, sun, bolt) decode as the defaults (M9).

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

    /// Both fields are closed enums that decode lossily, so there is nothing left to clamp.
    package func sanitized() -> AwakeIndicatorConfig { self }

    /// The SF Symbol for the item's current state.
    package func symbol(active: Bool) -> String { active ? glyph.active : glyph.idle }

    /// Whether the item shows text beside the glyph while a session with an end runs.
    package var showsTime: Bool { style != .icon }
}
