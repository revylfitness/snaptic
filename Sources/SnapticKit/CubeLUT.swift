import Foundation

/// Why a `.cube` file was rejected. Messages are user-facing.
package enum CubeLUTError: Error, Equatable, Sendable {
    case pathTooLong
    case unreadable
    case notRegularFile
    case fileTooLarge
    case notText
    case lineTooLong(Int)
    case malformedLine(Int)
    case missingSize
    case unsupportedSize(Int)
    case oneDimensional
    case duplicateKeyword(Int)
    case keywordAfterData(Int)
    case dataBeforeSize(Int)
    case valueOutOfRange(Int)
    case invalidDomain
    case wrongEntryCount(expected: Int, found: Int)

    package var message: String {
        switch self {
        case .pathTooLong: return L("The file path is too long.")
        case .unreadable: return L("The file couldn’t be opened.")
        case .notRegularFile: return L("Choose a regular file (not a folder, alias, or device).")
        case .fileTooLarge: return L("The file is too large for a LUT.")
        case .notText: return L("This isn’t a text .cube file.")
        case .lineTooLong(let n): return L("Line \(n) is too long.")
        case .malformedLine(let n): return L("Line \(n) couldn’t be read.")
        case .missingSize: return L("The file has no LUT_3D_SIZE line.")
        case .unsupportedSize(let n): return L("LUT size \(n) isn’t supported (2–128).")
        case .oneDimensional: return L("1D and mixed LUTs aren’t supported; use a 3D LUT.")
        case .duplicateKeyword(let n): return L("Line \(n) repeats a keyword.")
        case .keywordAfterData(let n): return L("Line \(n) has a keyword after the table started.")
        case .dataBeforeSize(let n): return L("Line \(n) has table data before LUT_3D_SIZE.")
        case .valueOutOfRange(let n): return L("Line \(n) has a value out of range.")
        case .invalidDomain: return L("DOMAIN_MIN must be below DOMAIN_MAX for every channel.")
        case .wrongEntryCount(let e, let f): return L("Expected \(e) table entries, found \(f).")
        }
    }
}

/// A 3D color lookup table from an Adobe/Resolve `.cube` file (PLAN §10, §4.10(4,6)).
/// Parsing is bounded: file size, line length, table size and value range are all
/// capped, and every malformed input is an error, never a trap.
package struct CubeLUT: Equatable, Sendable {
    package static let minSize = 2
    package static let maxSize = 128
    /// 128³ entries at about 40 bytes per line, plus headroom for comments.
    package static let maxFileBytes = 96 * 1024 * 1024
    package static let maxLineBytes = 1024
    package static let maxPathBytes = 1024
    /// CoreImage's color cube is only guaranteed up to 64; larger tables are resampled.
    package static let maxRenderSize = 64
    /// Values beyond this are rejected (HDR LUTs stay far below it).
    package static let valueLimit: Double = 1000

    package private(set) var title: String
    package private(set) var size: Int
    package private(set) var domainMin: [Double]
    package private(set) var domainMax: [Double]
    /// RGB triples; red changes fastest, then green, then blue (size³ × 3 floats).
    package private(set) var values: [Float]

    package init(title: String = "", size: Int, domainMin: [Double] = [0, 0, 0], domainMax: [Double] = [1, 1, 1],
                 values: [Float]) throws {
        guard size >= Self.minSize, size <= Self.maxSize else { throw CubeLUTError.unsupportedSize(size) }
        guard domainMin.count == 3, domainMax.count == 3,
              (0..<3).allSatisfy({ domainMin[$0].isFinite && domainMax[$0].isFinite && domainMin[$0] < domainMax[$0]
                  && abs(domainMin[$0]) <= Self.valueLimit && abs(domainMax[$0]) <= Self.valueLimit })
        else { throw CubeLUTError.invalidDomain }
        let expected = size * size * size * 3
        guard values.count == expected else {
            throw CubeLUTError.wrongEntryCount(expected: size * size * size, found: values.count / 3)
        }
        guard values.allSatisfy({ $0.isFinite && abs(Double($0)) <= Self.valueLimit }) else {
            throw CubeLUTError.valueOutOfRange(0)
        }
        self.title = TextSanitizer.clean(title, maxScalars: 64)
        self.size = size
        self.domainMin = domainMin
        self.domainMax = domainMax
        self.values = values
    }

    /// The table that maps every color to itself.
    package static func identity(size: Int) -> CubeLUT? {
        guard size >= minSize, size <= maxSize else { return nil }
        var values: [Float] = []
        values.reserveCapacity(size * size * size * 3)
        let step = 1 / Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    values.append(Float(r) * step)
                    values.append(Float(g) * step)
                    values.append(Float(b) * step)
                }
            }
        }
        return try? CubeLUT(title: "Identity", size: size, values: values)
    }

    // MARK: Lookup

    package func entry(r: Int, g: Int, b: Int) -> (Double, Double, Double) {
        let n = size
        let rr = Swift.max(0, Swift.min(n - 1, r)), gg = Swift.max(0, Swift.min(n - 1, g)), bb = Swift.max(0, Swift.min(n - 1, b))
        let i = ((bb * n + gg) * n + rr) * 3
        return (Double(values[i]), Double(values[i + 1]), Double(values[i + 2]))
    }

    /// Trilinear lookup. Inputs are in the LUT's domain and clamped to it.
    package func sample(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let n = Double(size - 1)
        func coord(_ v: Double, _ c: Int) -> (Int, Double) {
            let t = (v - domainMin[c]) / (domainMax[c] - domainMin[c])
            let x = (t.isFinite ? Swift.max(0, Swift.min(1, t)) : 0) * n
            let i = Swift.min(Int(x), size - 2)
            return (i, x - Double(i))
        }
        let (ri, rf) = coord(r, 0), (gi, gf) = coord(g, 1), (bi, bf) = coord(b, 2)
        var out = (0.0, 0.0, 0.0)
        for db in 0...1 {
            for dg in 0...1 {
                for dr in 0...1 {
                    let w = (dr == 1 ? rf : 1 - rf) * (dg == 1 ? gf : 1 - gf) * (db == 1 ? bf : 1 - bf)
                    guard w > 0 else { continue }
                    let e = entry(r: ri + dr, g: gi + dg, b: bi + db)
                    out.0 += e.0 * w
                    out.1 += e.1 * w
                    out.2 += e.2 * w
                }
            }
        }
        return out
    }

    /// The same mapping on a grid of `newSize` points per axis (trilinear).
    package func resampled(to newSize: Int) -> CubeLUT? {
        guard newSize >= Self.minSize, newSize <= Self.maxSize else { return nil }
        if newSize == size { return self }
        var out: [Float] = []
        out.reserveCapacity(newSize * newSize * newSize * 3)
        let step = 1 / Double(newSize - 1)
        func at(_ c: Int, _ i: Int) -> Double { domainMin[c] + (domainMax[c] - domainMin[c]) * Double(i) * step }
        for b in 0..<newSize {
            for g in 0..<newSize {
                for r in 0..<newSize {
                    let v = sample(at(0, r), at(1, g), at(2, b))
                    out.append(Float(v.0))
                    out.append(Float(v.1))
                    out.append(Float(v.2))
                }
            }
        }
        return try? CubeLUT(title: title, size: newSize, domainMin: domainMin, domainMax: domainMax, values: out)
    }

    /// A table no larger than `maxRenderSize`, for CoreImage.
    package var renderable: CubeLUT {
        size <= Self.maxRenderSize ? self : (resampled(to: Self.maxRenderSize) ?? self)
    }

    /// Float32 RGBA (alpha 1) in CoreImage color-cube order: size³ × 4 floats.
    package func rgbaFloatData() -> Data {
        var rgba = [Float](repeating: 1, count: size * size * size * 4)
        var j = 0
        var i = 0
        while i < values.count {
            rgba[j] = values[i]
            rgba[j + 1] = values[i + 1]
            rgba[j + 2] = values[i + 2]
            i += 3
            j += 4
        }
        return rgba.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Per-channel scale and bias that map the domain onto 0…1 (for a color matrix
    /// in front of the cube).
    package var inputScale: [Double] { (0..<3).map { 1 / (domainMax[$0] - domainMin[$0]) } }
    package var inputBias: [Double] { (0..<3).map { -domainMin[$0] / (domainMax[$0] - domainMin[$0]) } }
    package var hasUnitDomain: Bool { domainMin == [0, 0, 0] && domainMax == [1, 1, 1] }

    // MARK: Parsing

    package static func parse(_ data: Data) throws -> CubeLUT {
        guard data.count <= maxFileBytes else { throw CubeLUTError.fileTooLarge }
        return try data.withUnsafeBytes { raw -> CubeLUT in
            try parse(bytes: raw.bindMemory(to: UInt8.self))
        }
    }

    package static func parse(text: String) throws -> CubeLUT {
        try parse(Data(text.utf8))
    }

    private static func parse(bytes: UnsafeBufferPointer<UInt8>) throws -> CubeLUT {
        var state = CubeParseState()
        let count = bytes.count
        var lineStart = 0
        var lineNumber = 0
        // A UTF-8 byte-order mark is allowed at the very start.
        if count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { lineStart = 3 }
        while lineStart < count {
            lineNumber += 1
            var lineEnd = lineStart
            while lineEnd < count, bytes[lineEnd] != 0x0A {
                lineEnd += 1
                if lineEnd - lineStart > maxLineBytes { throw CubeLUTError.lineTooLong(lineNumber) }
            }
            try state.consume(bytes, lineStart, lineEnd, lineNumber)
            lineStart = lineEnd + 1
        }
        return try state.finish()
    }

    /// Parses a decimal number (`[+-]digits[.digits][e[+-]digits]`) from `b[lo..<hi]`.
    /// Bounded: at most 64 bytes, exponent within ±400. Exposed for tests.
    package static func parseNumber(_ b: UnsafeBufferPointer<UInt8>, _ lo: Int, _ hi: Int) -> Double? {
        guard hi > lo, hi - lo <= 64, lo >= 0, hi <= b.count else { return nil }
        var i = lo
        var negative = false
        if b[i] == 0x2B || b[i] == 0x2D {
            negative = b[i] == 0x2D
            i += 1
        }
        var mantissa: UInt64 = 0
        var significant = 0
        var exp10 = 0
        var sawDigit = false
        while i < hi, b[i] >= 0x30, b[i] <= 0x39 {
            sawDigit = true
            if significant < 19 {
                mantissa = mantissa * 10 + UInt64(b[i] - 0x30)
                if mantissa != 0 { significant += 1 }
            } else {
                exp10 += 1
            }
            i += 1
        }
        if i < hi, b[i] == 0x2E {
            i += 1
            while i < hi, b[i] >= 0x30, b[i] <= 0x39 {
                sawDigit = true
                if significant < 19 {
                    mantissa = mantissa * 10 + UInt64(b[i] - 0x30)
                    if mantissa != 0 { significant += 1 }
                    exp10 -= 1
                }
                i += 1
            }
        }
        guard sawDigit else { return nil }
        if i < hi, b[i] == 0x65 || b[i] == 0x45 {
            i += 1
            var expNegative = false
            if i < hi, b[i] == 0x2B || b[i] == 0x2D {
                expNegative = b[i] == 0x2D
                i += 1
            }
            var e = 0
            var sawExp = false
            while i < hi, b[i] >= 0x30, b[i] <= 0x39 {
                sawExp = true
                if e < 100_000 { e = e * 10 + Int(b[i] - 0x30) }
                i += 1
            }
            guard sawExp else { return nil }
            exp10 += expNegative ? -e : e
        }
        guard i == hi else { return nil }
        var value = Double(mantissa)
        if mantissa != 0, exp10 != 0 {
            guard exp10 > -400, exp10 < 400 else { return nil }
            if exp10 < 0, exp10 >= -22 {
                value /= exactPowerOfTen[-exp10]
            } else if exp10 > 0, exp10 <= 22 {
                value *= exactPowerOfTen[exp10]
            } else {
                value *= pow(10, Double(exp10))
            }
        }
        return negative ? -value : value
    }

    private static let exactPowerOfTen: [Double] = (0...22).map { k in
        var v = 1.0
        for _ in 0..<k { v *= 10 }
        return v
    }

    // MARK: Picked files (PLAN §4.10(6))

    /// Reads a user-picked file: `O_NONBLOCK|O_NOFOLLOW`, regular files only, capped
    /// size. Blocking I/O: call it off the main thread.
    package static func readPickedFile(atPath path: String, maxBytes: Int = maxFileBytes) throws -> Data {
        guard !path.isEmpty, path.utf8.count <= maxPathBytes, !path.utf8.contains(0) else {
            throw CubeLUTError.pathTooLong
        }
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CubeLUTError.unreadable }
        defer { _ = close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw CubeLUTError.unreadable }
        guard (UInt32(info.st_mode) & 0o170000) == 0o100000 else { throw CubeLUTError.notRegularFile }
        guard info.st_size >= 0, Int64(info.st_size) <= Int64(maxBytes) else { throw CubeLUTError.fileTooLarge }
        var result = Data()
        result.reserveCapacity(Int(info.st_size))
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = chunk.withUnsafeMutableBytes { buf -> Int in
                read(fd, buf.baseAddress, buf.count)
            }
            if n < 0 {
                if errno == EINTR { continue }
                throw CubeLUTError.unreadable
            }
            if n == 0 { break }
            // The file may grow while we read it; the cap still holds.
            guard result.count + n <= maxBytes else { throw CubeLUTError.fileTooLarge }
            result.append(contentsOf: chunk[0..<n])
        }
        return result
    }
}

/// Line-by-line `.cube` parser state.
private struct CubeParseState {
    var title = ""
    var size: Int?
    var domainMin: [Double] = [0, 0, 0]
    var domainMax: [Double] = [1, 1, 1]
    var seen = Set<String>()
    var values: [Float] = []
    var expected = 0
    var unknownKeywords = 0

    static func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0B || c == 0x0C }

    mutating func consume(_ b: UnsafeBufferPointer<UInt8>, _ lo: Int, _ hi: Int, _ line: Int) throws {
        // Binary files: any control byte other than whitespace.
        var i = lo
        while i < hi {
            let c = b[i]
            if c < 0x20, !Self.isSpace(c) { throw CubeLUTError.notText }
            if c == 0x7F { throw CubeLUTError.notText }
            i += 1
        }
        // Tokens up to a comment.
        var tokens: [(Int, Int)] = []
        i = lo
        while i < hi {
            while i < hi, Self.isSpace(b[i]) { i += 1 }
            guard i < hi, b[i] != 0x23 else { break }
            let start = i
            while i < hi, !Self.isSpace(b[i]), b[i] != 0x23 { i += 1 }
            tokens.append((start, i))
            if tokens.count > 8 { throw CubeLUTError.malformedLine(line) }
            if tokens.count == 1, isKeyword(b, start, i, Self.titleWord) {
                try handleTitle(b, i, hi, line)
                return
            }
        }
        guard let first = tokens.first else { return }
        let c = b[first.0]
        let isLetter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
        if isLetter {
            try handleKeyword(b, tokens, line)
        } else {
            try handleData(b, tokens, line)
        }
    }

    static let titleWord: [UInt8] = Array("TITLE".utf8)

    func isKeyword(_ b: UnsafeBufferPointer<UInt8>, _ lo: Int, _ hi: Int, _ w: [UInt8]) -> Bool {
        guard hi - lo == w.count else { return false }
        for k in 0..<w.count {
            var c = b[lo + k]
            if c >= 0x61, c <= 0x7A { c -= 0x20 }
            if c != w[k] { return false }
        }
        return true
    }

    mutating func handleTitle(_ b: UnsafeBufferPointer<UInt8>, _ lo: Int, _ hi: Int, _ line: Int) throws {
        guard values.isEmpty else { throw CubeLUTError.keywordAfterData(line) }
        guard seen.insert("TITLE").inserted else { throw CubeLUTError.duplicateKeyword(line) }
        var s = lo
        var e = hi
        while s < e, Self.isSpace(b[s]) { s += 1 }
        while e > s, Self.isSpace(b[e - 1]) { e -= 1 }
        if e - s >= 2, b[s] == 0x22, b[e - 1] == 0x22 {
            s += 1
            e -= 1
        }
        let raw = String(decoding: UnsafeBufferPointer(rebasing: b[s..<e]), as: UTF8.self)
        title = TextSanitizer.clean(raw, maxScalars: 64)
    }

    func numbers(_ b: UnsafeBufferPointer<UInt8>, _ tokens: ArraySlice<(Int, Int)>, _ line: Int) throws -> [Double] {
        var out: [Double] = []
        for t in tokens {
            guard let v = CubeLUT.parseNumber(b, t.0, t.1) else { throw CubeLUTError.malformedLine(line) }
            guard v.isFinite, abs(v) <= CubeLUT.valueLimit else { throw CubeLUTError.valueOutOfRange(line) }
            out.append(v)
        }
        return out
    }

    mutating func handleKeyword(_ b: UnsafeBufferPointer<UInt8>, _ tokens: [(Int, Int)], _ line: Int) throws {
        let (lo, hi) = tokens[0]
        guard values.isEmpty else { throw CubeLUTError.keywordAfterData(line) }
        let name = String(decoding: UnsafeBufferPointer(rebasing: b[lo..<hi]), as: UTF8.self).uppercased()
        let args = tokens.dropFirst()
        switch name {
        case "LUT_1D_SIZE", "LUT_1D_INPUT_RANGE":
            throw CubeLUTError.oneDimensional
        case "LUT_3D_SIZE":
            guard seen.insert(name).inserted else { throw CubeLUTError.duplicateKeyword(line) }
            guard args.count == 1, let first = args.first else { throw CubeLUTError.malformedLine(line) }
            // An integer of at most 4 digits.
            guard first.1 - first.0 <= 4 else { throw CubeLUTError.malformedLine(line) }
            var n = 0
            for k in first.0..<first.1 {
                let c = b[k]
                guard c >= 0x30, c <= 0x39 else { throw CubeLUTError.malformedLine(line) }
                n = n * 10 + Int(c - 0x30)
            }
            guard n >= CubeLUT.minSize, n <= CubeLUT.maxSize else { throw CubeLUTError.unsupportedSize(n) }
            size = n
            expected = n * n * n
            values.reserveCapacity(expected * 3)
        case "DOMAIN_MIN", "DOMAIN_MAX":
            guard seen.insert(name).inserted else { throw CubeLUTError.duplicateKeyword(line) }
            guard args.count == 3 else { throw CubeLUTError.malformedLine(line) }
            let v = try numbers(b, args, line)
            if name == "DOMAIN_MIN" { domainMin = v } else { domainMax = v }
        case "LUT_3D_INPUT_RANGE":
            guard seen.insert(name).inserted else { throw CubeLUTError.duplicateKeyword(line) }
            guard args.count == 2 else { throw CubeLUTError.malformedLine(line) }
            let v = try numbers(b, args, line)
            domainMin = [v[0], v[0], v[0]]
            domainMax = [v[1], v[1], v[1]]
        default:
            // Vendor keywords are ignored, within reason.
            unknownKeywords += 1
            if unknownKeywords > 256 { throw CubeLUTError.malformedLine(line) }
        }
    }

    mutating func handleData(_ b: UnsafeBufferPointer<UInt8>, _ tokens: [(Int, Int)], _ line: Int) throws {
        guard size != nil else { throw CubeLUTError.dataBeforeSize(line) }
        guard tokens.count == 3 else { throw CubeLUTError.malformedLine(line) }
        let found = values.count / 3
        guard found < expected else { throw CubeLUTError.wrongEntryCount(expected: expected, found: found + 1) }
        for t in tokens {
            guard let v = CubeLUT.parseNumber(b, t.0, t.1) else { throw CubeLUTError.malformedLine(line) }
            guard v.isFinite, abs(v) <= CubeLUT.valueLimit else { throw CubeLUTError.valueOutOfRange(line) }
            values.append(Float(v))
        }
    }

    func finish() throws -> CubeLUT {
        guard let size else { throw CubeLUTError.missingSize }
        guard values.count == expected * 3 else {
            throw CubeLUTError.wrongEntryCount(expected: expected, found: values.count / 3)
        }
        return try CubeLUT(title: title, size: size, domainMin: domainMin, domainMax: domainMax, values: values)
    }
}
