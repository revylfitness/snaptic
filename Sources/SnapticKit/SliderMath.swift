import Foundation

// Slider, field and stepper arithmetic for Settings (H; PLAN 0.3 §4.1, N4, N12). Everything here is hand-written:
// no Foundation formatters, so the app and the Linux tests see the same text, and the app passes the system's
// decimal separator once.

/// Units and scaling for display, typing and VoiceOver.
package enum ValueFormat: Equatable, Sendable {
    /// Shows 0…`of` as 0–100% (`.percent(of: 1)`; `.percent(of: 100)` for values stored as percent).
    case percent(of: Double)
    /// "5 s", "1.5 s".
    case seconds
    /// "15 min".
    case minutes
    /// "60 Hz", "59.94 Hz".
    case hertz
    /// "170 pt".
    case points
    /// "500 nits".
    case nits
    /// "6500 K".
    case kelvin
    /// A number with exactly `digits` decimals (0…6) and no unit.
    case plain(digits: Int)
}

package enum SliderMath {
    /// Longest text `parse` looks at.
    package static let maxInputLength = 64
    /// Most digits `parse` accepts (Double keeps 15 exactly).
    package static let maxDigits = 15

    // MARK: Values

    /// Clamped to `range` and snapped to `step` (when given, > 0 and finite). Non-finite values become the lower
    /// bound. The result carries no binary noise beyond the step's own decimals (0.1 × 3 is 0.3).
    package static func clampSnap(_ value: Double, range: ClosedRange<Double>, step: Double?) -> Double {
        let lo = range.lowerBound, hi = range.upperBound
        guard value.isFinite else { return lo }
        var v = min(hi, max(lo, value))
        guard let s = validStep(step) else { return v }
        let n = ((v - lo) / s).rounded()
        v = lo + n * s
        let places = max(decimalPlaces(s), decimalPlaces(lo))
        if places > 0 && places <= 12 {
            let scale = pow10(places)
            let scaled = v * scale
            if abs(scaled) < 9e15 { v = scaled.rounded() / scale }
        }
        return min(hi, max(lo, v))
    }

    /// True when `value` shows as the default: within half a step (`step` nil: a tiny relative tolerance). A nil
    /// default (live values such as Brightness) counts as "at the default", so no reset glyph ever appears.
    package static func isDefault(value: Double, default defaultValue: Double?, step: Double?) -> Bool {
        guard let d = defaultValue else { return true }
        guard value.isFinite, d.isFinite else { return value == d }
        if let s = validStep(step) { return abs(value - d) < s / 2 }
        return abs(value - d) <= 1e-9 * max(1, abs(d))
    }

    /// The step the reset glyph compares with: `step`, or the smallest change the format shows.
    package static func effectiveStep(_ step: Double?, format: ValueFormat) -> Double {
        if let s = validStep(step) { return s }
        switch format {
        case .percent(let of): return abs(of) > 0 && abs(of).isFinite ? abs(of) / 100 : 0.01
        case .seconds, .minutes: return 0.1
        case .hertz: return 0.01
        case .points, .nits, .kelvin: return 1
        case .plain(let digits): return 1 / pow10(clampDigits(digits))
        }
    }

    /// Number of slider positions when `step` divides the range into ≤ `limit` (tick marks); nil otherwise.
    package static func positions(range: ClosedRange<Double>, step: Double?, limit: Int = 11) -> Int? {
        guard let s = validStep(step) else { return nil }
        let span = range.upperBound - range.lowerBound
        guard span.isFinite, span >= 0 else { return nil }
        let count = (span / s * (1 + 1e-12)).rounded(.down) + 1
        guard count <= Double(limit) else { return nil }
        return Int(count)
    }

    /// One step up or down (`direction` > 0 or < 0): `step`, or 1% of the range for continuous sliders.
    package static func nudged(_ value: Double, direction: Int, range: ClosedRange<Double>, step: Double?) -> Double {
        guard direction != 0 else { return clampSnap(value, range: range, step: step) }
        let delta = validStep(step) ?? (range.upperBound - range.lowerBound) / 100
        let start = value.isFinite ? value : range.lowerBound
        return clampSnap(start + (direction > 0 ? delta : -delta), range: range, step: step)
    }

    // MARK: Text

    /// Hand-formatted with the unit inside the text: "70%", "60 Hz", "15 min", "6500 K". Non-finite: "–".
    package static func format(_ value: Double, _ format: ValueFormat, decimalSeparator: String) -> String {
        guard value.isFinite else { return "–" }
        let sep = separator(decimalSeparator)
        switch format {
        case .percent(let of):
            guard abs(of) > 0, of.isFinite else { return "–" }
            return number(value / of * 100, digits: 0, trim: false, separator: sep) + "%"
        case .seconds: return number(value, digits: 1, trim: true, separator: sep) + " s"
        case .minutes: return number(value, digits: 1, trim: true, separator: sep) + " min"
        case .hertz: return number(value, digits: 2, trim: true, separator: sep) + " Hz"
        case .points: return number(value, digits: 0, trim: false, separator: sep) + " pt"
        case .nits: return number(value, digits: 0, trim: false, separator: sep) + " nits"
        case .kelvin: return number(value, digits: 0, trim: false, separator: sep) + " K"
        case .plain(let digits): return number(value, digits: clampDigits(digits), trim: false, separator: sep)
        }
    }

    /// VoiceOver text: "70 percent", "1 minute", "1512 by 982".
    package static func spoken(_ value: Double, _ format: ValueFormat, decimalSeparator: String) -> String {
        guard value.isFinite else { return L("no value") }
        let sep = separator(decimalSeparator)
        func with(_ shown: String, _ one: String, _ many: String) -> String {
            shown + " " + (shown == "1" ? one : many)
        }
        switch format {
        case .percent(let of):
            guard abs(of) > 0, of.isFinite else { return L("no value") }
            return number(value / of * 100, digits: 0, trim: false, separator: sep) + " " + L("percent")
        case .seconds: return with(number(value, digits: 1, trim: true, separator: sep), L("second"), L("seconds"))
        case .minutes: return with(number(value, digits: 1, trim: true, separator: sep), L("minute"), L("minutes"))
        case .hertz: return number(value, digits: 2, trim: true, separator: sep) + " " + L("hertz")
        case .points: return with(number(value, digits: 0, trim: false, separator: sep), L("point"), L("points"))
        case .nits: return with(number(value, digits: 0, trim: false, separator: sep), L("nit"), L("nits"))
        case .kelvin: return number(value, digits: 0, trim: false, separator: sep) + " " + L("kelvin")
        case .plain(let digits): return number(value, digits: clampDigits(digits), trim: false, separator: sep)
        }
    }

    /// The widest formatted value of the range, by character count (the field sizes itself with monospaced
    /// digits, so the longest text is the widest).
    package static func widestText(range: ClosedRange<Double>, step: Double?, format: ValueFormat) -> String {
        let lo = range.lowerBound, hi = range.upperBound
        var candidates = [lo, hi]
        if let s = validStep(step) {
            candidates.append(clampSnap(lo + s, range: range, step: s))
            candidates.append(clampSnap(hi - s, range: range, step: s))
        } else {
            switch format {
            case .seconds, .minutes, .hertz: candidates.append(max(lo, hi - 0.55))
            default: break
            }
        }
        var best = ""
        for c in candidates {
            let text = self.format(c, format, decimalSeparator: ".")
            if text.count > best.count { best = text }
        }
        return best
    }

    /// Accepts "70", "70 %", "70%", "70 percent", "1,5 s" (separator ","), "15 min", "60Hz". A "." is accepted as
    /// the decimal point whatever the separator. Returns the stored value (percent is scaled back by `of`), not
    /// clamped; nil for anything else (other units, grouping, exponents, more than 15 digits).
    package static func parse(_ text: String, _ format: ValueFormat, decimalSeparator: String) -> Double? {
        guard text.count <= maxInputLength else { return nil }
        var s = trimmed(text).lowercased()
        guard !s.isEmpty else { return nil }
        let suffixes = unitSuffixes(format)
        for suffix in suffixes where s.hasSuffix(suffix) {
            s = trimmed(String(s.dropLast(suffix.count)))
            break
        }
        guard let n = parseNumber(s, separator: separator(decimalSeparator)) else { return nil }
        switch format {
        case .percent(let of):
            guard of.isFinite else { return nil }
            let v = n / 100 * of
            return v.isFinite ? v : nil
        default:
            return n
        }
    }

    // MARK: Helpers

    private static func validStep(_ step: Double?) -> Double? {
        guard let s = step, s.isFinite, s > 0 else { return nil }
        return s
    }

    private static func clampDigits(_ d: Int) -> Int { min(6, max(0, d)) }

    private static func pow10(_ n: Int) -> Double {
        var r = 1.0
        for _ in 0..<max(0, n) { r *= 10 }
        return r
    }

    /// Decimals needed to write `x` exactly (≤ 12): 0.25 → 2, 5 → 0.
    private static func decimalPlaces(_ x: Double) -> Int {
        guard x.isFinite else { return 0 }
        var scaled = abs(x)
        for places in 0...12 {
            if abs(scaled - scaled.rounded()) < 1e-9 * max(1, scaled) { return places }
            scaled *= 10
        }
        return 12
    }

    private static func separator(_ s: String) -> String { s.isEmpty ? "." : s }

    /// `digits` decimals, rounded half away from zero; `trim` drops trailing zeros (and the separator).
    private static func number(_ value: Double, digits: Int, trim: Bool, separator: String) -> String {
        let scale = pow10(digits)
        var magnitude = (abs(value) * scale).rounded()
        if !magnitude.isFinite || magnitude >= 9e15 { magnitude = 9e15 - 1 }
        let total = Int64(magnitude)
        let factor = Int64(scale)
        let whole = total / factor
        var fraction = total % factor
        var text = String(whole)
        if digits > 0 {
            var fractionDigits = digits
            if trim {
                while fractionDigits > 0 && fraction % 10 == 0 {
                    fraction /= 10
                    fractionDigits -= 1
                }
            }
            if fractionDigits > 0 {
                var f = String(fraction)
                while f.count < fractionDigits { f = "0" + f }
                text += separator + f
            }
        }
        return (value < 0 && total != 0 ? "-" : "") + text
    }

    fileprivate static func trimmed(_ s: String) -> String {
        func isSpace(_ u: Unicode.Scalar) -> Bool {
            u == " " || u == "\t" || u == "\n" || u == "\r" || u.value == 0xA0 || u.value == 0x202F || u.value == 0x2009
        }
        let scalars = Array(s.unicodeScalars)
        var a = 0, b = scalars.count
        while a < b && isSpace(scalars[a]) { a += 1 }
        while b > a && isSpace(scalars[b - 1]) { b -= 1 }
        var out = String.UnicodeScalarView()
        out.append(contentsOf: scalars[a..<b])
        return String(out)
    }

    /// Longest first, lowercase.
    private static func unitSuffixes(_ format: ValueFormat) -> [String] {
        switch format {
        case .percent: return ["percent", "%"]
        case .seconds: return ["seconds", "second", "secs", "sec", "s"]
        case .minutes: return ["minutes", "minute", "mins", "min", "m"]
        case .hertz: return ["hertz", "hz"]
        case .points: return ["points", "point", "pts", "pt"]
        case .nits: return ["nits", "nit", "cd/m²", "cd/m2"]
        case .kelvin: return ["kelvin", "k"]
        case .plain: return []
        }
    }

    /// Optional sign, digits, at most one decimal point ("." or `separator`), digits. Nothing else.
    fileprivate static func parseNumber(_ s: String, separator: String) -> Double? {
        var scalars = Array(s.unicodeScalars)
        guard !scalars.isEmpty else { return nil }
        var negative = false
        if let first = scalars.first, first == "-" || first == "+" || first.value == 0x2212 {
            negative = first != "+"
            scalars.removeFirst()
        }
        let sepScalars = Array(separator.unicodeScalars)
        var whole: [UInt8] = []
        var fraction: [UInt8] = []
        var inFraction = false
        var i = 0
        while i < scalars.count {
            let u = scalars[i]
            if u.value >= 48 && u.value <= 57 {
                if inFraction { fraction.append(UInt8(u.value - 48)) } else { whole.append(UInt8(u.value - 48)) }
                i += 1
                continue
            }
            let matchesSeparator = !sepScalars.isEmpty && i + sepScalars.count <= scalars.count
                && Array(scalars[i..<(i + sepScalars.count)]) == sepScalars
            if !inFraction && (u == "." || matchesSeparator) {
                inFraction = true
                i += (u == "." && !matchesSeparator) ? 1 : sepScalars.count
                continue
            }
            return nil
        }
        guard !whole.isEmpty || !fraction.isEmpty, whole.count + fraction.count <= maxDigits else { return nil }
        var v = 0.0
        for d in whole { v = v * 10 + Double(d) }
        var scale = 1.0
        for d in fraction {
            scale /= 10
            v += Double(d) * scale
        }
        if !fraction.isEmpty {
            // Remove the binary noise of the sum (0.1 + 0.2): round to the typed decimals.
            let p = pow10(fraction.count)
            v = (v * p).rounded() / p
        }
        return negative ? -v : v
    }
}

/// A discrete slider whose positions have names ("1512 × 982", "Default", "Native"); values are indices. Used by
/// `SliderSetting(…, labels:)` and `NumberField(…, labels:)` in place of the format's numbers.
package enum SliderLabels {
    /// The label of the nearest index (clamped); "" without labels.
    package static func text(_ value: Double, _ labels: [String]) -> String {
        label(at: value, labels) ?? ""
    }

    /// VoiceOver text: "1512 by 982".
    package static func spoken(_ value: Double, _ labels: [String]) -> String {
        text(value, labels).replacingOccurrences(of: " × ", with: " " + L("by") + " ")
            .replacingOccurrences(of: "×", with: " " + L("by") + " ")
    }

    /// The longest label (field width).
    package static func widest(_ labels: [String]) -> String {
        labels.max { $0.count < $1.count } ?? ""
    }

    /// Exact label (case, spaces and "×"/"x" ignored), else the nearest "W × H" label to a typed size, else the
    /// nearest numeric label to a typed number ("110" or "110%" → "100%"; PLAN §4.1: a discrete slider snaps a typed
    /// value to the nearest position).
    package static func parse(_ text: String, _ labels: [String]) -> Double? {
        guard text.count <= SliderMath.maxInputLength else { return nil }
        let s = SliderMath.trimmed(text).lowercased()
        guard !s.isEmpty else { return nil }
        return parseLabel(s, labels)
    }

    private static func label(at value: Double, _ labels: [String]) -> String? {
        guard !labels.isEmpty, value.isFinite else { return nil }
        let i = Int(min(Double(labels.count - 1), max(0, value.rounded())))
        return labels[i]
    }

    /// Exact label (spaces and "×"/"x" ignored), else the nearest "W × H" label to a typed size, else (labels that
    /// are numbers such as "80%", resolution's percent mode) the label nearest to a typed number with or without
    /// "%". PLAN §4.1: a discrete slider snaps a typed value to the nearest position.
    private static func parseLabel(_ s: String, _ labels: [String]) -> Double? {
        func normalized(_ t: String) -> String {
            var out = ""
            for u in t.lowercased().unicodeScalars where u != " " && u.value != 0xA0 && u.value != 0x202F {
                out.unicodeScalars.append(u == "×" || u == "*" ? "x" : u)
            }
            return out
        }
        let typed = normalized(s)
        if let i = labels.firstIndex(where: { normalized($0) == typed }) { return Double(i) }
        var best: (index: Int, distance: Double)?
        if let size = pair(typed) {
            for (i, label) in labels.enumerated() {
                guard let p = pair(normalized(label)) else { continue }
                let d = (p.0 - size.0) * (p.0 - size.0) + (p.1 - size.1) * (p.1 - size.1)
                if let b = best, d >= b.distance { continue }
                best = (i, d)
            }
        } else if let n = percentNumber(typed), n.isFinite {
            for (i, label) in labels.enumerated() {
                guard let v = percentNumber(normalized(label)), v.isFinite else { continue }
                let d = abs(v - n)
                if let b = best, d >= b.distance { continue }
                best = (i, d)
            }
        }
        return best.map { Double($0.index) }
    }

    /// "1512x982" (normalized; a trailing " HiDPI · 60 Hz" on a label ignored) → (1512, 982).
    private static func pair(_ s: String) -> (Double, Double)? {
        let parts = s.split(separator: "x", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let w = SliderMath.parseNumber(String(parts[0]), separator: "."),
              let h = SliderMath.parseNumber(leadingNumber(String(parts[1])), separator: ".") else { return nil }
        return (w, h)
    }

    /// The digits (and one ".") a string starts with: "982hidpi·60hz" → "982".
    private static func leadingNumber(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var dot = false
        for u in s.unicodeScalars {
            if u.value >= 48 && u.value <= 57 { out.append(u); continue }
            if u == ".", !dot { dot = true; out.append(u); continue }
            break
        }
        return String(out)
    }

    /// "110%", "110" or "99,5" (normalized) → the number; nil for anything else.
    private static func percentNumber(_ s: String) -> Double? {
        let body = s.hasSuffix("%") ? String(s.dropLast()) : s
        guard !body.isEmpty else { return nil }
        // A decimal comma ("99,5") reads as a point (percent labels never group digits).
        return SliderMath.parseNumber(body.replacingOccurrences(of: ",", with: "."), separator: ".")
    }
}

/// The edit state of a typed value field (`NumberField`, the field of `SliderSetting` and `StepperSetting`).
///
/// The field always follows the value it shows unless the user has typed something since it last synced: then the
/// typed text stays until Return, Esc, an arrow key, focus loss or the row's own control. A commit writes only text
/// the user typed (dirty) and never writes stale text back over a value that changed elsewhere.
///
/// Two kinds of outside change: a change made elsewhere (brightness keys, a hardware read-back, the menu's slider)
/// `sync`s and keeps text being typed; the row's own slider, stepper or Reset is the user's newer intent, so it
/// `discardTyping`s (review round 2 ui F1): typed-but-not-Returned text is dropped and never written on blur.
package struct TypedFieldState: Equatable, Sendable {
    /// What the field shows.
    package private(set) var text: String
    /// The text last synced from the value (what `text` was before the user typed).
    package private(set) var synced: String
    /// Changes with every write (`commit` → `.write`, `nudge`). The field settles when it changes, in the render that
    /// follows the write, so it reads the binding after the write instead of a getter captured when it committed
    /// (review round 3 ui F3).
    package private(set) var settleTick: Int = 0

    package init(display: String = "") {
        text = display
        synced = display
    }

    /// The user typed since the last sync (and the text differs from what was shown).
    package var isDirty: Bool { text != synced }

    /// The value changed elsewhere, or the field appeared: follow it unless the user is typing. Focus doesn't matter.
    package mutating func sync(display: String) {
        guard !isDirty else { return }
        text = display
        synced = display
    }

    /// The user typed (the text binding's setter; programmatic changes never come through here).
    package mutating func edit(_ newText: String) {
        text = newText
    }

    /// Esc, or after a commit: show the value again and drop the typed text.
    package mutating func revert(display: String) {
        text = display
        synced = display
    }

    /// The row's own slider drag or click, stepper arrow or Reset set the value: drop any typed-but-not-Returned text
    /// and show the value, so focus leaving later writes nothing over it.
    package mutating func discardTyping(display: String) {
        revert(display: display)
    }

    /// After a write (`settleTick` changed), with the display of the render that follows it: show what the binding
    /// really stored. A value clamped back to the old one (e.g. a custom nits minimum already at its cap) doesn't
    /// change the display, so without this the field would keep the typed number (review round 2 ui N2). Text typed
    /// in between is kept (`sync`). A store that publishes later re-renders with a new display, which `sync`s.
    package mutating func settle(display: String) {
        sync(display: display)
    }

    /// What Return or focus loss does.
    package enum Commit: Equatable, Sendable {
        /// Nothing typed: no write (the field re-synced to the current value).
        case none
        /// Typed text that doesn't parse: beep (the field reverted).
        case invalid
        /// Write this value (already parsed, clamped and snapped by `parse`).
        case write(Double)
    }

    /// Commits typed text. `parse` turns text into the value to write (clamped and snapped) or nil when invalid;
    /// `format` shows a written value. Text the user didn't type is never parsed or written.
    package mutating func commit(display: String, parse: (String) -> Double?, format: (Double) -> String) -> Commit {
        guard isDirty else {
            revert(display: display)
            return .none
        }
        guard let v = parse(text) else {
            revert(display: display)
            return .invalid
        }
        revert(display: format(v))
        settleTick &+= 1
        return .write(v)
    }

    /// ↑/↓: steps from the typed number when there is one, else from the value; the field then shows the result.
    package mutating func nudge(value: Double, parse: (String) -> Double?, step: (Double) -> Double,
                                format: (Double) -> String) -> Double {
        let base = (isDirty ? parse(text) : nil) ?? value
        let v = step(base)
        revert(display: format(v))
        settleTick &+= 1
        return v
    }
}

/// Which typed field may still hold text that hasn't been written (review round 3 ui F1/F2). A button that reads
/// values (a sheet's Done, the virtual display editor's "+") commits that field first: a click doesn't take focus
/// from the field, so its blur commit would come after the button's action. Fields register when they gain focus
/// (and again as they change, so the commit is always the latest one); a field that loses focus resigns only its
/// own registration, because the next field's focus can arrive first.
package struct FocusedCommitSlot<Owner: Equatable, Commit> {
    package private(set) var owner: Owner?
    private var commit: Commit?

    package init() {}

    package mutating func register(_ id: Owner, _ commit: Commit) {
        owner = id
        self.commit = commit
    }

    /// The field `id` lost focus or went away.
    package mutating func resign(_ id: Owner) {
        guard owner == id else { return }
        owner = nil
        commit = nil
    }

    /// The pending commit, once: the slot is empty afterwards.
    package mutating func take() -> Commit? {
        defer {
            owner = nil
            commit = nil
        }
        return commit
    }
}
