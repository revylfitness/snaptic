import XCTest
@testable import SnapticKit

final class AwakeLogEventTests: XCTestCase {
    private var every: [AwakeLogEvent] {
        let kinds: [AwakeHistoryKind] = [.indefinite, .duration, .until, .app, .idle, .process, .automatic]
        let errors = DriveAliveError.allCases
        var out: [AwakeLogEvent] = [.holdStarted, .activityCapped, .assertionFailed, .holdRefused, .restoreDropped]
        for k in kinds { out.append(.sessionStarted(k)) }
        for r in AwakeEndReason.allCases { out.append(.sessionEnded(r)) }
        for i in 0..<AwakeTrigger.maxTriggers { out.append(.triggerActive(index: i)) }
        for e in errors { out.append(.driveAliveError(e)) }
        return out
    }

    func testCountedVersusRing() {
        XCTAssertTrue(AwakeLogEvent.sessionStarted(.duration).isCounted)
        XCTAssertTrue(AwakeLogEvent.sessionEnded(.batteryLow).isCounted)
        XCTAssertTrue(AwakeLogEvent.holdStarted.isCounted)
        XCTAssertTrue(AwakeLogEvent.triggerActive(index: 0).isCounted)
        XCTAssertTrue(AwakeLogEvent.activityCapped.isCounted)
        XCTAssertFalse(AwakeLogEvent.assertionFailed.isCounted)
        XCTAssertFalse(AwakeLogEvent.driveAliveError(.denied).isCounted)
        XCTAssertFalse(AwakeLogEvent.holdRefused.isCounted)
        XCTAssertFalse(AwakeLogEvent.restoreDropped.isCounted)
    }

    func testFixedTextPerCase() {
        let texts = every.map(\.text)
        XCTAssertEqual(Set(texts).count, texts.count, "every case has its own text (counter key)")
        XCTAssertEqual(AwakeLogEvent.sessionStarted(.duration).text, "awake.session.started.duration")
        XCTAssertEqual(AwakeLogEvent.sessionEnded(.commandLineOff).text, "awake.session.ended.commandLineOff")
        XCTAssertEqual(AwakeLogEvent.triggerActive(index: 0).text, "awake.rule.active.1")
        XCTAssertEqual(AwakeLogEvent.triggerActive(index: 9_999).text, "awake.rule.active.32", "bounded")
        XCTAssertEqual(AwakeLogEvent.triggerActive(index: -3).text, "awake.rule.active.1")
        for e in every where e.isCounted {
            XCTAssertTrue(e.text.hasPrefix("awake."))
            XCTAssertFalse(e.text.contains(" "))
        }
    }

    func testNoTextCarriesAPayload() {
        // Only fixed vocabulary: ASCII letters, digits, punctuation from the case list; no names, paths or pids.
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.'()- ")
        for e in every {
            XCTAssertTrue(e.text.allSatisfy { allowed.contains($0) }, e.text)
            XCTAssertLessThan(e.text.count, 80)
        }
    }
}

// MARK: - 0.3.1 B5: lid-closed mode's events (owner: T-lid-kit)

extension AwakeLogEventTests {
    func testLidEvents() {
        var lid: [AwakeLogEvent] = [.lidOn, .lidLeftover]
        lid += AwakeLidEnd.allCases.map { .lidOff($0) }
        lid += AwakeLidFailStage.allCases.map { .lidFailed($0) }
        XCTAssertTrue(AwakeLogEvent.lidOn.isCounted)
        XCTAssertTrue(AwakeLidEnd.allCases.allSatisfy { AwakeLogEvent.lidOff($0).isCounted })
        XCTAssertFalse(AwakeLidFailStage.allCases.contains { AwakeLogEvent.lidFailed($0).isCounted })
        XCTAssertFalse(AwakeLogEvent.lidLeftover.isCounted)
        XCTAssertEqual(AwakeLogEvent.lidOn.text, "awake.lid.on")
        XCTAssertEqual(AwakeLogEvent.lidOff(.otherApp).text, "awake.lid.off.otherApp")
        XCTAssertEqual(AwakeLogEvent.lidFailed(.verify).text, "Lid-closed mode couldn't turn on (verify).")
        XCTAssertEqual(AwakeLogEvent.lidFailed(.restore).text, "Turn Sleep Back On's script reported an error.")
        XCTAssertEqual(AwakeLogEvent.lidLeftover.text, "Sleep was found turned off after an earlier lid-closed session.")
        let texts = (every + lid).map(\.text)
        XCTAssertEqual(Set(texts).count, texts.count, "every case has its own text")
        for t in lid.map(\.text) {
            XCTAssertFalse(t.contains("/"), "no paths, tokens or pids: \(t)")
            XCTAssertTrue(t.unicodeScalars.allSatisfy { $0.isASCII }, t)
        }
    }
}
