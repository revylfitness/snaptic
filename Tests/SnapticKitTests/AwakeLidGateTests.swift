import XCTest
@testable import SnapticKit

// N19, the lid gate (owner: T-lid-kit; PLAN 0.3.1 B2): the whole truth table, the hotkey rows included.

final class AwakeLidGateTests: XCTestCase {
    private let sources: [AwakeSessionSource] = [.menu, .hotkey, .settings, .commandLine, .launch, .rule]

    private var events: [AwakeLidGate.Event] {
        [.request(running: nil)] + sources.map { .request(running: $0) } + sources.map { .replaced(by: $0) }
            + [.sessionEnded, .triggerOrHold, .moduleStopped, .safeMode, .featureOff, .restore]
    }

    private func decide(_ s: AwakeSessionSource, _ mayStart: Bool = true, _ e: AwakeLidGate.Event) -> AwakeLidGate.Decision {
        AwakeLidGate.decide(source: s, mayStart: mayStart, event: e)
    }

    /// Every (source, mayStart, event) against a hand-written table (r1 C9: nothing here recomputes the rule). The
    /// only rows that aren't `.end` are listed; everything else must end.
    func testExhaustiveTable() {
        let notEnd: [(AwakeSessionSource, Bool, AwakeLidGate.Event, AwakeLidGate.Decision)] = [
            // A menu click, with or without Settings' focus guard: idle, or in a menu or Settings session.
            (.menu, false, .request(running: nil), .allowed),
            (.menu, false, .request(running: .menu), .allowed),
            (.menu, false, .request(running: .settings), .allowed),
            (.menu, true, .request(running: nil), .allowed),
            (.menu, true, .request(running: .menu), .allowed),
            (.menu, true, .request(running: .settings), .allowed),
            // A Settings action only while Settings may start sessions.
            (.settings, true, .request(running: nil), .allowed),
            (.settings, true, .request(running: .menu), .allowed),
            (.settings, true, .request(running: .settings), .allowed),
            // Kept across a replacement by such a start from the same place.
            (.menu, false, .replaced(by: .menu), .keep),
            (.menu, true, .replaced(by: .menu), .keep),
            (.settings, true, .replaced(by: .settings), .keep),
        ]
        var checked = 0
        for source in sources {
            for mayStart in [false, true] {
                for event in events {
                    let row = notEnd.first { $0.0 == source && $0.1 == mayStart && $0.2 == event }
                    XCTAssertEqual(decide(source, mayStart, event), row?.3 ?? .end,
                                   "\(source) mayStart=\(mayStart) \(event)")
                    checked += 1
                }
            }
        }
        XCTAssertEqual(checked, 6 * 2 * 19, "every source, both guard states, every event")
        // Every listed row is one the loop reached.
        for row in notEnd {
            XCTAssertTrue(sources.contains(row.0) && events.contains(row.2), "\(row)")
        }
    }

    func testNamedRows() {
        XCTAssertEqual(decide(.menu, false, .request(running: nil)), .allowed, "the menu needs no mayStart")
        XCTAssertEqual(decide(.settings, true, .request(running: nil)), .allowed)
        XCTAssertEqual(decide(.settings, false, .request(running: nil)), .end, "Settings checks mayStart()")
        XCTAssertEqual(decide(.menu, true, .request(running: .settings)), .allowed)
        XCTAssertEqual(decide(.settings, true, .request(running: .menu)), .allowed)
        // Hotkeys never: any same-user process can change their bindings.
        XCTAssertEqual(decide(.hotkey, true, .request(running: nil)), .end)
        XCTAssertEqual(decide(.menu, true, .request(running: .hotkey)), .end, "a hotkey session takes the submenu")
        XCTAssertEqual(decide(.hotkey, true, .replaced(by: .hotkey)), .end)
        // The command line, rules, launch: never.
        for s in [AwakeSessionSource.commandLine, .launch, .rule] {
            XCTAssertEqual(decide(s, true, .request(running: nil)), .end, "\(s)")
            XCTAssertEqual(decide(s, true, .replaced(by: s)), .end, "\(s)")
            XCTAssertEqual(decide(.menu, true, .request(running: s)), .end, "\(s)")
        }
        // Keep across a direct replacement in this process only.
        XCTAssertEqual(decide(.menu, true, .replaced(by: .menu)), .keep)
        XCTAssertEqual(decide(.settings, true, .replaced(by: .settings)), .keep)
        XCTAssertEqual(decide(.settings, false, .replaced(by: .settings)), .end)
        XCTAssertEqual(decide(.menu, true, .replaced(by: .settings)), .end, "an inconsistent call fails safe")
        for e in [AwakeLidGate.Event.sessionEnded, .triggerOrHold, .moduleStopped, .safeMode, .featureOff, .restore] {
            XCTAssertEqual(decide(.menu, true, e), .end, "\(e)")
        }
    }

    func testAddsToSession() {
        for s in sources {
            XCTAssertEqual(AwakeLidGate.addsToSession(source: s, startedInProcess: true), s == .menu || s == .settings,
                           "\(s)")
            XCTAssertFalse(AwakeLidGate.addsToSession(source: s, startedInProcess: false), "restored \(s)")
        }
    }

    /// No persisted path carries the mode (B2): it is no session option, and the session flag is never encoded.
    func testNoPersistedPath() throws {
        let options = String(decoding: try JSONEncoder().encode(AwakeSessionOptions()), as: UTF8.self)
        XCTAssertFalse(options.lowercased().contains("lid"))
        let now = ClockNow(wall: 1_700_000_000, continuous: 100, bootSession: "B")
        var s = AwakeClock.start(.indefinite, options: AwakeSessionOptions(), presetID: nil, source: .menu, now: now,
                                 id: StableID.derived(namespace: "gate", name: "s"))
        s.lidRequested = true
        let data = try JSONEncoder().encode(s)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("lid"))
        XCTAssertFalse(try JSONDecoder().decode(AwakeSession.self, from: data).lidRequested)
    }
}
