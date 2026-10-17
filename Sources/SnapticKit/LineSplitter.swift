import Foundation

/// Splits a byte stream into newline-terminated lines, bounded (R2C §4.3).
package struct LineSplitter: Sendable {
    package static let maxLine = 64 * 1024
    private var buffer = Data()

    package init() {}

    /// Complete lines (without the newline), or nil on overflow. A caller must treat
    /// nil as a fatal protocol error.
    package mutating func feed(_ chunk: Data) -> [Data]? {
        buffer.append(chunk)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            if newline - buffer.startIndex > Self.maxLine { return nil }
            lines.append(Data(buffer[buffer.startIndex..<newline]))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return buffer.count > Self.maxLine ? nil : lines
    }
}
