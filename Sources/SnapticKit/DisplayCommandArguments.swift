import Foundation

/// Splits a display verb's arguments into its values and an optional display selector
/// (PLAN §11): `set brightness 50 [display]`, `ddc set 10 50 [display]`, `get volume [display]`.
/// The selector is `--display <selector>` / `--display=<selector>` (passed through by the
/// CLI client), or everything after the values joined with single spaces, so an
/// unquoted name with spaces ("LG UltraFine") still works. The app resolves the selector
/// text with `DisplaySelectorResolver`.
package enum DisplayCommandArguments {
    package struct Split: Equatable, Sendable {
        package var values: [String]
        /// Nil when no selector was given (the verb's default applies).
        package var selector: String?

        package init(values: [String], selector: String?) {
            self.values = values
            self.selector = selector
        }
    }

    package static let displayOption = "--display"

    /// Nil when the arguments don't fit: wrong number of values, `--display` without a
    /// selector or given twice, or an empty selector.
    package static func split(_ arguments: [String], valueCount: Int) -> Split? {
        guard valueCount >= 0, valueCount <= 16 else { return nil }
        var args = arguments
        var selector: String?
        let optionIndices = args.indices.filter { args[$0] == displayOption || args[$0].hasPrefix(displayOption + "=") }
        if optionIndices.count > 1 { return nil }
        if let i = optionIndices.first {
            if args[i] == displayOption {
                guard i + 1 < args.count else { return nil }
                selector = args[i + 1]
                args.removeSubrange(i...(i + 1))
            } else {
                selector = String(args[i].dropFirst(displayOption.count + 1))
                args.remove(at: i)
            }
        } else if args.count > valueCount {
            selector = args[valueCount...].joined(separator: " ")
            args = Array(args.prefix(valueCount))
        }
        guard args.count == valueCount else { return nil }
        if let text = selector {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            selector = trimmed
        }
        return Split(values: args, selector: selector)
    }
}
