import XCTest
@testable import SnapticKit

final class CubeLUTTests: XCTestCase {
    private func identityText(size: Int, header: String = "") -> String {
        var lines = [header, "LUT_3D_SIZE \(size)"]
        let step = 1 / Double(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    lines.append("\(Double(r) * step) \(Double(g) * step) \(Double(b) * step)")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func assertThrows(_ text: String, _ expected: CubeLUTError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try CubeLUT.parse(text: text), file: file, line: line) { error in
            XCTAssertEqual(error as? CubeLUTError, expected, file: file, line: line)
        }
    }

    // MARK: Valid files

    func testParsesIdentityWithTitleAndComments() throws {
        let text = "# Created by a test\nTITLE \"Warm # look\"\n" + identityText(size: 2) + "# trailing comment\n"
        let lut = try CubeLUT.parse(text: text)
        XCTAssertEqual(lut.title, "Warm # look")
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.values.count, 2 * 2 * 2 * 3)
        XCTAssertTrue(lut.hasUnitDomain)
        let e = lut.entry(r: 1, g: 0, b: 1)
        XCTAssertEqual(e.0, 1)
        XCTAssertEqual(e.1, 0)
        XCTAssertEqual(e.2, 1)
        let s = lut.sample(0.25, 0.5, 0.75)
        XCTAssertEqual(s.0, 0.25, accuracy: 1e-6)
        XCTAssertEqual(s.1, 0.5, accuracy: 1e-6)
        XCTAssertEqual(s.2, 0.75, accuracy: 1e-6)
    }

    func testCRLFTabsBOMAndInlineComments() throws {
        var text = identityText(size: 3).replacingOccurrences(of: "\n", with: "\r\n")
        text = text.replacingOccurrences(of: " ", with: "\t")
        text = text.replacingOccurrences(of: "LUT_3D_SIZE\t3", with: "lut_3d_size 3 # three")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(text.utf8))
        let lut = try CubeLUT.parse(data)
        XCTAssertEqual(lut.size, 3)
        XCTAssertEqual(lut.entry(r: 2, g: 1, b: 0).1, 0.5, accuracy: 1e-6)
    }

    func testDomainKeywords() throws {
        let text = "DOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2\n" + identityText(size: 2)
        let lut = try CubeLUT.parse(text: text)
        XCTAssertEqual(lut.domainMax, [2, 2, 2])
        XCTAssertFalse(lut.hasUnitDomain)
        XCTAssertEqual(lut.inputScale, [0.5, 0.5, 0.5])
        XCTAssertEqual(lut.inputBias, [0, 0, 0])
        // Input 1 is halfway through the domain.
        XCTAssertEqual(lut.sample(1, 1, 1).0, 0.5, accuracy: 1e-6)

        let ranged = try CubeLUT.parse(text: "LUT_3D_INPUT_RANGE -1 1\n" + identityText(size: 2))
        XCTAssertEqual(ranged.domainMin, [-1, -1, -1])
        XCTAssertEqual(ranged.inputScale, [0.5, 0.5, 0.5])
        XCTAssertEqual(ranged.inputBias, [0.5, 0.5, 0.5])
    }

    func testUnknownVendorKeywordsAreIgnored() throws {
        let lut = try CubeLUT.parse(text: "LUT_IN_VIDEO_RANGE\nCUSTOM_TAG 1 2\n" + identityText(size: 2))
        XCTAssertEqual(lut.size, 2)
    }

    // MARK: Rejections

    func testRejections() {
        let body8 = (0..<8).map { _ in "0 0 0" }.joined(separator: "\n")
        assertThrows("# nothing\n", .missingSize)
        assertThrows("", .missingSize)
        assertThrows("LUT_3D_SIZE 1\n", .unsupportedSize(1))
        assertThrows("LUT_3D_SIZE 129\n", .unsupportedSize(129))
        assertThrows("LUT_3D_SIZE 12345\n", .malformedLine(1))
        assertThrows("LUT_3D_SIZE two\n", .malformedLine(1))
        assertThrows("LUT_1D_SIZE 16\n", .oneDimensional)
        assertThrows("LUT_1D_INPUT_RANGE 0 1\nLUT_3D_SIZE 2\n", .oneDimensional)
        assertThrows("LUT_3D_SIZE 2\nLUT_3D_SIZE 2\n", .duplicateKeyword(2))
        assertThrows("TITLE \"a\"\nTITLE \"b\"\n", .duplicateKeyword(2))
        assertThrows("0 0 0\nLUT_3D_SIZE 2\n", .dataBeforeSize(1))
        assertThrows("LUT_3D_SIZE 2\n0 0 0\nDOMAIN_MIN 0 0 0\n", .keywordAfterData(3))
        assertThrows("LUT_3D_SIZE 2\n" + body8 + "\n0 0 0\n", .wrongEntryCount(expected: 8, found: 9))
        assertThrows("LUT_3D_SIZE 2\n0 0 0\n", .wrongEntryCount(expected: 8, found: 1))
        assertThrows("LUT_3D_SIZE 2\n0 0\n", .malformedLine(2))
        assertThrows("LUT_3D_SIZE 2\n0 0 0 0\n", .malformedLine(2))
        assertThrows("LUT_3D_SIZE 2\n0 0 x\n", .malformedLine(2))
        assertThrows("LUT_3D_SIZE 2\n0 0 2000\n", .valueOutOfRange(2))
        assertThrows("LUT_3D_SIZE 2\n0 0 nan\n", .malformedLine(2))
        assertThrows("DOMAIN_MIN 1 1 1\nDOMAIN_MAX 1 1 1\nLUT_3D_SIZE 2\n" + body8, .invalidDomain)
        assertThrows("DOMAIN_MIN 0 0\n", .malformedLine(1))
        assertThrows("1 2 3 4 5 6 7 8 9 10\n", .malformedLine(1))
        assertThrows("LUT_3D_SIZE 2\n" + String(repeating: " ", count: 2000) + "\n", .lineTooLong(2))
        XCTAssertThrowsError(try CubeLUT.parse(Data([0x4C, 0x00, 0x0A]))) { XCTAssertEqual($0 as? CubeLUTError, .notText) }
    }

    func testOversizeDataIsRejectedBeforeParsing() {
        XCTAssertThrowsError(try CubeLUT.parse(Data(count: CubeLUT.maxFileBytes + 1))) {
            XCTAssertEqual($0 as? CubeLUTError, .fileTooLarge)
        }
    }

    func testValidatingInitializer() {
        XCTAssertThrowsError(try CubeLUT(size: 2, values: [0, 0, 0]))
        XCTAssertThrowsError(try CubeLUT(size: 2, values: [Float](repeating: .nan, count: 24)))
        XCTAssertThrowsError(try CubeLUT(size: 2, domainMin: [0, 0], values: [Float](repeating: 0, count: 24)))
        XCTAssertNoThrow(try CubeLUT(size: 2, values: [Float](repeating: 0.5, count: 24)))
    }

    // MARK: Numbers

    func testNumberParser() {
        func parse(_ s: String) -> Double? {
            let bytes = Array(s.utf8)
            return bytes.withUnsafeBufferPointer { CubeLUT.parseNumber($0, 0, $0.count) }
        }
        XCTAssertEqual(parse("0"), 0)
        XCTAssertEqual(parse("1"), 1)
        XCTAssertEqual(parse("-0.5"), -0.5)
        XCTAssertEqual(parse("+.25"), 0.25)
        XCTAssertEqual(parse("1."), 1)
        XCTAssertEqual(parse("1e-3"), 0.001)
        XCTAssertEqual(parse("2.5E+2"), 250)
        XCTAssertEqual(parse("0.000123"), 0.000123)
        XCTAssertEqual(parse("0.1"), 0.1)
        XCTAssertEqual(parse("0.333333333333333333333333") ?? 0, 1.0 / 3.0, accuracy: 1e-15)
        for bad in ["", "-", "+", ".", "e5", "1e", "1e+", "1.2.3", "0x10", "inf", "nan", "1e500", "--1", "1-", "１"] {
            XCTAssertNil(parse(bad), bad)
        }
        XCTAssertNil(parse(String(repeating: "1", count: 65)))
    }

    func testNumberParserMatchesFoundation() {
        var rng = SeededGenerator(seed: 0xC0BE)
        for _ in 0..<5000 {
            let mantissa = Double(rng.next() % 10_000_000) / Double(1 + rng.next() % 1_000_000)
            let sign = rng.next() % 2 == 0 ? "" : "-"
            let text: String
            switch rng.next() % 3 {
            case 0: text = sign + String(mantissa)
            case 1: text = sign + String(format: "%.6f", mantissa)
            default: text = sign + String(format: "%.9e", mantissa)
            }
            let expected = Double(text)
            let bytes = Array(text.utf8)
            let got = bytes.withUnsafeBufferPointer { CubeLUT.parseNumber($0, 0, $0.count) }
            guard let e = expected, let g = got else {
                XCTAssertEqual(expected == nil, got == nil, text)
                continue
            }
            XCTAssertEqual(g, e, accuracy: Swift.max(abs(e) * 1e-12, 1e-300), text)
        }
    }

    // MARK: Fuzzing

    func testFuzzRandomBytesNeverTrap() {
        var rng = SeededGenerator(seed: 0xF00D)
        let alphabet = Array("0123456789 .-+eE#\n\r\tLUT_3DSIZEDOMAINMXTITLE\"abc".utf8) + [0x00, 0xFF, 0x7F]
        for _ in 0..<3000 {
            let count = Int(rng.next() % 400)
            var bytes: [UInt8] = []
            for _ in 0..<count { bytes.append(alphabet[Int(rng.next() % UInt64(alphabet.count))]) }
            do {
                let lut = try CubeLUT.parse(Data(bytes))
                XCTAssertTrue((CubeLUT.minSize...CubeLUT.maxSize).contains(lut.size))
                XCTAssertEqual(lut.values.count, lut.size * lut.size * lut.size * 3)
            } catch {
                XCTAssertNotNil(error as? CubeLUTError)
            }
        }
    }

    func testFuzzMutatedValidFile() {
        var rng = SeededGenerator(seed: 0xBEEF)
        let base = Array(("TITLE \"x\"\nDOMAIN_MIN 0 0 0\n" + identityText(size: 3)).utf8)
        var parsedOK = 0
        for _ in 0..<2000 {
            var bytes = base
            let edits = 1 + Int(rng.next() % 4)
            for _ in 0..<edits {
                let i = Int(rng.next() % UInt64(bytes.count))
                switch rng.next() % 3 {
                case 0: bytes[i] = UInt8(truncatingIfNeeded: rng.next())
                case 1: bytes.remove(at: i)
                default: bytes.insert(UInt8(truncatingIfNeeded: rng.next()), at: i)
                }
                if bytes.isEmpty { bytes = [0x0A] }
            }
            do {
                let lut = try CubeLUT.parse(Data(bytes))
                parsedOK += 1
                XCTAssertEqual(lut.values.count, lut.size * lut.size * lut.size * 3)
                XCTAssertTrue(lut.values.allSatisfy { $0.isFinite && abs($0) <= Float(CubeLUT.valueLimit) })
            } catch {
                XCTAssertNotNil(error as? CubeLUTError)
            }
        }
        // Some mutations land in comments or whitespace and still parse.
        XCTAssertGreaterThan(parsedOK, 0)
    }

    // MARK: Lookup and conversion

    func testIdentityResampleAndRenderable() throws {
        let lut = try XCTUnwrap(CubeLUT.identity(size: 17))
        let s = lut.sample(0.3, 0.6, 0.9)
        XCTAssertEqual(s.0, 0.3, accuracy: 1e-5)
        XCTAssertEqual(s.1, 0.6, accuracy: 1e-5)
        XCTAssertEqual(s.2, 0.9, accuracy: 1e-5)
        let small = try XCTUnwrap(lut.resampled(to: 5))
        XCTAssertEqual(small.size, 5)
        XCTAssertEqual(small.entry(r: 2, g: 4, b: 0).0, 0.5, accuracy: 1e-5)
        XCTAssertEqual(small.entry(r: 2, g: 4, b: 0).1, 1, accuracy: 1e-5)
        XCTAssertNil(lut.resampled(to: 1))
        let big = try XCTUnwrap(CubeLUT.identity(size: 65))
        XCTAssertEqual(big.renderable.size, CubeLUT.maxRenderSize)
        XCTAssertEqual(small.renderable.size, 5)
        // Out-of-domain input clamps.
        XCTAssertEqual(lut.sample(-3, 7, 0.5).0, 0, accuracy: 1e-6)
        XCTAssertEqual(lut.sample(-3, 7, 0.5).1, 1, accuracy: 1e-6)
    }

    func testResamplingKeepsANonlinearTableAtGridPoints() throws {
        var values: [Float] = []
        let n = 9
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let x = Double(r) / Double(n - 1), y = Double(g) / Double(n - 1), z = Double(b) / Double(n - 1)
                    values += [Float(x * x), Float(1 - y), Float((x + z) / 2)]
                }
            }
        }
        let lut = try CubeLUT(size: n, values: values)
        let resampled = try XCTUnwrap(lut.resampled(to: 5))
        // 5-point grid lines up with every other 9-point grid point.
        for i in 0..<5 {
            let a = resampled.entry(r: i, g: i, b: 4 - i)
            let b = lut.entry(r: i * 2, g: i * 2, b: 8 - i * 2)
            XCTAssertEqual(a.0, b.0, accuracy: 1e-5)
            XCTAssertEqual(a.1, b.1, accuracy: 1e-5)
            XCTAssertEqual(a.2, b.2, accuracy: 1e-5)
        }
    }

    func testRGBAFloatData() throws {
        let lut = try XCTUnwrap(CubeLUT.identity(size: 2))
        let data = lut.rgbaFloatData()
        XCTAssertEqual(data.count, 8 * 4 * MemoryLayout<Float>.size)
        let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(Array(floats[4..<8]), [1, 0, 0, 1])
        XCTAssertEqual(Array(floats[28..<32]), [1, 1, 1, 1])
    }

    // MARK: Picked files

    func testReadPickedFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cube-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.cube")
        let text = identityText(size: 2)
        try Data(text.utf8).write(to: file)

        let data = try CubeLUT.readPickedFile(atPath: file.path)
        XCTAssertEqual(data, Data(text.utf8))
        XCTAssertEqual(try CubeLUT.parse(data).size, 2)

        XCTAssertThrowsError(try CubeLUT.readPickedFile(atPath: file.path, maxBytes: 10)) {
            XCTAssertEqual($0 as? CubeLUTError, .fileTooLarge)
        }
        XCTAssertThrowsError(try CubeLUT.readPickedFile(atPath: dir.path)) {
            XCTAssertEqual($0 as? CubeLUTError, .notRegularFile)
        }
        XCTAssertThrowsError(try CubeLUT.readPickedFile(atPath: dir.appendingPathComponent("missing").path)) {
            XCTAssertEqual($0 as? CubeLUTError, .unreadable)
        }
        let link = dir.appendingPathComponent("link.cube")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: file.path)
        XCTAssertThrowsError(try CubeLUT.readPickedFile(atPath: link.path)) {
            XCTAssertEqual($0 as? CubeLUTError, .unreadable)
        }
        XCTAssertThrowsError(try CubeLUT.readPickedFile(atPath: "")) { XCTAssertEqual($0 as? CubeLUTError, .pathTooLong) }
        XCTAssertThrowsError(try CubeLUT.readPickedFile(atPath: "/" + String(repeating: "a", count: 1100))) {
            XCTAssertEqual($0 as? CubeLUTError, .pathTooLong)
        }
    }

    func testErrorMessagesAreNonEmpty() {
        let all: [CubeLUTError] = [.pathTooLong, .unreadable, .notRegularFile, .fileTooLarge, .notText, .lineTooLong(1),
                                   .malformedLine(1), .missingSize, .unsupportedSize(1), .oneDimensional,
                                   .duplicateKeyword(1), .keywordAfterData(1), .dataBeforeSize(1), .valueOutOfRange(1),
                                   .invalidDomain, .wrongEntryCount(expected: 8, found: 1)]
        for e in all { XCTAssertFalse(e.message.isEmpty) }
    }
}
