import XCTest
@testable import SnapticKit

final class ToastPolicyTests: XCTestCase {
    private let never: () -> Bool = { false }

    // MARK: Rules

    func testActionsAtMostTwoAndOneDefault() {
        XCTAssertTrue(ToastRules.normalizedActions(isDefault: []) == (0, nil))
        XCTAssertTrue(ToastRules.normalizedActions(isDefault: [false]) == (1, nil))
        XCTAssertTrue(ToastRules.normalizedActions(isDefault: [false, true]) == (2, 1))
        XCTAssertTrue(ToastRules.normalizedActions(isDefault: [true, true]) == (2, 0), "the first default wins")
        XCTAssertTrue(ToastRules.normalizedActions(isDefault: [false, false, true]) == (2, nil), "a third is dropped")
    }

    func testRecentNewestLastUniqueBounded() {
        var list: [String] = []
        list = ToastRules.appendingRecent("a", to: list)
        list = ToastRules.appendingRecent("b", to: list)
        list = ToastRules.appendingRecent("a", to: list)
        XCTAssertEqual(list, ["b", "a"])
        list = ToastRules.appendingRecent("", to: list)
        XCTAssertEqual(list, ["b", "a"])
        for n in 0..<20 { list = ToastRules.appendingRecent("n\(n)", to: list) }
        XCTAssertEqual(list.count, ToastRules.maxRecent)
        XCTAssertEqual(list.first, "n10")
        XCTAssertEqual(list.last, "n19")
    }

    func testDisplayDuration() {
        XCTAssertEqual(ToastRules.displayDuration(hasActions: false, queuedAt: 0, now: 0), 4)
        XCTAssertEqual(ToastRules.displayDuration(hasActions: true, queuedAt: 0, now: 0), 10)
        XCTAssertEqual(ToastRules.displayDuration(hasActions: true, queuedAt: 0, now: 3), 7, "queued time counts")
        XCTAssertEqual(ToastRules.displayDuration(hasActions: false, queuedAt: 0, now: 8), 2)
        XCTAssertEqual(ToastRules.displayDuration(hasActions: true, queuedAt: 0, now: 9.9), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ToastRules.displayDuration(hasActions: false, queuedAt: 5, now: 2), 4, "clock went back")
    }

    // MARK: Suppression

    func testSuppression() {
        XCTAssertFalse(ToastSuppressionFacts().isSuppressed)
        XCTAssertTrue(ToastSuppressionFacts(locked: true).isSuppressed)
        XCTAssertTrue(ToastSuppressionFacts(offConsole: true).isSuppressed)
        XCTAssertTrue(ToastSuppressionFacts(screensaverFrontmost: true).isSuppressed)
        XCTAssertTrue(ToastSuppressionFacts(mirroring: true).isSuppressed)
        XCTAssertTrue(ToastSuppressionFacts(frontmostCoversDisplay: true).isSuppressed)
        XCTAssertTrue(ToastSuppressionFacts(mirroring: true).presenting)
    }

    func testScreensaverHintExpires() {
        XCTAssertTrue(ToastSuppressionFacts(screensaverHintAge: 0).screensaverRunning)
        XCTAssertTrue(ToastSuppressionFacts(screensaverHintAge: 9.9).screensaverRunning)
        XCTAssertFalse(ToastSuppressionFacts(screensaverHintAge: 10).screensaverRunning, "a hint lasts 10 s at most")
        XCTAssertFalse(ToastSuppressionFacts(screensaverHintAge: -1).screensaverRunning)
        XCTAssertTrue(ToastSuppressionFacts(screensaverFrontmost: true, screensaverHintAge: 60).screensaverRunning,
                      "the engine being frontmost is the truth")
    }

    // MARK: Geometry

    func testCocoaToCG() {
        // Primary 1080 high; a 400×56 panel whose bottom is at y = 1000 has its top 24 pt below the top.
        XCTAssertEqual(ToastGeometry.cgRect(cocoaX: 760, y: 1000, width: 400, height: 56, primaryHeight: 1080),
                       ScreenRect(x: 760, y: 24, width: 400, height: 56))
        // A screen above the primary has negative CG y.
        XCTAssertEqual(ToastGeometry.cgRect(cocoaX: 0, y: 1200, width: 100, height: 100, primaryHeight: 1080).y, -220)
    }

    func testIntersects() {
        let a = ScreenRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertTrue(ToastGeometry.intersects(a, ScreenRect(x: 99, y: 49, width: 10, height: 10)))
        XCTAssertFalse(ToastGeometry.intersects(a, ScreenRect(x: 100, y: 0, width: 10, height: 10)), "touching")
        XCTAssertFalse(ToastGeometry.intersects(a, ScreenRect(x: 0, y: 50, width: 10, height: 10)), "touching")
        XCTAssertFalse(ToastGeometry.intersects(a, ScreenRect(x: 10, y: 10, width: 0, height: 10)), "empty")
        XCTAssertTrue(ToastGeometry.intersects(a, ScreenRect(x: -10, y: -10, width: 200, height: 200)), "contains")
    }

    func testCovers() {
        let display = ScreenRect(x: 1920, y: 0, width: 2560, height: 1440)
        XCTAssertTrue(ToastGeometry.covers(ScreenRect(x: 1920, y: 0, width: 2560, height: 1440), display: display))
        XCTAssertTrue(ToastGeometry.covers(ScreenRect(x: 1920.5, y: 0.5, width: 2559, height: 1439), display: display),
                      "within 1 pt")
        XCTAssertFalse(ToastGeometry.covers(ScreenRect(x: 1920, y: 25, width: 2560, height: 1415), display: display),
                       "a zoomed window under the menu bar isn't presenting")
        XCTAssertFalse(ToastGeometry.covers(ScreenRect(x: 0, y: 0, width: 1920, height: 1080), display: display))
        XCTAssertFalse(ToastGeometry.covers(display, display: ScreenRect(x: 0, y: 0, width: 0, height: 0)))
        XCTAssertTrue(ToastGeometry.anyCovers(windows: [ScreenRect(x: 0, y: 0, width: 10, height: 10), display],
                                              displays: [ScreenRect(x: 0, y: 0, width: 1920, height: 1080), display]))
        XCTAssertFalse(ToastGeometry.anyCovers(windows: [], displays: [display]))
    }

    // MARK: Guarded clicks

    func testOverlap() {
        let panel = ScreenRect(x: 100, y: 30, width: 400, height: 56)
        let over = ScreenRect(x: 300, y: 50, width: 50, height: 50)
        let away = ScreenRect(x: 0, y: 500, width: 50, height: 50)
        let me: Int32 = 42
        XCTAssertFalse(ToastClickPolicy.isOverlapped(panel: panel, above: [], ownPID: me))
        XCTAssertTrue(ToastClickPolicy.isOverlapped(panel: panel, above: nil, ownPID: me), "fail closed")
        XCTAssertTrue(ToastClickPolicy.isOverlapped(panel: panel, above: [ToastWindowAbove(bounds: over, alpha: 1, ownerPID: 7)],
                                                    ownPID: me))
        XCTAssertTrue(ToastClickPolicy.isOverlapped(panel: panel, above: [ToastWindowAbove(bounds: over, alpha: 0.01, ownerPID: 7)],
                                                    ownPID: me), "any alpha above 0")
        XCTAssertFalse(ToastClickPolicy.isOverlapped(panel: panel, above: [ToastWindowAbove(bounds: over, alpha: 0, ownerPID: 7)],
                                                     ownPID: me), "invisible")
        XCTAssertFalse(ToastClickPolicy.isOverlapped(panel: panel, above: [ToastWindowAbove(bounds: over, alpha: 1, ownerPID: me)],
                                                     ownPID: me), "our own window")
        XCTAssertFalse(ToastClickPolicy.isOverlapped(panel: panel, above: [ToastWindowAbove(bounds: away, alpha: 1, ownerPID: 7)],
                                                     ownPID: me), "elsewhere")
    }

    func testArming() {
        XCTAssertTrue(ToastClickPolicy.accepts(armDelay: nil, shownAt: 10, now: 10, overlapped: true), "unguarded")
        XCTAssertFalse(ToastClickPolicy.accepts(armDelay: 0.3, shownAt: 10, now: 10.299, overlapped: false))
        XCTAssertTrue(ToastClickPolicy.accepts(armDelay: 0.3, shownAt: 10, now: 10.3, overlapped: false))
        XCTAssertFalse(ToastClickPolicy.accepts(armDelay: 0.3, shownAt: 10, now: 11, overlapped: true))
        XCTAssertFalse(ToastClickPolicy.accepts(armDelay: 0.3, shownAt: 10, now: 9, overlapped: false), "clock went back")
        XCTAssertTrue(ToastClickPolicy.accepts(armDelay: 0, shownAt: 10, now: 10, overlapped: false))
    }

    // MARK: Queue

    func testOfferQueuesMergesAndSuppresses() {
        var q = ToastQueueModel()
        XCTAssertEqual(q.offer("", hasActions: false, now: 0, suppressed: never), .empty)
        XCTAssertEqual(q.offer("a", hasActions: false, now: 0, suppressed: never), .queued(id: 1, evicted: nil))
        XCTAssertEqual(q.offer("a", hasActions: true, now: 0, suppressed: never), .merged)
        var asked = false
        XCTAssertEqual(q.offer("b", hasActions: false, now: 0, suppressed: { asked = true; return true }), .suppressed)
        XCTAssertTrue(asked)
        asked = false
        XCTAssertEqual(q.offer("a", hasActions: false, now: 0, suppressed: { asked = true; return true }), .merged)
        XCTAssertFalse(asked, "merging needs no suppression facts")
        XCTAssertTrue(ToastQueueModel.Offer.suppressed.addsToRecent)
        XCTAssertTrue(ToastQueueModel.Offer.queued(id: 1, evicted: nil).addsToRecent)
        XCTAssertFalse(ToastQueueModel.Offer.merged.addsToRecent)
        XCTAssertFalse(ToastQueueModel.Offer.empty.addsToRecent)
    }

    func testMergesWithTheShowingToast() {
        var q = ToastQueueModel()
        _ = q.offer("a", hasActions: false, now: 0, suppressed: never)
        XCTAssertEqual(q.next(now: 0, suppressed: never).presented?.text, "a")
        XCTAssertEqual(q.offer("a", hasActions: false, now: 1, suppressed: never), .merged)
        XCTAssertEqual(q.finishCurrent()?.text, "a")
        XCTAssertEqual(q.offer("a", hasActions: false, now: 2, suppressed: never), .queued(id: 2, evicted: nil))
    }

    func testEvictsTheOldestBeyondEight() {
        var q = ToastQueueModel()
        for n in 1...8 { XCTAssertEqual(q.offer("t\(n)", hasActions: false, now: 0, suppressed: never),
                                        .queued(id: UInt64(n), evicted: nil)) }
        XCTAssertEqual(q.offer("t9", hasActions: false, now: 0, suppressed: never), .queued(id: 9, evicted: 1))
        XCTAssertEqual(q.queue.map(\.text), (2...9).map { "t\($0)" })
    }

    func testNextOneAtATimeInOrderAndExpiry() {
        var q = ToastQueueModel()
        _ = q.offer("a", hasActions: false, now: 0, suppressed: never)
        _ = q.offer("b", hasActions: false, now: 5, suppressed: never)
        _ = q.offer("c", hasActions: false, now: 9, suppressed: never)
        let first = q.next(now: 1, suppressed: never)
        XCTAssertEqual(first.presented?.id, 1)
        XCTAssertEqual(q.next(now: 1, suppressed: never).presented, nil, "one at a time")
        _ = q.finishCurrent()
        let second = q.next(now: 15, suppressed: never)
        XCTAssertEqual(second.expired, [2], "b waited 10 s")
        XCTAssertEqual(second.presented?.text, "c")
        _ = q.finishCurrent()
        XCTAssertTrue(q.next(now: 20, suppressed: never) == (nil, []))
    }

    func testNextWaitsWhileSuppressed() {
        var q = ToastQueueModel()
        _ = q.offer("a", hasActions: false, now: 0, suppressed: never)
        let held = q.next(now: 1, suppressed: { true })
        XCTAssertNil(held.presented)
        XCTAssertEqual(q.queue.count, 1, "kept until it can show or expires")
        XCTAssertEqual(q.next(now: 2, suppressed: never).presented?.text, "a")
        var r = ToastQueueModel()
        var asked = false
        _ = r.next(now: 0, suppressed: { asked = true; return true })
        XCTAssertFalse(asked, "an empty queue asks nothing")
    }

    func testRemoveQueuedAndRemoveAll() {
        var q = ToastQueueModel()
        _ = q.offer("a", hasActions: false, now: 0, suppressed: never)
        _ = q.offer("b", hasActions: false, now: 0, suppressed: never)
        _ = q.offer("c", hasActions: false, now: 0, suppressed: never)
        _ = q.next(now: 0, suppressed: never)
        XCTAssertFalse(q.removeQueued(1), "showing, not waiting")
        XCTAssertTrue(q.removeQueued(2))
        XCTAssertFalse(q.removeQueued(2))
        XCTAssertEqual(q.removeAll(), [1, 3])
        XCTAssertNil(q.current)
        XCTAssertTrue(q.queue.isEmpty)
        XCTAssertNil(q.finishCurrent())
    }

    /// Seeded fuzz: every queued id ends exactly once (shown and finished, expired, evicted, removed or removed by
    /// removeAll); at most 8 wait; texts are unique across the showing and waiting toasts; one shows at a time.
    func testFuzzEveryToastEndsExactlyOnce() {
        for seed in 1...40 {
            var rng = SeededGenerator(seed: UInt64(seed))
            var q = ToastQueueModel()
            var now = 0.0
            var live: Set<UInt64> = []
            var ended: Set<UInt64> = []
            func end(_ id: UInt64) {
                XCTAssertTrue(live.remove(id) != nil, "seed \(seed): \(id) ended twice or never started")
                XCTAssertFalse(ended.contains(id))
                ended.insert(id)
            }
            for _ in 0..<400 {
                now += Double(rng.next() % 3000) / 1000
                switch rng.next() % 6 {
                case 0, 1:
                    let text = "t\(rng.next() % 12)"
                    let suppressed = rng.next() % 5 == 0
                    let offer = q.offer(text, hasActions: rng.next() % 2 == 0, now: now, suppressed: { suppressed })
                    if case .queued(let id, let evicted) = offer {
                        XCTAssertFalse(live.contains(id))
                        live.insert(id)
                        if let evicted { end(evicted) }
                    }
                case 2:
                    let r = q.next(now: now, suppressed: { rng.next() % 4 == 0 })
                    r.expired.forEach(end)
                case 3:
                    if let e = q.finishCurrent() { end(e.id) }
                case 4:
                    if let id = q.queue.randomElementSeeded(&rng)?.id { XCTAssertTrue(q.removeQueued(id)); end(id) }
                default:
                    if rng.next() % 10 == 0 { q.removeAll().forEach(end) }
                }
                XCTAssertLessThanOrEqual(q.queue.count, ToastRules.maxQueued)
                let texts = q.queue.map(\.text) + (q.current.map { [$0.text] } ?? [])
                XCTAssertEqual(Set(texts).count, texts.count, "seed \(seed): duplicate text")
                let ids = Set(q.queue.map(\.id) + (q.current.map { [$0.id] } ?? []))
                XCTAssertEqual(ids, live, "seed \(seed): model and ledger disagree")
            }
            q.removeAll().forEach(end)
            XCTAssertTrue(live.isEmpty)
        }
    }
}

private extension Array {
    func randomElementSeeded(_ rng: inout SeededGenerator) -> Element? {
        isEmpty ? nil : self[Int(rng.next() % UInt64(count))]
    }
}
