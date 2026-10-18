import AppKit
import SnapticKit

/// The one way CLI verbs (and anything else that takes text) pick displays, so
/// `snaptic set brightness 50 2` and `snaptic rotate 2 90` mean the same "2" that
/// Identify shows (lead; PLAN §11).
///
/// - `main`, `mouse`/`pointer`, `focus`, `all`
/// - a bare number N: the Nth display in menu / Identify order (1-based, hidden included)
/// - `id:N`: a raw CGDirectDisplayID (desktop or hardware id)
/// - a 32-hex DisplayKey
/// - otherwise a name: an exact (case-insensitive) match wins, then a unique prefix
@MainActor enum DisplaySelectorResolver {
    enum Resolution: Equatable {
        case target(DisplayTarget)
        /// Several displays share the name prefix; exit with `ControlExit.usage`.
        case ambiguous([String])
        /// Exit with `ControlExit.notFound`.
        case notFound
    }

    /// Displays in Identify / menu order, including hidden ones.
    static func ordered(_ ctx: DisplaysContext) -> [DisplayInfo] {
        DisplaysMenuBuilder.orderedDisplays(ctx, includeHidden: true)
    }

    static func resolve(_ text: String, _ ctx: DisplaysContext) -> Resolution {
        let t = text.trimmingCharacters(in: .whitespaces)
        let displays = ordered(ctx)
        if let n = Int(t) {
            guard n >= 1, n <= displays.count else { return .notFound }
            return .target(.display(displays[n - 1].key))
        }
        guard let selector = ControlSelector.parse(t) else { return .notFound }
        switch selector {
        case .main: return .target(.main)
        case .mouse: return .target(.pointer)
        case .all: return .target(.all)
        case .focus:
            guard let id = NSScreen.main?.displayID,
                  let d = displays.first(where: { $0.desktopID == id || $0.hardwareID == id }) else { return .target(.main) }
            return .target(.display(d.key))
        case .key(let key):
            return displays.contains { $0.key == key } ? .target(.display(key)) : .notFound
        case .id(let id):
            guard let d = displays.first(where: { $0.desktopID == id || $0.hardwareID == id }) else { return .notFound }
            return .target(.display(d.key))
        case .name(let name):
            let lower = name.lowercased()
            if let exact = displays.first(where: { $0.name.lowercased() == lower }) { return .target(.display(exact.key)) }
            let matches = displays.filter { $0.name.lowercased().hasPrefix(lower) }
            switch matches.count {
            case 0: return .notFound
            case 1: return .target(.display(matches[0].key))
            default: return .ambiguous(matches.map(\.name))
            }
        }
    }

    /// Convenience for CLI handlers: either a target, or the response to return.
    static func resolveForCLI(_ text: String, _ ctx: DisplaysContext) -> (target: DisplayTarget?, error: ControlResponse?) {
        switch resolve(text, ctx) {
        case .target(let t): return (t, nil)
        case .notFound: return (nil, .failure(ControlExit.notFound, L("No display matches “\(text)”. Try `snaptic list`.")))
        case .ambiguous(let names):
            return (nil, .failure(ControlExit.usage,
                                  L("“\(text)” matches several displays: \(names.joined(separator: ", ")). Use its number or id:N.")))
        }
    }
}
