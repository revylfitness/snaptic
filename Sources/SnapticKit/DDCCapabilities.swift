import Foundation

/// Parsed MCCS capabilities string, e.g.
/// `(prot(monitor)type(lcd)model(U2723QE)cmds(01 02 03 0C E3 F3)vcp(10 12 14(05 08 0B) 60(0F 11 12) D6(01 04 05))mccs_ver(2.1))`.
/// Parsing is bounded (PLAN §4.10(4)): ≤ 4096 bytes, nesting ≤ 8, ≤ 256 codes, ≤ 64 values per code.
package struct DDCCapabilities: Codable, Equatable, Sendable {
    /// Supported VCP codes; for non-continuous codes, the allowed values (empty = any).
    package var vcp: [UInt8: [UInt16]]
    package var model: String?
    package var type: String?
    package var mccsVersion: String?
    package var commands: [UInt8]

    package init() {
        vcp = [:]
        commands = []
    }

    package func supports(_ code: UInt8) -> Bool { vcp[code] != nil }

    /// Listed values for a code, or nil when the code isn't listed or lists none.
    package func values(for code: UInt8) -> [UInt16]? {
        guard let v = vcp[code], !v.isEmpty else { return nil }
        return v
    }

    /// Input sources (VCP 0x60) the display lists.
    package var inputSources: [UInt16] { vcp[0x60] ?? [] }

    package static let maxInputBytes = 4096
    package static let maxNesting = 8
    package static let maxCodes = 256
    package static let maxValuesPerCode = 64
    package static let maxTextLength = 64

    private enum CodingKeys: String, CodingKey { case vcp, model, type, mccsVersion, commands }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vcp = c.lossy(.vcp, [UInt8: [UInt16]]())
        model = c.lossy(.model, nil as String?)
        type = c.lossy(.type, nil as String?)
        mccsVersion = c.lossy(.mccsVersion, nil as String?)
        commands = c.lossy(.commands, [UInt8]())
    }

    /// Parses a capabilities string. Returns nil when the input is malformed beyond use
    /// (unbalanced or too deeply nested parentheses, no groups at all).
    package static func parse(_ text: String) -> DDCCapabilities? {
        let bytes = Array(text.utf8.prefix(maxInputBytes))
        guard let groups = topLevelGroups(bytes) else { return nil }
        guard !groups.isEmpty else { return nil }
        var caps = DDCCapabilities()
        for (name, content) in groups {
            switch name.lowercased() {
            case "vcp":
                guard let parsed = parseVCPList(content) else { return nil }
                caps.vcp = parsed
            case "model":
                caps.model = cleanText(content)
            case "type":
                caps.type = cleanText(content)
            case "mccs_ver":
                caps.mccsVersion = cleanText(content)
            case "cmds":
                caps.commands = Array(hexTokens(content).compactMap { $0 <= 0xFF ? UInt8($0) : nil }.prefix(maxCodes))
            default:
                continue
            }
        }
        return caps
    }

    // MARK: Parsing helpers

    private static func isNameByte(_ b: UInt8) -> Bool {
        (0x30...0x39).contains(b) || (0x41...0x5A).contains(b) || (0x61...0x7A).contains(b) || b == 0x5F
    }

    private static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D }

    /// Index of the ")" matching the "(" at `open`, or nil (unbalanced or nested > maxNesting).
    private static func matchingParen(_ bytes: [UInt8], open: Int, baseDepth: Int) -> Int? {
        var depth = 0
        var i = open
        while i < bytes.count {
            switch bytes[i] {
            case 0x28:
                depth += 1
                if depth + baseDepth > maxNesting { return nil }
            case 0x29:
                depth -= 1
                if depth == 0 { return i }
            default:
                break
            }
            i += 1
        }
        return nil
    }

    /// `name(content)` groups at the top level, after stripping one optional outer pair.
    private static func topLevelGroups(_ input: [UInt8]) -> [(String, [UInt8])]? {
        var bytes = input
        var start = 0
        while start < bytes.count, isSpace(bytes[start]) { start += 1 }
        var baseDepth = 0
        if start < bytes.count, bytes[start] == 0x28 {
            // Outer wrapper: tolerate a missing final ")" (common truncation).
            if let close = matchingParen(bytes, open: start, baseDepth: 0) {
                bytes = Array(bytes[(start + 1)..<close])
            } else {
                bytes = Array(bytes[(start + 1)...])
            }
            baseDepth = 1
        }
        var groups: [(String, [UInt8])] = []
        var i = 0
        while i < bytes.count {
            guard isNameByte(bytes[i]) else { i += 1; continue }
            var j = i
            while j < bytes.count, isNameByte(bytes[j]) { j += 1 }
            let name = String(decoding: bytes[i..<j], as: UTF8.self)
            var k = j
            while k < bytes.count, isSpace(bytes[k]) { k += 1 }
            guard k < bytes.count, bytes[k] == 0x28 else { i = j; continue }
            guard let close = matchingParen(bytes, open: k, baseDepth: baseDepth) else { return nil }
            groups.append((name, Array(bytes[(k + 1)..<close])))
            i = close + 1
            if groups.count > 64 { break }
        }
        return groups
    }

    /// Hex tokens anywhere in `bytes` (ignores parentheses), each ≤ 4 digits.
    private static func hexTokens(_ bytes: [UInt8]) -> [UInt32] {
        var result: [UInt32] = []
        var current: UInt32 = 0
        var digits = 0
        func flush() {
            if digits > 0 && digits <= 4 { result.append(current) }
            current = 0
            digits = 0
        }
        for b in bytes {
            if let v = hexValue(b) {
                digits += 1
                if digits <= 4 { current = current << 4 | UInt32(v) }
            } else {
                flush()
            }
        }
        flush()
        return result
    }

    private static func hexValue(_ b: UInt8) -> UInt8? {
        switch b {
        case 0x30...0x39: return b - 0x30
        case 0x41...0x46: return b - 0x41 + 10
        case 0x61...0x66: return b - 0x61 + 10
        default: return nil
        }
    }

    /// `10 12 14(05 08 0B) 60(0F 11)` → codes with optional value lists.
    private static func parseVCPList(_ bytes: [UInt8]) -> [UInt8: [UInt16]]? {
        var result: [UInt8: [UInt16]] = [:]
        var i = 0
        var lastCode: UInt8?
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x28 {
                // Values for the preceding code (nested groups are flattened).
                guard let close = matchingParen(bytes, open: i, baseDepth: 2) else { return nil }
                if let code = lastCode {
                    let values = hexTokens(Array(bytes[(i + 1)..<close]))
                        .compactMap { $0 <= 0xFFFF ? UInt16($0) : nil }
                    var unique: [UInt16] = []
                    for v in values where !unique.contains(v) {
                        unique.append(v)
                        if unique.count >= maxValuesPerCode { break }
                    }
                    result[code] = unique
                }
                lastCode = nil
                i = close + 1
                continue
            }
            if b == 0x29 { i += 1; continue }
            if hexValue(b) != nil {
                var j = i
                var value: UInt32 = 0
                while j < bytes.count, let v = hexValue(bytes[j]) {
                    if j - i < 4 { value = value << 4 | UInt32(v) }
                    j += 1
                }
                if j - i <= 2, value <= 0xFF {
                    let code = UInt8(value)
                    if result[code] == nil {
                        if result.count >= maxCodes { return result }
                        result[code] = []
                    }
                    lastCode = code
                } else {
                    lastCode = nil
                }
                i = j
                continue
            }
            if !isSpace(b) { lastCode = nil }
            i += 1
        }
        return result
    }

    private static func cleanText(_ bytes: [UInt8]) -> String? {
        let printable = bytes.filter { $0 >= 0x20 && $0 < 0x7F && $0 != 0x28 && $0 != 0x29 }
        let text = String(decoding: printable.prefix(maxTextLength), as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}
