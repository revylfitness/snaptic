import XCTest
@testable import SnapticKit

final class KitHookPolicyTests: XCTestCase {
    private let uid: UInt32 = 501

    private func chain(_ path: String, leafMode: UInt32 = 0o755, leafOwner: UInt32 = 501) -> [PathComponentInfo] {
        let parts = KitHookPolicy.components(of: path)
        return parts.enumerated().map { i, p in
            let last = i == parts.count - 1
            return PathComponentInfo(path: p, isDirectory: !last, isRegularFile: last,
                                     owner: last ? leafOwner : (i < 2 ? 0 : 501), mode: last ? leafMode : 0o755)
        }
    }

    func testSyntax() {
        XCTAssertNil(KitHookPolicy.checkSyntax("/Users/a/bin/tool"))
        XCTAssertEqual(KitHookPolicy.checkSyntax("bin/tool"), .notAbsolute)
        XCTAssertEqual(KitHookPolicy.checkSyntax("/Users/a/../b/tool"), .dotComponent)
        XCTAssertEqual(KitHookPolicy.checkSyntax("/Users/./tool"), .dotComponent)
        XCTAssertEqual(KitHookPolicy.checkSyntax("/a\nb"), .badCharacters)
        XCTAssertEqual(KitHookPolicy.checkSyntax("/" + String(repeating: "a", count: 1100)), .tooLong)
        XCTAssertEqual(KitHookPolicy.checkSyntax("/"), .notRegularFile)
    }

    func testComponents() {
        XCTAssertEqual(KitHookPolicy.components(of: "/a/b/c"), ["/", "/a", "/a/b", "/a/b/c"])
        XCTAssertEqual(KitHookPolicy.components(of: "//a//b"), ["/", "/a", "/a/b"])
    }

    func testGoodChainPasses() {
        XCTAssertNil(KitHookPolicy.check(chain("/Users/a/bin/tool"), userID: uid))
        XCTAssertNil(KitHookPolicy.check(chain("/usr/bin/say", leafOwner: 0), userID: uid))
    }

    func testRefusals() {
        var c = chain("/Users/a/bin/tool")
        c[2].mode = 0o775
        XCTAssertEqual(KitHookPolicy.check(c, userID: uid), .writableByOthers("/Users/a"))
        c = chain("/Users/a/bin/tool")
        c[3].owner = 502
        XCTAssertEqual(KitHookPolicy.check(c, userID: uid), .badOwner("/Users/a/bin"))
        c = chain("/Users/a/bin/tool")
        c[3].isSymlink = true
        XCTAssertEqual(KitHookPolicy.check(c, userID: uid), .symlink("/Users/a/bin"))
        XCTAssertEqual(KitHookPolicy.check(chain("/Users/a/bin/tool", leafMode: 0o644), userID: uid), .notExecutable)
        XCTAssertEqual(KitHookPolicy.check(chain("/Users/a/bin/tool", leafMode: 0o777), userID: uid),
                       .writableByOthers("/Users/a/bin/tool"))
        c = chain("/Users/a/bin/tool")
        c[4].isRegularFile = false
        XCTAssertEqual(KitHookPolicy.check(c, userID: uid), .notRegularFile)
        c = chain("/Users/a/bin/tool")
        c[4].exists = false
        XCTAssertEqual(KitHookPolicy.check(c, userID: uid), .missing("/Users/a/bin/tool"))
        c = chain("/Users/a/bin/tool")
        c[1].isDirectory = false
        XCTAssertEqual(KitHookPolicy.check(c, userID: uid), .notDirectory("/Users"))
        XCTAssertEqual(KitHookPolicy.check([], userID: uid), .notRegularFile)
    }

    func testFuzzedChainsPassOnlyWhenEveryRuleHolds() {
        var rng = SeededGenerator(seed: 0x400C)
        for _ in 0..<3_000 {
            var c = chain("/a/b/c/tool")
            for i in c.indices {
                if rng.next() % 10 == 0 { c[i].mode = UInt32(rng.next() % 0o1000) }
                if rng.next() % 10 == 0 { c[i].owner = UInt32(rng.next() % 3) == 0 ? 0 : 777 }
                if rng.next() % 15 == 0 { c[i].isSymlink = true }
            }
            let ok = KitHookPolicy.check(c, userID: uid) == nil
            let expected = c.allSatisfy { !$0.isSymlink && ($0.owner == uid || $0.owner == 0) && $0.mode & 0o022 == 0 }
                && c.last!.mode & 0o111 != 0
            XCTAssertEqual(ok, expected)
        }
    }

    func testArguments() {
        XCTAssertNil(KitHookPolicy.checkArguments(["a", "b"]))
        XCTAssertEqual(KitHookPolicy.checkArguments(Array(repeating: "x", count: 9)), .tooManyArguments)
        XCTAssertEqual(KitHookPolicy.checkArguments([String(repeating: "x", count: 300)]), .argumentTooLong)
    }

    func testInsideBundle() {
        let bundle = "/Applications/Snaptic.app"
        XCTAssertTrue(KitHookPolicy.isInside("/Applications/Snaptic.app/Contents/MacOS/Snaptic", bundle: bundle))
        XCTAssertTrue(KitHookPolicy.isInside(bundle, bundle: bundle + "/"))
        XCTAssertFalse(KitHookPolicy.isInside("/Applications/Snaptic.appx/tool", bundle: bundle))
        XCTAssertFalse(KitHookPolicy.isInside("/usr/bin/true", bundle: ""))
    }

    func testEnvironmentIsMinimalAndClean() {
        let key = DisplayKey(rawValue: String(repeating: "0f", count: 16))!
        let env = KitHookPolicy.environment(event: .connect, displayName: "Studio\u{202E}Display", displayKey: key)
        XCTAssertEqual(Set(env.keys), ["PATH", "SNAPTIC_EVENT", "SNAPTIC_DISPLAY_NAME", "SNAPTIC_DISPLAY_KEY"])
        XCTAssertEqual(env["SNAPTIC_DISPLAY_NAME"], "StudioDisplay")
        XCTAssertEqual(env["SNAPTIC_EVENT"], "connect")
        XCTAssertEqual(KitHookPolicy.environment(event: .wake, displayName: nil, displayKey: nil).count, 2)
        XCTAssertEqual(KitHookPolicy.environmentList(["B": "2", "A": "1"]), ["A=1", "B=2"])
    }

    func testThrottle() {
        var t = HookThrottle(interval: 10)
        XCTAssertTrue(t.allow("h1.connect", now: 100))
        XCTAssertFalse(t.allow("h1.connect", now: 105))
        XCTAssertTrue(t.allow("h2.connect", now: 105))
        XCTAssertTrue(t.allow("h1.connect", now: 110))
        XCTAssertTrue(t.allow("h1.connect", now: 50))   // clock went back: don't block forever
    }

    func testEveryRefusalHasAMessage() {
        let all: [HookRefusal] = [.notAbsolute, .tooLong, .badCharacters, .dotComponent, .missing("/x"), .symlink("/x"),
                                  .badOwner("/x"), .writableByOthers("/x"), .notDirectory("/x"), .notRegularFile,
                                  .notExecutable, .insideSnaptic, .snapticIdentity, .tooManyArguments, .argumentTooLong]
        for r in all { XCTAssertFalse(r.message.isEmpty) }
    }
}
