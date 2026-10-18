import XCTest
@testable import SnapticKit

/// FIXES-R2 N1: the parent ↔ guard request/ack conversation over a fake transport. The
/// parent side is GuardAckTracker (what DisplayGuardClient runs), the guard side is
/// GuardSession (what GuardCore runs), and every line crosses as encoded JSON.
final class GuardLinkTests: XCTestCase {
    private let op = UndoOp(displayID: 2, fingerprint: "uuid:X", property: .mode,
                            restore: .mode(BLayout.mode(1920, 1080)), expected: .mode(BLayout.mode(1280, 720)))
    private let enableOp = UndoOp(displayID: 3, fingerprint: "uuid:Y", property: .enabled,
                                  restore: .bool(true), expected: .bool(false))

    /// Both pipes, both processes. A restarted guard is a new process with new pipes: what the
    /// old one never read is lost, and what it wrote is still read, tagged with its generation.
    private final class FakeLink {
        var tracker = GuardAckTracker<Int>()
        var session = GuardSession()
        var now = 0.0
        var outcomes: [Int: Bool] = [:]
        var toGuard: [(gen: UInt64, line: Data)] = []
        var toParent: [(gen: UInt64, line: Data)] = []
        var readyFrom: [UInt64] = []
        /// (generation, seq) of every acked request the guard actually handled.
        var handled: Set<[UInt64]> = []
        var seqOf: [Int: (gen: UInt64, seq: UInt64)] = [:]
        private var nextRequest = 0
        private let file: StaticString
        private let line: UInt

        init(file: StaticString = #filePath, line: UInt = #line) {
            self.file = file
            self.line = line
            _ = tracker.startGeneration()
        }

        @discardableResult
        func request(timeout: Double = GuardProtocol.ackTimeoutSeconds, _ make: (UInt64) -> GuardMessage) -> Int {
            let i = nextRequest
            nextRequest += 1
            let seq = tracker.begin(i, at: now, timeout: timeout)
            seqOf[i] = (tracker.generation, seq)
            let m = make(seq)
            XCTAssertEqual(GuardProtocol.ackSeq(m), seq, "the waiter is keyed by the seq actually sent", file: file, line: line)
            send(m)
            return i
        }

        func send(_ m: GuardMessage) {
            guard let data = GuardProtocol.encode(m) else { return XCTFail("encode", file: file, line: line) }
            toGuard.append((tracker.generation, data))
        }

        /// The guard reads up to `count` lines (only those sent to it, the current process).
        func guardReads(_ count: Int = .max) {
            var n = 0
            while n < count, !toGuard.isEmpty {
                let (gen, data) = toGuard.removeFirst()
                guard gen == tracker.generation else { continue }
                n += 1
                guard let m = GuardProtocol.decodeMessage(data) else {
                    XCTFail("the guard couldn't decode a parent message", file: file, line: line)
                    continue
                }
                if let seq = GuardProtocol.ackSeq(m) { handled.insert([gen, seq]) }
                for r in session.handle(m, at: now, canMonitorPanel: true) {
                    toParent.append((gen, GuardProtocol.encode(r)!))
                }
            }
        }

        func parentReads(_ count: Int = .max) {
            var n = 0
            while n < count, !toParent.isEmpty {
                n += 1
                let (gen, data) = toParent.removeFirst()
                switch GuardProtocol.decodeReply(data) {
                case .ack(let seq)?:
                    if let w = tracker.acknowledge(seq, from: gen) {
                        XCTAssertTrue(handled.contains([gen, seq]), "acked only what that guard handled", file: file, line: line)
                        resolve(w, true)
                    }
                case .ready?: readyFrom.append(gen)
                case .reverted?, .failed?: break
                case nil: XCTFail("the parent couldn't decode a guard reply", file: file, line: line)
                }
            }
        }

        func advance(_ seconds: Double) {
            now += seconds
            for w in tracker.expire(at: now) { resolve(w, false) }
        }

        func restartGuard() {
            for w in tracker.startGeneration() { resolve(w, false) }
            session = GuardSession()
        }

        func resolve(_ w: Int, _ ok: Bool) {
            XCTAssertNil(outcomes[w], "request \(w) resolved twice", file: file, line: line)
            outcomes[w] = ok
        }
    }

    // MARK: The N1 regression

    func testArmIsAcknowledgedUnderTheSeqItCarries() {
        let link = FakeLink()
        // Trial ids and seqs come from different counters; nothing may depend on them matching.
        for trial in [UInt64(42), 1, 2, 7] {
            let r = link.request { .armTrial(id: trial, seq: $0, undo: [self.op], deadlineSeconds: 30) }
            link.guardReads()
            link.parentReads()
            XCTAssertEqual(link.outcomes[r], true, "trial \(trial) armed")
            XCTAssertNotNil(link.session.trials[trial])
        }
        XCTAssertEqual(link.tracker.pendingCount, 0)
    }

    func testCommitIntentAndLongAreAcknowledged() {
        let link = FakeLink()
        link.request { .armTrial(id: 5, seq: $0, undo: [self.op], deadlineSeconds: 30) }
        let intent = link.request { .commitIntent(id: 5, seq: $0) }
        let long = link.request { .long(seq: $0, undo: [self.enableOp], restoreColorSync: true) }
        link.guardReads()
        link.parentReads()
        XCTAssertEqual(link.outcomes[intent], true)
        XCTAssertEqual(link.outcomes[long], true)
        XCTAssertEqual(link.session.trials[5]?.committing, true)
        XCTAssertEqual(link.session.longUndo, [enableOp])
        XCTAssertTrue(link.session.longColorSync)
    }

    /// Before N1 every message was acked with the trial id, so an `extend` sent before
    /// `commitIntent` could answer it. Now only the request's own ack does.
    func testMessagesWithoutAckNeverAnswerAWaiter() {
        let link = FakeLink()
        link.request { .armTrial(id: 5, seq: $0, undo: [self.op], deadlineSeconds: 30) }
        link.guardReads()
        link.parentReads()
        link.send(.extend(id: 5, seconds: 20))
        link.send(.busy(seconds: 3))
        link.send(.heartbeat(mainAgeMillis: 5))
        link.send(.classification([]))
        link.send(.impairment(dimToBlack: false, overlayBelowFloor: false))
        let intent = link.request { .commitIntent(id: 5, seq: $0) }
        link.guardReads(5)
        XCTAssertTrue(link.toParent.isEmpty, "none of those messages has a reply")
        link.parentReads()
        XCTAssertNil(link.outcomes[intent])
        link.guardReads()
        link.parentReads()
        XCTAssertEqual(link.outcomes[intent], true)
    }

    // MARK: Timeouts, late and duplicate acks

    func testTimeoutThenLateAck() {
        let link = FakeLink()
        let r = link.request { .armTrial(id: 1, seq: $0, undo: [self.op], deadlineSeconds: 30) }
        link.advance(0.5)
        XCTAssertNil(link.outcomes[r])
        link.advance(0.6)
        XCTAssertEqual(link.outcomes[r], false, "no ack within 1 s: refused")
        link.guardReads()
        link.parentReads()              // resolve() fails the test if this resolves it again
        XCTAssertEqual(link.outcomes[r], false)
        XCTAssertEqual(link.tracker.pendingCount, 0)
    }

    func testLateAckNeverAnswersANewerRequest() {
        let link = FakeLink()
        let a = link.request { .armTrial(id: 1, seq: $0, undo: [self.op], deadlineSeconds: 30) }
        link.advance(1.5)
        XCTAssertEqual(link.outcomes[a], false)
        let b = link.request { .armTrial(id: 1, seq: $0, undo: [self.op], deadlineSeconds: 30) }
        link.guardReads(1)                // only A's arm
        link.parentReads()
        XCTAssertNil(link.outcomes[b], "A's late ack must not resolve B (same trial id)")
        link.guardReads()
        link.parentReads()
        XCTAssertEqual(link.outcomes[b], true)
    }

    func testDuplicateAckIsIgnored() {
        let link = FakeLink()
        let a = link.request { .long(seq: $0, undo: [], restoreColorSync: false) }
        link.guardReads()
        link.toParent.append(link.toParent[0])
        let b = link.request { .long(seq: $0, undo: [self.enableOp], restoreColorSync: false) }
        link.parentReads()
        XCTAssertEqual(link.outcomes[a], true)
        XCTAssertNil(link.outcomes[b], "a duplicate of A's ack is not B's")
        link.guardReads()
        link.parentReads()
        XCTAssertEqual(link.outcomes[b], true)
    }

    func testIndividualTimersAndExpiry() {
        var t = GuardAckTracker<String>()
        _ = t.startGeneration()
        let a = t.begin("a", at: 0, timeout: 1)
        let b = t.begin("b", at: 0.5, timeout: 1)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(t.timeOut(a), "a")
        XCTAssertNil(t.timeOut(a), "a timer firing twice resolves nothing")
        XCTAssertNil(t.acknowledge(a, from: t.generation))
        XCTAssertEqual(t.expire(at: 1.2), [])
        XCTAssertEqual(t.expire(at: 1.5), ["b"])
        XCTAssertEqual(t.pendingCount, 0)
        XCTAssertNil(t.acknowledge(0, from: t.generation))
        XCTAssertNil(t.acknowledge(999, from: t.generation))
    }

    // MARK: Guard restart

    func testGuardRestartFailsPendingAndIgnoresTheOldGuard() {
        let link = FakeLink()
        link.send(.hello(protocolVersion: GuardProtocol.version, build: "t"))
        let a = link.request { .armTrial(id: 1, seq: $0, undo: [self.op], deadlineSeconds: 30) }
        let firstGen = link.tracker.generation
        link.guardReads()               // the old guard answered…
        link.restartGuard()             // …but died before the parent read it
        XCTAssertEqual(link.outcomes[a], false, "a guard restart fails what was waiting on the old one")
        link.parentReads()
        XCTAssertEqual(link.outcomes[a], false)
        XCTAssertEqual(link.readyFrom, [firstGen], "the reader sees the old ready, tagged with its generation")

        // A request the old guard never read is lost with its pipe and fails too.
        let lost = link.request { .long(seq: $0, undo: [], restoreColorSync: false) }
        let lostSeq = link.seqOf[lost]!.seq
        link.restartGuard()
        XCTAssertEqual(link.outcomes[lost], false)

        link.send(.hello(protocolVersion: GuardProtocol.version, build: "t"))
        let c = link.request { .armTrial(id: 1, seq: $0, undo: [self.op], deadlineSeconds: 30) }
        XCTAssertGreaterThan(link.seqOf[c]!.seq, lostSeq, "seqs are never reused across guards")
        // The old guard's ack for the same seq value can't match: different generation.
        XCTAssertNil(link.tracker.acknowledge(link.seqOf[c]!.seq, from: firstGen))
        link.guardReads()
        link.parentReads()
        XCTAssertEqual(link.outcomes[c], true)
        XCTAssertEqual(link.readyFrom.last, link.tracker.generation)
        XCTAssertNotNil(link.session.trials[1])
    }

    func testFailAllOnGuardLoss() {
        var t = GuardAckTracker<Int>()
        _ = t.startGeneration()
        let s1 = t.begin(1, at: 0, timeout: 1)
        _ = t.begin(2, at: 0, timeout: 1)
        XCTAssertEqual(t.failAll(), [1, 2])
        XCTAssertNil(t.acknowledge(s1, from: t.generation))
        XCTAssertEqual(t.startGeneration(), [])
        let seqs = (0..<100).map { _ in t.nextSeq() }
        XCTAssertEqual(Set(seqs).count, 100)
        XCTAssertFalse(seqs.contains(0))
    }

    // MARK: Every message, both sides

    func testEveryMessageGetsExactlyThePromisedReply() {
        let messages: [GuardMessage] = [
            .hello(protocolVersion: GuardProtocol.version, build: "x"),
            .armTrial(id: 9, seq: 11, undo: [op], deadlineSeconds: 30),
            .extend(id: 9, seconds: 20), .commitIntent(id: 9, seq: 12), .commit(id: 9), .disarm(id: 9),
            .long(seq: 13, undo: [enableOp], restoreColorSync: false),
            .impairment(dimToBlack: true, overlayBelowFloor: false), .busy(seconds: 2),
            .classification([GuardDisplayClass(id: 1, transport: .builtin, strong: true, weak: false)]),
            .heartbeat(mainAgeMillis: 3), .shutdown,
        ]
        var session = GuardSession()
        for m in messages {
            let wire = GuardProtocol.decodeMessage(GuardProtocol.encode(m)!)
            XCTAssertEqual(wire, m)
            let replies = session.handle(m, at: 10, canMonitorPanel: false)
            if case .hello = m {
                XCTAssertEqual(replies, [.ready(protocolVersion: GuardProtocol.version, canMonitorPanel: false)])
            } else if let seq = GuardProtocol.ackSeq(m) {
                XCTAssertEqual(replies, [.ack(seq: seq)], "\(m)")
            } else {
                XCTAssertEqual(replies, [], "\(m)")
            }
            for r in replies { XCTAssertEqual(GuardProtocol.decodeReply(GuardProtocol.encode(r)!), r) }
        }
        XCTAssertTrue(session.shutdownRequested)
    }

    func testGuardSessionTrialRules() {
        var s = GuardSession()
        _ = s.handle(.armTrial(id: 1, seq: 1, undo: [op], deadlineSeconds: 30), at: 100, canMonitorPanel: true)
        _ = s.handle(.armTrial(id: 2, seq: 2, undo: [op], deadlineSeconds: 30), at: 100, canMonitorPanel: true)
        XCTAssertTrue(s.hasArmedState)
        XCTAssertEqual(s.dueTrials(at: 129), [])
        XCTAssertEqual(s.dueTrials(at: 130), [1, 2])
        // N8: each apply stage pushes the deadline out; never shortened.
        _ = s.handle(.extend(id: 1, seconds: 18), at: 125, canMonitorPanel: true)
        XCTAssertEqual(s.trials[1]?.deadline, 143)
        _ = s.handle(.extend(id: 1, seconds: 1), at: 126, canMonitorPanel: true)
        XCTAssertEqual(s.trials[1]?.deadline, 143)
        XCTAssertEqual(s.dueTrials(at: 131), [2])
        // Keep chosen: no longer reverted by deadline or hang; extend ignored.
        _ = s.handle(.commitIntent(id: 1, seq: 3), at: 131, canMonitorPanel: true)
        _ = s.handle(.extend(id: 1, seconds: 80), at: 131, canMonitorPanel: true)
        XCTAssertEqual(s.trials[1]?.deadline, 143)
        XCTAssertEqual(s.dueTrials(at: 200), [2])
        XCTAssertEqual(s.revertibleTrials, [2])
        XCTAssertEqual(s.takeTrial(2)?.undo, [op])
        XCTAssertNil(s.takeTrial(2))
        s.pruneCommitting(at: 143 + GuardSession.committingGraceSeconds - 1)
        XCTAssertNotNil(s.trials[1])
        s.pruneCommitting(at: 143 + GuardSession.committingGraceSeconds)
        XCTAssertNil(s.trials[1])
        XCTAssertFalse(s.hasArmedState)
        // commit / disarm end a trial without a reply.
        _ = s.handle(.armTrial(id: 3, seq: 4, undo: [op], deadlineSeconds: 30), at: 0, canMonitorPanel: true)
        XCTAssertEqual(s.handle(.disarm(id: 3), at: 1, canMonitorPanel: true), [])
        XCTAssertNil(s.trials[3])
        XCTAssertEqual(s.handle(.commit(id: 77), at: 1, canMonitorPanel: true), [], "unknown trial: nothing to do")
    }

    func testGuardSessionLongAndImpairment() {
        var s = GuardSession()
        XCTAssertFalse(s.isImpairing)
        _ = s.handle(.long(seq: 1, undo: [op], restoreColorSync: false), at: 0, canMonitorPanel: true)
        XCTAssertFalse(s.isImpairing, "a mode op alone doesn't impair visibility")
        XCTAssertTrue(s.hasArmedState)
        _ = s.handle(.long(seq: 2, undo: [enableOp], restoreColorSync: false), at: 0, canMonitorPanel: true)
        XCTAssertTrue(s.isImpairing)
        _ = s.handle(.long(seq: 3, undo: [], restoreColorSync: false), at: 0, canMonitorPanel: true)
        XCTAssertFalse(s.hasArmedState)
        _ = s.handle(.impairment(dimToBlack: false, overlayBelowFloor: true), at: 0, canMonitorPanel: true)
        XCTAssertTrue(s.isImpairing)
        _ = s.handle(.heartbeat(mainAgeMillis: 0), at: 50, canMonitorPanel: true)
        XCTAssertNil(s.hang.hangSeconds(at: 51))
        XCTAssertNotNil(s.hang.hangSeconds(at: 61))
    }

    // MARK: Fuzz

    /// Random interleavings of requests, reads, drops, duplicates, delays and restarts: every
    /// request resolves exactly once, an ack only ever resolves the request the guard handled
    /// (FakeLink asserts both), and nothing stays pending once time runs out.
    func testFuzzConversation() {
        var rng = SeededGenerator(seed: 0x6B1D)
        for _ in 0..<300 {
            let link = FakeLink()
            var trial: UInt64 = 0
            for _ in 0..<60 {
                switch rng.next() % 10 {
                case 0, 1:
                    trial += 1
                    let id = trial
                    link.request { .armTrial(id: id, seq: $0, undo: [self.op], deadlineSeconds: 30) }
                case 2:
                    let id = trial
                    link.request { .commitIntent(id: id, seq: $0) }
                case 3:
                    link.request { .long(seq: $0, undo: [], restoreColorSync: rng.next() % 2 == 0) }
                case 4:
                    link.send(.extend(id: trial, seconds: 10))
                case 5:
                    link.guardReads(Int(rng.next() % 3) + 1)
                case 6:
                    link.parentReads(Int(rng.next() % 3) + 1)
                case 7:
                    if !link.toParent.isEmpty {
                        let i = Int(rng.next() % UInt64(link.toParent.count))
                        if rng.next() % 2 == 0 { link.toParent.append(link.toParent[i]) } else { link.toParent.remove(at: i) }
                    }
                case 8:
                    link.advance(Double(rng.next() % 8) / 10)
                default:
                    if rng.next() % 4 == 0 { link.restartGuard() } else { link.guardReads(); link.parentReads() }
                }
            }
            link.guardReads()
            link.parentReads()
            link.advance(GuardProtocol.ackTimeoutSeconds + 0.01)
            XCTAssertEqual(link.tracker.pendingCount, 0)
            XCTAssertEqual(link.outcomes.count, link.seqOf.count, "every request resolved")
            // An acked request was handled by the guard process it was sent to.
            for (i, ok) in link.outcomes where ok {
                let s = link.seqOf[i]!
                XCTAssertTrue(link.handled.contains([s.gen, s.seq]))
            }
        }
    }
}
