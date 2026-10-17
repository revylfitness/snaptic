import Foundation

// Objective-C type-encoding comparison (owner: B). PLAN §3.1: shims return raw
// `method_getTypeEncoding` strings; Swift compares them here before a private selector is
// used. BOOL is `B` on arm64 and `c` on x86_64 (R2C c7), so they compare equal.

package enum KitEncoding {
    private static let qualifiers: Set<Character> = ["r", "n", "N", "o", "O", "R", "V", "A", "j", "+", "|", "!"]
    private static let simple: Set<Character> = ["c", "i", "s", "l", "q", "C", "I", "S", "L", "Q", "f", "d", "D", "B",
                                                 "v", "*", "#", ":", "?", "t", "T"]

    /// Type tokens without frame offsets or qualifiers, e.g. "v20@0:8B16" → ["v", "@", ":", "B"].
    /// Nil when the string isn't a well-formed encoding (fail closed).
    package static func tokens(_ encoding: String) -> [String]? {
        let chars = Array(encoding)
        guard chars.count <= 1024 else { return nil }
        var i = 0
        var out: [String] = []
        while i < chars.count {
            guard let parsed = parseType(chars, i, depth: 0) else { return nil }
            out.append(parsed.0)
            i = parsed.1
            while i < chars.count, chars[i].isNumber || chars[i] == "-" { i += 1 }   // frame offset
        }
        return out.isEmpty ? nil : out
    }

    private static func parseType(_ c: [Character], _ start: Int, depth: Int) -> (String, Int)? {
        guard depth < 16 else { return nil }
        var i = start
        while i < c.count, qualifiers.contains(c[i]) { i += 1 }
        guard i < c.count else { return nil }
        let ch = c[i]
        switch ch {
        case "@":
            i += 1
            if i < c.count, c[i] == "?" { return ("@?", i + 1) }                       // block
            if i < c.count, c[i] == "\"" {                                               // @"ClassName"
                guard let close = c[(i + 1)...].firstIndex(of: "\"") else { return nil }
                return ("@", close + 1)
            }
            return ("@", i)
        case "^":
            guard let inner = parseType(c, i + 1, depth: depth + 1) else { return nil }
            return ("^" + inner.0, inner.1)
        case "{", "(":
            let closeChar: Character = ch == "{" ? "}" : ")"
            var level = 0
            var j = i
            while j < c.count {
                if c[j] == ch { level += 1 } else if c[j] == closeChar {
                    level -= 1
                    if level == 0 { break }
                }
                j += 1
            }
            guard j < c.count else { return nil }
            // Keep the aggregate's name only ("{CGPoint=dd}" → "{CGPoint}") plus its body's tokens.
            let body = String(c[(i + 1)..<j])
            let name = body.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
            return (String(ch) + name + String(closeChar), j + 1)
        case "[":
            var j = i + 1
            var count = ""
            while j < c.count, c[j].isNumber { count.append(c[j]); j += 1 }
            guard let inner = parseType(c, j, depth: depth + 1), inner.1 < c.count, c[inner.1] == "]" else { return nil }
            return ("[" + count + inner.0 + "]", inner.1 + 1)
        case "b":
            var j = i + 1
            var bits = ""
            while j < c.count, c[j].isNumber { bits.append(c[j]); j += 1 }
            guard !bits.isEmpty else { return nil }
            return ("b" + bits, j)
        default:
            guard simple.contains(ch) else { return nil }
            return (String(ch), i + 1)
        }
    }

    /// Digits removed (the legacy normalizer SNEncoding also exposes).
    package static func normalized(_ encoding: String) -> String { String(encoding.filter { !$0.isNumber }) }

    /// True when `actual` (from the running OS) matches `expected` (from our table).
    package static func matches(actual: String, expected: String, boolAware: Bool = true) -> Bool {
        guard let a = tokens(actual), let e = tokens(expected), a.count == e.count else { return false }
        for (x, y) in zip(a, e) where x != y {
            if boolAware && Set([x, y]) == Set(["B", "c"]) { continue }
            return false
        }
        return true
    }

    /// One selector's expectation, checked against the encoding the shim reports.
    package struct Requirement: Equatable, Sendable {
        package var selector: String
        package var expected: String
        package init(_ selector: String, _ expected: String) {
            self.selector = selector
            self.expected = expected
        }
    }

    /// Selectors that are missing or whose encoding differs (empty = all good).
    package static func failures(_ requirements: [Requirement], actual: (String) -> String?) -> [String] {
        requirements.compactMap { r in
            guard let a = actual(r.selector), matches(actual: a, expected: r.expected) else { return r.selector }
            return nil
        }
    }
}
