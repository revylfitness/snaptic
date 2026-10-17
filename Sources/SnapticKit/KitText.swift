import Foundation

/// Cleans text that comes from other apps (window titles, app names) before
/// Snaptic stores, searches or draws it.
package enum TextSanitizer {
    /// Words browsers put in the title of a private window (Firefox does; Safari
    /// and Chrome don't mark their private windows at all).
    package static let privateMarkers = [
        "private browsing", "incognito", "inprivate", "private window",
        "privater modus", "navigation privée", "navegación privada", "navigazione anonima",
        "navegação privada", "privénavigatie", "prywatne przeglądanie", "приватный просмотр",
        "プライベートブラウジング", "隐私浏览", "隱私瀏覽", "시크릿",
    ]

    /// Checks the full title, before it is shortened, so a long page title
    /// can't push the marker out of view.
    package static func hasPrivateMarker(_ title: String) -> Bool {
        guard !title.isEmpty else { return false }
        let lowered = title.lowercased()
        return privateMarkers.contains { lowered.contains($0) }
    }

    /// Limits length by Unicode scalars (not grapheme clusters, which can be
    /// arbitrarily large) and drops control and text-direction override
    /// characters.
    package static func clean(_ text: String, maxScalars: Int = 512) -> String {
        var scalars = String.UnicodeScalarView()
        var count = 0
        for scalar in text.unicodeScalars {
            if count >= maxScalars { break }
            switch scalar.value {
            case 0x00...0x1F, 0x7F...0x9F, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069:
                continue
            default:
                scalars.append(scalar)
                count += 1
            }
        }
        return String(scalars)
    }
}
