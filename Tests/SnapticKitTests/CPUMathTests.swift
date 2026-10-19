import XCTest
@testable import SnapticKit

/// CPUMath (PLAN 0.3 §2.8, §6.6, R5-4).
final class CPUMathTests: XCTestCase {
    private let appleSilicon = CPUTimebase(numer: 125, denom: 3)
    private let intel = CPUTimebase.identity

    /// Mach ticks for `seconds` of CPU on a timebase (the inverse of `nanos`).
    private func ticks(_ seconds: Double, _ tb: CPUTimebase) -> UInt64 {
        UInt64(seconds * 1e9 * Double(tb.denom) / Double(tb.numer))
    }

    // MARK: load

    func testLoadFromTickDeltas() throws {
        let a = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let b = CPUTicks(user: 200, system: 100, idle: 1_000, nice: 100)
        XCTAssertEqual(try XCTUnwrap(CPUMath.load(prev: a, now: b)), 50, accuracy: 1e-9)
        let idle = CPUTicks(user: 100, system: 50, idle: 1_800, nice: 50)
        XCTAssertEqual(try XCTUnwrap(CPUMath.load(prev: a, now: idle)), 0, accuracy: 1e-9)
        let busy = CPUTicks(user: 1_100, system: 50, idle: 800, nice: 50)
        XCTAssertEqual(try XCTUnwrap(CPUMath.load(prev: a, now: busy)), 100, accuracy: 1e-9)
    }

    func testLoadNilWhenNoTicksElapsed() {
        let a = CPUTicks(user: 1, system: 2, idle: 3, nice: 4)
        XCTAssertNil(CPUMath.load(prev: a, now: a))
    }

    func testLoadHandlesUInt32Wraparound() throws {
        let a = CPUTicks(user: UInt32.max - 9, system: UInt32.max, idle: UInt32.max - 29, nice: 0)
        // user +20 (wraps), system +10 (wraps), idle +70 (wraps), nice +0.
        let b = CPUTicks(user: 10, system: 9, idle: 40, nice: 0)
        XCTAssertEqual(try XCTUnwrap(CPUMath.load(prev: a, now: b)), 30, accuracy: 1e-9)
    }

    func testSingleThreadOnTwelveCoresIsAboutEightPercent() throws {
        // One busy core out of 12 for 5 s at 100 ticks/s per core.
        let a = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let b = CPUTicks(user: 500, system: 0, idle: 5_500, nice: 0)
        XCTAssertEqual(try XCTUnwrap(CPUMath.load(prev: a, now: b)), 100.0 / 12, accuracy: 1e-9)
    }

    func testAverageSkipsUnknowns() {
        XCTAssertNil(CPUMath.average([]))
        XCTAssertNil(CPUMath.average([nil, nil]))
        XCTAssertEqual(CPUMath.average([10, nil, 30]), 20)
        XCTAssertEqual(CPUMath.average([Double.nan, 40]), 40)
    }

    // MARK: Timebase

    func testTimebaseConversions() {
        XCTAssertEqual(appleSilicon.nanos(3), 125)
        XCTAssertEqual(appleSilicon.nanos(24_000_000), 1_000_000_000)   // 24 MHz: one second
        XCTAssertEqual(intel.nanos(123_456), 123_456)
        XCTAssertEqual(CPUTimebase(numer: 0, denom: 0).nanos(42), 42)   // garbage reads as 1/1
    }

    func testTimebaseNeverTraps() {
        XCTAssertEqual(appleSilicon.nanos(UInt64.max), UInt64.max)          // saturates
        XCTAssertEqual(CPUTimebase(numer: 1, denom: 3).nanos(UInt64.max), UInt64.max / 3)
        XCTAssertEqual(CPUTimebase(numer: UInt32.max, denom: UInt32.max).nanos(UInt64.max), UInt64.max)
        var rng = SeededGenerator(seed: 0xC0FFEE)
        for _ in 0..<5_000 {
            let tb = CPUTimebase(numer: UInt32(truncatingIfNeeded: rng.next()), denom: UInt32(truncatingIfNeeded: rng.next()))
            let t = rng.next() >> (rng.next() % 64)
            let n = tb.nanos(t)
            if tb.numer == tb.denom, tb.numer != 0 { XCTAssertEqual(n, t) }
        }
    }

    // MARK: processPercent

    func testBusyAppleSiliconProcessReadsAboutOneHundredPercent() throws {
        // A process that burned 5 s of CPU in 5 s on Apple silicon: ≈ 100%, not ≈ 2.4% (raw ticks read as ns).
        let p = try XCTUnwrap(CPUMath.processPercent(prevTicks: 0, nowTicks: ticks(5, appleSilicon), seconds: 5,
                                                     timebase: appleSilicon))
        XCTAssertEqual(p, 100, accuracy: 0.01)
        let wrong = Double(ticks(5, appleSilicon)) / 1e9 / 5 * 100
        XCTAssertLessThan(wrong, 3)
    }

    func testProcessPercentEdges() throws {
        XCTAssertEqual(try XCTUnwrap(CPUMath.processPercent(prevTicks: 10, nowTicks: 5, seconds: 5, timebase: intel)), 0)
        XCTAssertNil(CPUMath.processPercent(prevTicks: 0, nowTicks: 5, seconds: 0, timebase: intel))
        XCTAssertNil(CPUMath.processPercent(prevTicks: 0, nowTicks: 5, seconds: -1, timebase: intel))
        XCTAssertNil(CPUMath.processPercent(prevTicks: 0, nowTicks: 5, seconds: .nan, timebase: intel))
        XCTAssertNil(CPUMath.processPercent(prevTicks: 0, nowTicks: 5, seconds: .infinity, timebase: intel))
        // Two cores' worth reads 200.
        let two = try XCTUnwrap(CPUMath.processPercent(prevTicks: 0, nowTicks: 10_000_000_000, seconds: 5, timebase: intel))
        XCTAssertEqual(two, 200, accuracy: 1e-9)
    }

    // MARK: window

    private func s(_ pid: Int32, _ start: UInt64, _ cpuSeconds: Double, _ tb: CPUTimebase? = nil) -> ProcessCPUSample {
        ProcessCPUSample(pid: pid, startAbs: start, cpuTicks: ticks(cpuSeconds, tb ?? appleSilicon))
    }

    func testWindowTakesTheBusiestProcess() throws {
        let prev = [s(10, 100, 1), s(11, 100, 3)]
        let now = [s(10, 100, 1.5), s(11, 100, 7)]
        let w = CPUMath.window(prev: prev, now: now, windowStartAbs: 1_000, seconds: 5, timebase: appleSilicon)
        XCTAssertEqual(try XCTUnwrap(w.top), 80, accuracy: 0.01)
        XCTAssertEqual(w.newProcesses, 0)
    }

    func testFirstSeenInsideTheWindowCountsItsWholeTime() throws {
        let prev = [s(10, 100, 1)]
        let now = [s(10, 100, 1), s(20, 1_500, 4)]
        let w = CPUMath.window(prev: prev, now: now, windowStartAbs: 1_000, seconds: 5, timebase: appleSilicon)
        XCTAssertEqual(try XCTUnwrap(w.top), 80, accuracy: 0.01)
        XCTAssertEqual(w.newProcesses, 1)
    }

    func testFirstSeenButOlderThanTheWindowCountsNothing() throws {
        let now = [s(30, 50, 1_000)]   // started before the window: its lifetime CPU is not this window's
        let w = CPUMath.window(prev: [], now: now, windowStartAbs: 1_000, seconds: 5, timebase: appleSilicon)
        XCTAssertEqual(try XCTUnwrap(w.top), 0)
        XCTAssertEqual(w.newProcesses, 0)
    }

    func testReusedPidIsANewProcess() throws {
        let prev = [s(10, 100, 50)]
        let now = [s(10, 2_000, 2)]   // same pid, new start: not a counter that went down
        let w = CPUMath.window(prev: prev, now: now, windowStartAbs: 1_000, seconds: 5, timebase: appleSilicon)
        XCTAssertEqual(try XCTUnwrap(w.top), 40, accuracy: 0.01)
        XCTAssertEqual(w.newProcesses, 1)
    }

    func testCounterThatWentDownReadsZero() throws {
        let w = CPUMath.window(prev: [s(10, 100, 9)], now: [s(10, 100, 2)], windowStartAbs: 1_000, seconds: 5,
                               timebase: appleSilicon)
        XCTAssertEqual(try XCTUnwrap(w.top), 0)
    }

    func testChurnCountsEveryFirstSeenProcessInTheWindow() {
        let now = (0..<5).map { s(Int32(100 + $0), 1_500, 0.1) } + [s(1, 10, 0)]
        let w = CPUMath.window(prev: [s(1, 10, 0)], now: now, windowStartAbs: 1_000, seconds: 5, timebase: appleSilicon)
        XCTAssertEqual(w.newProcesses, 5)
    }

    func testUnknownWindows() {
        XCTAssertNil(CPUMath.window(prev: [s(1, 1, 1)], now: [], windowStartAbs: 0, seconds: 5, timebase: intel).top)
        XCTAssertNil(CPUMath.window(prev: [], now: [s(1, 1, 1)], windowStartAbs: 0, seconds: 0, timebase: intel).top)
        XCTAssertNil(CPUMath.window(prev: [], now: [s(1, 1, 1)], windowStartAbs: 0, seconds: .nan, timebase: intel).top)
    }

    func testDuplicatePidsKeepTheFirstAndNeverTrap() throws {
        let prev = [s(10, 100, 1), s(10, 100, 0)]
        let now = [s(10, 100, 2), s(10, 100, 50)]
        let w = CPUMath.window(prev: prev, now: now, windowStartAbs: 1_000, seconds: 5, timebase: appleSilicon)
        XCTAssertEqual(try XCTUnwrap(w.top), 20, accuracy: 0.01)
    }

    /// R5-4: a long-lived parent (make, a shell) whose reaped-children time grows 5 s per 5 s window reads ≈ 100%.
    func testLongLivedParentWithGrowingChildTimeReadsBusy() throws {
        var prev = [s(500, 10, 0)]
        for window in 1...6 {
            let now = [s(500, 10, Double(window) * 5)]
            let w = CPUMath.window(prev: prev, now: now, windowStartAbs: UInt64(window) * 1_000, seconds: 5,
                                   timebase: appleSilicon)
            XCTAssertEqual(try XCTUnwrap(w.top), 100, accuracy: 0.01)
            XCTAssertEqual(w.newProcesses, 0)
            prev = now
        }
    }

    /// R5-4: `make -j1` with 1–3 s compiles. No child is alive at either sample instant; the parent's child time grows
    /// 2 s per window and no new process is seen: the top process still reads 40% (busy at the 10% floor of
    /// `topProcessPercent`), so the session stays.
    func testMakeJ1FixtureStaysBusyThroughChildTime() throws {
        var parentCPU = 0.0
        var prev = [s(600, 10, 0), s(601, 10, 0)]   // make and the shell, both long-lived
        for window in 1...12 {
            parentCPU += 2
            let now = [s(600, 10, parentCPU), s(601, 10, 0)]
            let w = CPUMath.window(prev: prev, now: now, windowStartAbs: UInt64(window) * 1_000, seconds: 5,
                                   timebase: appleSilicon)
            XCTAssertEqual(try XCTUnwrap(w.top), 40, accuracy: 0.01)
            XCTAssertEqual(w.newProcesses, 0)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(w.top), 10)
            prev = now
        }
    }

    func testSeededFuzzNeverTraps() {
        var rng = SeededGenerator(seed: 0xD15C0)
        func sample() -> [ProcessCPUSample] {
            (0..<Int(rng.next() % 40)).map { _ in
                ProcessCPUSample(pid: Int32(truncatingIfNeeded: rng.next() % 64), startAbs: rng.next() % 4,
                                 cpuTicks: rng.next() >> (rng.next() % 64))
            }
        }
        let seconds: [Double] = [5, 0, -1, .nan, .infinity, 1e-300, 1e300]
        for _ in 0..<5_000 {
            let tb = CPUTimebase(numer: UInt32(truncatingIfNeeded: rng.next() % 200), denom: UInt32(truncatingIfNeeded: rng.next() % 5))
            let w = CPUMath.window(prev: sample(), now: sample(), windowStartAbs: rng.next() % 4,
                                   seconds: seconds[Int(rng.next() % UInt64(seconds.count))], timebase: tb)
            if let top = w.top { XCTAssertGreaterThanOrEqual(top, 0) }
            XCTAssertGreaterThanOrEqual(w.newProcesses, 0)
            let a = CPUTicks(user: UInt32(truncatingIfNeeded: rng.next()), system: UInt32(truncatingIfNeeded: rng.next()),
                             idle: UInt32(truncatingIfNeeded: rng.next()), nice: UInt32(truncatingIfNeeded: rng.next()))
            let b = CPUTicks(user: UInt32(truncatingIfNeeded: rng.next()), system: UInt32(truncatingIfNeeded: rng.next()),
                             idle: UInt32(truncatingIfNeeded: rng.next()), nice: UInt32(truncatingIfNeeded: rng.next()))
            if let load = CPUMath.load(prev: a, now: b) { XCTAssertTrue((0...100).contains(load)) }
        }
    }
}
