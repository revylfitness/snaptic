import XCTest

// TEMPORARY (team A step 2): runs scripts/selftest-helpers.sh against the debug build on
// the macOS CI runner, to prove the self-test before the lead adds the workflow step.
// Removed again before the final push.
final class SelfTestProbeTests: XCTestCase {
    func testHelperSelfTest() throws {
        #if os(macOS)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let binary = root.appendingPathComponent(".build/debug/Snaptic").path
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw XCTSkip("no debug Snaptic binary at \(binary)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent("scripts/selftest-helpers.sh").path, binary]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, "selftest output:\n" + text)
        XCTAssertTrue(text.contains("both children exited"), "selftest output:\n" + text)
        #endif
    }
}
