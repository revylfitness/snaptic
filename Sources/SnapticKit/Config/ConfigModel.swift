import Foundation

/// A persisted settings model or section. `sanitized()` clamps every value to what
/// the UI could have produced, because settings can be edited outside the app.
package protocol ConfigModel: Codable, Equatable, Sendable {
    init()
    func sanitized() -> Self
}
