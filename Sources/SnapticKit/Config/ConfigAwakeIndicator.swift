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

    /// 0.3.1 B1: the family's own SF Symbol while lid-closed mode is on, if it has one. None of the three families
    /// has a lid variant among the symbols this project can rely on (the macOS 15 SDK), so every family returns nil
    /// and the indicator draws `active` composited with a short bar under it (`lidBarHeightRatio`, a template image
    /// tested at 15 pt), which stays visibly different from N11's dot. HW-30 records the look.
    package var lidActiveSymbol: String? {
        switch self {
        case .cup, .eye, .lightbulb: return nil
        }
    }

    /// The fallback bar under the active glyph: its height and its gap above, as fractions of the glyph's height.
    package static let lidBarHeightRatio = 0.12
    package static let lidBarGapRatio = 0.1
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

    /// 0.3.1 B1: while lid-closed mode is on, the family's lid symbol, or nil when the app draws `symbol(active:
    /// true)` with the bar under it.
    package func lidSymbol() -> String? { glyph.lidActiveSymbol }

    /// Whether the item shows text beside the glyph while a session with an end runs.
    package var showsTime: Bool { style != .icon }
}
