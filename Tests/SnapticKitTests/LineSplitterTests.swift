import XCTest
import SnapticKit

final class LineSplitterTests: XCTestCase {
    func testSplitsAcrossChunks() {
        var s = LineSplitter()
        XCTAssertEqual(s.feed(Data("ab".utf8)), [])
        XCTAssertEqual(s.feed(Data("c\nde\n\nf".utf8)), [Data("abc".utf8), Data("de".utf8), Data()])
        XCTAssertEqual(s.feed(Data("\n".utf8)), [Data("f".utf8)])
    }

    func testRejectsOversizedLineWithNewline() {
        var s = LineSplitter()
        var big = Data(repeating: 0x41, count: LineSplitter.maxLine + 1)
        big.append(0x0A)
        XCTAssertNil(s.feed(big))
    }

    func testRejectsOversizedPartialLine() {
        var s = LineSplitter()
        XCTAssertNil(s.feed(Data(repeating: 0x41, count: LineSplitter.maxLine + 1)))
    }

    func testAcceptsMaxLengthLine() {
        var s = LineSplitter()
        var line = Data(repeating: 0x41, count: LineSplitter.maxLine)
        line.append(0x0A)
        XCTAssertEqual(s.feed(line)?.first?.count, LineSplitter.maxLine)
    }

    func testRandomChunkingMatchesWholeFeed() {
        var rng = SeededGenerator(seed: 42)
        for _ in 0..<200 {
            var bytes = Data()
            for _ in 0..<Int(rng.next() % 400) { bytes.append(rng.next() % 5 == 0 ? 0x0A : UInt8(65 + rng.next() % 26)) }
            var whole = LineSplitter()
            let expected = whole.feed(bytes)
            var chunked = LineSplitter()
            var got: [Data] = []
            var i = bytes.startIndex
            while i < bytes.endIndex {
                let n = min(Int(rng.next() % 17) + 1, bytes.endIndex - i)
                got += chunked.feed(bytes[i..<(i + n)]) ?? []
                i += n
            }
            XCTAssertEqual(got, expected)
        }
    }
}
