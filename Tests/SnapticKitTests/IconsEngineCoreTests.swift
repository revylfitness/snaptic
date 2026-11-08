import XCTest
@testable import SnapticKit

// 0.4 K3 (§4.2, §4.4, §4.11). The engine core over fake ports. `IconsEngineHiddenBarTests` ports Hidden Bar's
// `StatusBarControllerTests` as behaviour (ten Native cases, one Length case). Where the plan differs, the plan wins:
// an expand during an activation delivers `.superseded` (HB delivers nothing), a collapse while restricted reads the
// allowed bundles only (HB doesn't read), and Length writes `⋮` = 0 while collapsed (HB leaves it).

private let own = "app.snaptic.Snaptic"
private let screenFrame = IconsRect(x: 0, y: 0, width: 1728, height: 1117)
private let hideL: Double = 3456

// MARK: - Fakes

private final class FakeItems: IconsItemsPort {
    var frames: [IconsItemRole: IconsRect]
    var lengths: [IconsItemRole: Double]
    var hidden: Set<IconsItemRole> = []
    var rejectLengths = false
    private(set) var writes: [IconsLengthWrite] = []

    init(separator: Double, alwaysHidden: Double?) {
        frames = [.toggle: IconsRect(x: 1340, y: 0, width: 24, height: 24)]
        lengths = [.toggle: 24]
        frames[.separator] = IconsRect(x: 1320 - separator, y: 0, width: separator, height: 24)
        lengths[.separator] = separator
        if let alwaysHidden {
            frames[.alwaysHidden] = IconsRect(x: 1020 - alwaysHidden, y: 0, width: alwaysHidden, height: 24)
            lengths[.alwaysHidden] = alwaysHidden
        }
    }

    func frame(of role: IconsItemRole) -> IconsRect? { frames[role] }
    func length(of role: IconsItemRole) -> Double? { lengths[role] }
    func isVisible(_ role: IconsItemRole) -> Bool { !hidden.contains(role) && frames[role] != nil }

    func setLength(_ length: Double, for role: IconsItemRole) {
        writes.append(IconsLengthWrite(role, length))
        lengths[role] = length
        guard !rejectLengths, let old = frames[role] else { return }
        // Status items grow away from the shown side: the line (maxX in LTR) stays.
        frames[role] = IconsRect(x: old.maxX - length, y: old.y, width: length, height: old.height)
    }

    func clearWrites() { writes = [] }
}

private final class FakeVisibility: IconsVisibilityPort {
    struct Request: Equatable {
        var token: UInt64
        var systemItems: Range<Int>
        var bundles: [String]
    }

    var isAvailable = true
    private(set) var requests: [Request] = []
    private(set) var active: [UInt64: [String]] = [:]
    private(set) var invalidated: [UInt64] = []
    private(set) var invalidateAllCount = 0
    /// Active assertion count after every change, to catch a flash (it reaching 0 between two restrictions).
    private(set) var activeHistory: [Int] = []
    private var completions: [(UInt64, (Result<Void, IconsActivationError>) -> Void)] = []
    /// Completes every activation at once with this result.
    var autoResult: Result<Void, IconsActivationError>?

    var pendingCount: Int { completions.count }
    var pendingTokens: [UInt64] { completions.map(\.0) }

    func activate(systemItems: Range<Int>, bundles: [String], token: UInt64,
                  completion: @escaping (Result<Void, IconsActivationError>) -> Void) {
        requests.append(Request(token: token, systemItems: systemItems, bundles: bundles))
        if let autoResult {
            deliver(token, autoResult, completion)
        } else {
            completions.append((token, completion))
        }
    }

    func invalidate(token: UInt64) {
        invalidated.append(token)
        if active.removeValue(forKey: token) != nil { activeHistory.append(active.count) }
    }

    func invalidateAll() {
        invalidateAllCount += 1
        if !active.isEmpty {
            active.removeAll()
            activeHistory.append(0)
        }
    }

    /// Completes the oldest (or newest) outstanding activation.
    func complete(lifo: Bool = false, _ result: Result<Void, IconsActivationError> = .success(())) {
        guard !completions.isEmpty else { return XCTFail("no activation outstanding") }
        let (token, completion) = lifo ? completions.removeLast() : completions.removeFirst()
        deliver(token, result, completion)
    }

    /// Hands back the completion without running it, to call it again (duplicates).
    func takeCompletion() -> (Result<Void, IconsActivationError>) -> Void {
        let (token, completion) = completions.removeFirst()
        return { [weak self] result in self?.deliver(token, result, completion) }
    }

    private func deliver(_ token: UInt64, _ result: Result<Void, IconsActivationError>,
                         _ completion: (Result<Void, IconsActivationError>) -> Void) {
        if case .success = result, active[token] == nil, let request = requests.last(where: { $0.token == token }) {
            active[token] = request.bundles
            activeHistory.append(active.count)
        }
        completion(result)
    }

    var flashed: Bool {
        // Restricted, then nothing, then restricted again.
        guard let first = activeHistory.firstIndex(where: { $0 > 0 }) else { return false }
        let rest = activeHistory[first...]
        guard let zero = rest.firstIndex(of: 0) else { return false }
        return rest[zero...].contains { $0 > 0 }
    }
}

private final class FakeInventory: IconsInventoryPort {
    var inventory: IconsInventory
    /// Answers reads at once instead of queueing them.
    var immediate = false
    var systemAfter: Set<String>?
    private(set) var scopes: [IconsReadScope] = []
    private(set) var systemReads = 0
    private var pending: [(IconsInventory) -> Void] = []

    init(_ inventory: IconsInventory) {
        self.inventory = inventory
        systemAfter = inventory.systemIdentifiers
    }

    var pendingCount: Int { pending.count }

    func read(scope: IconsReadScope, completion: @escaping (IconsInventory) -> Void) {
        scopes.append(scope)
        if immediate { completion(inventory) } else { pending.append(completion) }
    }

    func readSystemIdentifiers(completion: @escaping (Set<String>?) -> Void) {
        systemReads += 1
        completion(systemAfter)
    }

    func respond(lifo: Bool = false, with read: IconsInventory? = nil) {
        guard !pending.isEmpty else { return XCTFail("no read outstanding") }
        let completion = lifo ? pending.removeLast() : pending.removeFirst()
        completion(read ?? inventory)
    }
}

private final class FakeScheduler: IconsSchedulerPort {
    private final class Task: IconsCancellable {
        let at: Double
        let seq: Int
        let work: () -> Void
        var cancelled = false

        init(at: Double, seq: Int, work: @escaping () -> Void) {
            self.at = at
            self.seq = seq
            self.work = work
        }

        func cancel() { cancelled = true }
    }

    private(set) var now: Double = 0
    private var tasks: [Task] = []
    private var seq = 0

    var pendingCount: Int { tasks.filter { !$0.cancelled }.count }

    func after(_ seconds: Double, _ work: @escaping () -> Void) -> IconsCancellable {
        seq += 1
        let task = Task(at: now + max(0, seconds), seq: seq, work: work)
        tasks.append(task)
        return task
    }

    func advance(_ seconds: Double) {
        let end = now + seconds
        while let next = nextTask(), next.at <= end {
            runTask(next)
        }
        now = end
    }

    func tick() { advance(0) }

    /// Runs the earliest live task, whenever it's due.
    func runNext() {
        guard let next = nextTask() else { return }
        runTask(next)
    }

    private func nextTask() -> Task? {
        tasks.removeAll { $0.cancelled }
        return tasks.min { ($0.at, $0.seq) < ($1.at, $1.seq) }
    }

    private func runTask(_ task: Task) {
        tasks.removeAll { $0 === task }
        now = max(now, task.at)
        task.work()
    }
}

private final class FakeHost: IconsEngineHost {
    var refusal: IconsRefusal?
    var killSwitch = false
    var screenList = [IconsScreen(frame: screenFrame)]
    var skip = IconsSkipRules(ownPID: 1, ownBundlePath: "/Applications/Snaptic.app")
    private(set) var inFlight: [Bool] = []
    private(set) var disabledBuilds = 0
    private(set) var counters: [IconsCounter] = []
    private(set) var states: [IconsEngineState] = []
    private(set) var layouts: [IconsLayout] = []
    private(set) var refusalAsks = 0

    func collapseRefusal(engine: IconsEngineKind) -> IconsRefusal? {
        refusalAsks += 1
        return refusal
    }

    func killSwitchOn(engine: IconsEngineKind) -> Bool { killSwitch }
    func screens() -> [IconsScreen] { screenList }
    func skipRules() -> IconsSkipRules { skip }
    func setActivationInFlight(_ inFlight: Bool) { self.inFlight.append(inFlight) }
    func disableNativeOnThisBuild() { disabledBuilds += 1 }
    func count(_ counter: IconsCounter) { counters.append(counter) }
    func engineStateChanged(_ state: IconsEngineState) { states.append(state) }
    func layoutRead(_ layout: IconsLayout) { layouts.append(layout) }

    var markerSet: Bool { inFlight.last ?? false }
    func count(of counter: IconsCounter) -> Int { counters.filter { $0 == counter }.count }
}

// MARK: - Fixtures

private func extra(_ pid: Int32, _ bundle: String?, _ x: Double, index: Int = 0) -> IconsExtra {
    IconsExtra(pid: pid, bundleID: bundle, index: index, frame: IconsRect(x: x, y: 0, width: 24, height: 24))
}

private func app(_ bundle: String, _ x: Double, pid: Int32, path: String? = nil) -> IconsAppRead {
    IconsAppRead(pid: pid, bundleID: bundle, bundlePath: path ?? "/Applications/\(bundle).app", result: .ok,
                 extras: [extra(pid, bundle, x)])
}

private let systemIDs: Set<String> = ["com.apple.menuextra.clock", "com.apple.menuextra.battery",
                                      "com.apple.menuextra.now-playing"]

/// ⋮ at 1000, `|` at 1300 (Length), the arrow at 1340: `com.always` beyond ⋮, `com.hidden` between, `com.visible`
/// right of the arrow, plus Snaptic itself, a system owner and MenuBarAgent.
private func standardInventory(always: Bool = true, readAt: Double = 100) -> IconsInventory {
    var apps = [
        app("com.hidden", 1100, pid: 20),
        app("com.visible", 1400, pid: 30),
        app(own, 1450, pid: 1, path: "/Applications/Snaptic.app"),
        app("com.apple.TextInputMenuAgent", 1500, pid: 40,
            path: "/System/Library/CoreServices/TextInputMenuAgent.app"),
        app(IconsSkipRules.menuBarAgentID, 1600, pid: 50, path: "/System/Library/CoreServices/MenuBarAgent.app"),
    ]
    if always { apps.insert(app("com.always", 900, pid: 10), at: 0) }
    return IconsInventory(apps: apps, readAt: readAt, systemIdentifiers: systemIDs)
}

private let collapseList = ["app.snaptic.Snaptic", "com.apple.TextInputMenuAgent", "com.visible"]
private let plainList = ["app.snaptic.Snaptic", "com.apple.TextInputMenuAgent", "com.hidden", "com.visible"]

private final class Rig {
    let items: FakeItems
    let visibility: FakeVisibility
    let inventory: FakeInventory
    let scheduler = FakeScheduler()
    let host = FakeHost()
    let core: IconsEngineCore
    private(set) var results: [[IconsCollapseResult]] = []

    init(_ engine: IconsEngineKind, alwaysHidden: Bool = false, dividers: Bool = true,
         inventory read: IconsInventory = standardInventory(), cache: IconsLayoutCache? = nil,
         inputs: ((inout IconsEngineInputs) -> Void)? = nil) {
        items = FakeItems(separator: 20, alwaysHidden: alwaysHidden ? 20 : nil)
        visibility = FakeVisibility()
        inventory = FakeInventory(read)
        var i = IconsEngineInputs(ownBundleID: own, alwaysHidden: alwaysHidden, dividers: dividers)
        inputs?(&i)
        core = IconsEngineCore(engine: engine, items: items, visibility: engine == .native ? visibility : nil,
                               inventory: inventory, scheduler: scheduler, host: host, inputs: i, cache: cache)
    }

    /// Starts and answers the first read (and, with Always Hidden on, the plain activation).
    @discardableResult
    func started() -> Rig {
        core.start()
        reads()
        while visibility.pendingCount > 0 { visibility.complete() }
        return self
    }

    /// Calls collapse and records every result it gets, at its index.
    @discardableResult
    func collapse() -> Int {
        let index = results.count
        results.append([])
        core.collapse { [unowned self] result in self.results[index].append(result) }
        return index
    }

    /// Collapses and settles the read and the activation.
    @discardableResult
    func collapsed() -> Rig {
        collapse()
        reads()
        while visibility.pendingCount > 0 { visibility.complete() }
        scheduler.tick()
        return self
    }

    func result(_ index: Int) -> [IconsCollapseResult] { results[index] }

    /// Answers every outstanding read, oldest first.
    func reads(with read: IconsInventory? = nil) {
        while inventory.pendingCount > 0 { inventory.respond(with: read) }
    }

    var inputs: IconsEngineInputs { core.inputs }

    func update(_ change: (inout IconsEngineInputs) -> Void) {
        var i = core.inputs
        change(&i)
        core.update(i)
    }

    /// Answers everything outstanding until nothing is left: reads, activations, then timers.
    func settle(lifo: Bool) {
        for _ in 0..<200 {
            if inventory.pendingCount > 0 {
                inventory.respond(lifo: lifo)
            } else if visibility.pendingCount > 0 {
                visibility.complete(lifo: lifo)
            } else if scheduler.pendingCount > 0 {
                scheduler.runNext()
            } else {
                return
            }
        }
        XCTFail("didn't settle")
    }
}

// MARK: - Lengths table

final class IconsLengthTableTests: XCTestCase {
    func testHideLength() {
        XCTAssertEqual(IconsLengthTable.hideLength(widestScreen: 1728), 3456)
        XCTAssertEqual(IconsLengthTable.hideLength(widestScreen: 200), 500)
        XCTAssertEqual(IconsLengthTable.hideLength(widestScreen: 6016), 10_000)
        XCTAssertEqual(IconsLengthTable.hideLength(widestScreen: nil), 1728)
        XCTAssertEqual(IconsLengthTable.hideLength(widestScreen: 0), 1728)
        XCTAssertEqual(IconsLengthTable.hideLength(widestScreen: .nan), 1728)
        let screens = [IconsScreen(frame: screenFrame),
                       IconsScreen(frame: IconsRect(x: 1728, y: 0, width: 2560, height: 1440))]
        XCTAssertEqual(IconsLengthTable.hideLength(screens: screens), 5120)
        XCTAssertEqual(IconsLengthTable.hideLength(screens: []), 1728)
    }

    /// Every row of §4.2.4: 2 engines × 3 visuals × Always Hidden (off, on unplaced, on placed) × dividers.
    func testTruthTable() {
        let visuals: [IconsVisual] = [.collapsed, .expanded(.plain), .expanded(.all)]
        for engine in IconsEngineKind.allCases {
            for visual in visuals {
                for (ah, placed) in [(false, false), (true, false), (true, true)] {
                    for dividers in [true, false] {
                        let plan = IconsLengthTable.plan(engine: engine, visual: visual, alwaysHidden: ah,
                                                         alwaysHiddenPlaced: placed, dividers: dividers,
                                                         hideLength: 3000)
                        let shown: Double = dividers ? 20 : 0
                        let label = "\(engine) \(visual) ah=\(ah) placed=\(placed) dividers=\(dividers)"
                        let separator: Double
                        let mark: Double
                        switch (engine, visual) {
                        case (.native, .collapsed): (separator, mark) = (0, 0)
                        case (.native, _): (separator, mark) = (0, shown)
                        case (.length, .collapsed): (separator, mark) = (3000, 0)
                        case (.length, .expanded(.plain)): (separator, mark) = (shown, placed ? 3000 : shown)
                        case (.length, .expanded(.all)): (separator, mark) = (shown, shown)
                        }
                        XCTAssertEqual(plan.separator, separator, label)
                        XCTAssertEqual(plan.alwaysHidden, ah ? mark : nil, label)
                    }
                }
            }
        }
    }

    /// Every ordered pair of Length visuals: the writes land on the target, widen before they narrow, and skip
    /// lengths that are already right.
    func testTransitionsWidenFirst() {
        let visuals: [IconsVisual] = [.collapsed, .expanded(.plain), .expanded(.all)]
        for dividers in [true, false] {
            for from in visuals {
                for to in visuals {
                    let plan = { (v: IconsVisual) in
                        IconsLengthTable.plan(engine: .length, visual: v, alwaysHidden: true, alwaysHiddenPlaced: true,
                                              dividers: dividers, hideLength: hideL)
                    }
                    let start = plan(from)
                    let target = plan(to)
                    let writes = IconsLengthTable.writes(separator: start.separator, alwaysHidden: start.alwaysHidden,
                                                         to: target)
                    var lengths: [IconsItemRole: Double] = [.separator: start.separator,
                                                            .alwaysHidden: start.alwaysHidden ?? 0]
                    var narrowed = false
                    for write in writes {
                        let before = lengths[write.role] ?? 0
                        XCTAssertNotEqual(before, write.length, "no-op write \(from)→\(to)")
                        if write.length < before { narrowed = true } else {
                            XCTAssertFalse(narrowed, "widened after narrowing \(from)→\(to)")
                        }
                        lengths[write.role] = write.length
                    }
                    XCTAssertEqual(lengths[.separator], target.separator, "\(from)→\(to)")
                    XCTAssertEqual(lengths[.alwaysHidden], target.alwaysHidden, "\(from)→\(to)")
                    if from == to { XCTAssertTrue(writes.isEmpty) }
                }
            }
        }
    }

    func testThePlansWriteOrders() {
        let plan = { (v: IconsVisual) in
            IconsLengthTable.plan(engine: .length, visual: v, alwaysHidden: true, alwaysHiddenPlaced: true,
                                  dividers: true, hideLength: hideL)
        }
        let collapsed = plan(.collapsed)
        let plain = plan(.expanded(.plain))
        let all = plan(.expanded(.all))
        XCTAssertEqual(IconsLengthTable.writes(separator: collapsed.separator, alwaysHidden: collapsed.alwaysHidden,
                                               to: plain),
                       [IconsLengthWrite(.alwaysHidden, hideL), IconsLengthWrite(.separator, 20)])
        XCTAssertEqual(IconsLengthTable.writes(separator: plain.separator, alwaysHidden: plain.alwaysHidden, to: all),
                       [IconsLengthWrite(.alwaysHidden, 20)])
        XCTAssertEqual(IconsLengthTable.writes(separator: all.separator, alwaysHidden: all.alwaysHidden,
                                               to: collapsed),
                       [IconsLengthWrite(.separator, hideL), IconsLengthWrite(.alwaysHidden, 0)])
        XCTAssertEqual(IconsLengthTable.writes(separator: plain.separator, alwaysHidden: plain.alwaysHidden,
                                               to: collapsed),
                       [IconsLengthWrite(.separator, hideL), IconsLengthWrite(.alwaysHidden, 0)])
    }

    func testMissingAlwaysHiddenIsNeverWritten() {
        let plan = IconsLengthTable.plan(engine: .length, visual: .collapsed, alwaysHidden: false,
                                         alwaysHiddenPlaced: false, dividers: true, hideLength: hideL)
        XCTAssertEqual(IconsLengthTable.writes(separator: 20, alwaysHidden: nil, to: plan),
                       [IconsLengthWrite(.separator, hideL)])
        // An item with no length yet is written (widening).
        let on = IconsLengthTable.plan(engine: .native, visual: .expanded(.plain), alwaysHidden: true,
                                       alwaysHiddenPlaced: false, dividers: true, hideLength: hideL)
        XCTAssertEqual(IconsLengthTable.writes(separator: 0, alwaysHidden: nil, to: on),
                       [IconsLengthWrite(.alwaysHidden, 20)])
    }
}

// MARK: - Allow-lists, system-item check, factory, crash guard

final class IconsEnginePureTests: XCTestCase {
    private func layout(_ sections: [String: IconsSection], system: Set<String> = ["com.apple.TextInputMenuAgent"])
        -> IconsLayout {
        IconsLayout(sections: sections, systemBundles: system, carried: [], extras: [], offScreen: [],
                    scope: .unrestricted, readAt: 0)
    }

    private let sections: [String: IconsSection] = ["com.a": .shown, "com.b": .hidden, "com.c": .alwaysHidden,
                                                    "com.d": .hidden, "com.e": .alwaysHidden]

    func testCollapseList() {
        var inputs = IconsEngineInputs(ownBundleID: own, newShown: ["com.d"],
                                       choices: ["com.b": .alwaysShow, "com.a": .alwaysHide,
                                                 own: .alwaysHide, "com.apple.TextInputMenuAgent": .alwaysHide])
        XCTAssertEqual(IconsAllowList.collapse(layout(sections), inputs),
                       [own, "com.apple.TextInputMenuAgent", "com.b", "com.d"])
        inputs.choices = [:]
        inputs.newShown = []
        XCTAssertEqual(IconsAllowList.collapse(layout(sections), inputs), [own, "com.a", "com.apple.TextInputMenuAgent"])
    }

    func testPlainList() {
        let inputs = IconsEngineInputs(ownBundleID: own, alwaysHidden: true, newShown: ["com.e"],
                                       choices: ["com.c": .alwaysShow, "com.b": .alwaysHide])
        // Always Hide shows while expanded plain unless the app is in Always Hidden.
        XCTAssertEqual(IconsAllowList.plainExpand(layout(sections), inputs),
                       [own, "com.a", "com.apple.TextInputMenuAgent", "com.b", "com.c", "com.d", "com.e"])
    }

    func testPlainRestrictionNeedsSomethingToHide() {
        var inputs = IconsEngineInputs(ownBundleID: own, alwaysHidden: true)
        XCTAssertTrue(IconsAllowList.keepsPlainRestriction(layout(sections), inputs))
        XCTAssertFalse(IconsAllowList.keepsPlainRestriction(nil, inputs))
        inputs.choices = ["com.c": .alwaysShow]
        inputs.newShown = ["com.e"]
        XCTAssertFalse(IconsAllowList.keepsPlainRestriction(layout(sections), inputs))
        inputs = IconsEngineInputs(ownBundleID: own, alwaysHidden: false)
        XCTAssertFalse(IconsAllowList.keepsPlainRestriction(layout(sections), inputs))
        inputs.alwaysHidden = true
        XCTAssertFalse(IconsAllowList.keepsPlainRestriction(layout(["com.a": .shown, own: .alwaysHidden]), inputs))
    }

    func testSystemItemCheck() {
        let before: Set<String> = ["a", "b", IconsSystemItemCheck.nowPlaying]
        XCTAssertEqual(IconsSystemItemCheck.missing(before: before, after: ["a"]), ["b"])
        XCTAssertEqual(IconsSystemItemCheck.missing(before: before, after: ["a", "b"]), [])
        XCTAssertEqual(IconsSystemItemCheck.missing(before: before, after: nil), [])
        XCTAssertEqual(IconsSystemItemCheck.missing(before: nil, after: []), [])
        XCTAssertEqual(IconsSystemItemCheck.missing(before: ["a"], after: ["a", "new"]), [])
    }

    func testFactory() {
        let ok = IconsFactoryInputs(osMajor: 27, currentBuild: "27A1", shimAvailable: true, shimVerified: true)
        XCTAssertEqual(IconsEngineFactory.choose(ok), .engine(.native))
        func with(_ change: (inout IconsFactoryInputs) -> Void) -> IconsEngineChoice {
            var i = ok
            change(&i)
            return IconsEngineFactory.choose(i)
        }
        XCTAssertEqual(with { $0.killSwitches = [.native] }, .unavailable(.killSwitch))
        // macOS 27 never falls back to Length, even with Length's switch off and Native's on.
        XCTAssertEqual(with { $0.killSwitches = [.native, .length] }, .unavailable(.killSwitch))
        XCTAssertEqual(with { $0.killSwitches = [.length] }, .engine(.native))
        XCTAssertEqual(with { $0.killSwitches = [.inventory] }, .unavailable(.inventoryOff))
        XCTAssertEqual(with { $0.shimPoisoned = true }, .unavailable(.shimPoisoned))
        XCTAssertEqual(with { $0.shimAvailable = false }, .unavailable(.shimUnavailable))
        XCTAssertEqual(with { $0.shimVerified = false }, .unavailable(.shimUnavailable))
        XCTAssertEqual(with { $0.disabledBuild = "27A1" }, .unavailable(.disabledBuild))
        XCTAssertEqual(with { $0.disabledBuild = "27A0" }, .engine(.native))
        XCTAssertEqual(with { $0.identityOK = false }, .unavailable(.identity))
        XCTAssertEqual(with { $0.osMajor = 28 }, .engine(.native))

        for major in [14, 15, 26] {
            let legacy = IconsFactoryInputs(osMajor: major, currentBuild: "x")
            XCTAssertEqual(IconsEngineFactory.choose(legacy), .engine(.length))
            var off = legacy
            off.killSwitches = [.length]
            XCTAssertEqual(IconsEngineFactory.choose(off), .unavailable(.killSwitch))
            // Native's switches and the shim don't matter below 27.
            off.killSwitches = [.native, .inventory]
            off.disabledBuild = "x"
            XCTAssertEqual(IconsEngineFactory.choose(off), .engine(.length))
        }
    }

    func testCrashGuard() {
        XCTAssertEqual(IconsCrashGuard.atStart(inFlight: nil, disabledBuild: nil, currentBuild: "B"),
                       IconsCrashGuardResult(disabledBuild: nil, clearInFlight: false, tripped: false))
        XCTAssertEqual(IconsCrashGuard.atStart(inFlight: "B", disabledBuild: nil, currentBuild: "B"),
                       IconsCrashGuardResult(disabledBuild: "B", clearInFlight: true, tripped: true))
        XCTAssertEqual(IconsCrashGuard.atStart(inFlight: "A", disabledBuild: nil, currentBuild: "B"),
                       IconsCrashGuardResult(disabledBuild: nil, clearInFlight: true, tripped: false))
        XCTAssertEqual(IconsCrashGuard.atStart(inFlight: "A", disabledBuild: "A", currentBuild: "B"),
                       IconsCrashGuardResult(disabledBuild: "A", clearInFlight: true, tripped: false))
        // The guard's output feeds the factory: a crash on this build turns Native off on it.
        let guarded = IconsCrashGuard.atStart(inFlight: "B", disabledBuild: nil, currentBuild: "B")
        let choice = IconsEngineFactory.choose(IconsFactoryInputs(
            osMajor: 27, currentBuild: "B", shimAvailable: true, shimVerified: true,
            disabledBuild: guarded.disabledBuild))
        XCTAssertEqual(choice, .unavailable(.disabledBuild))
    }

    func testCounterNames() {
        XCTAssertEqual(IconsFailSafeReason.activateTimeout.counter.name, "icons.activateTimeout")
        XCTAssertEqual(IconsFailSafeReason.exam.counter.name, "icons.failSafe.exam")
        XCTAssertEqual(IconsCounter.dupCompletion.name, "icons.dupCompletion")
        let names = IconsFailSafeReason.allCases.map(\.counter.name)
        XCTAssertEqual(Set(names).count, names.count)
    }
}

// MARK: - Hidden Bar's cases

final class IconsEngineHiddenBarTests: XCTestCase {
    /// HB 1: collapse keeps the visible app, Snaptic and the system items.
    func testCollapseKeepsVisibleOwnAndSystem() {
        let rig = Rig(.native).started()
        XCTAssertEqual(rig.items.lengths[.separator], 0)
        let index = rig.collapse()
        XCTAssertEqual(rig.core.state, .calibrating)
        XCTAssertEqual(rig.inventory.scopes.last, .unrestricted)
        rig.reads()
        XCTAssertEqual(rig.core.state, .calibrating)
        XCTAssertEqual(rig.visibility.requests.map(\.bundles), [collapseList])
        XCTAssertEqual(rig.visibility.requests.first?.systemItems, 0..<64)
        rig.visibility.complete()
        XCTAssertEqual(rig.result(index), [.collapsed])
        XCTAssertEqual(rig.core.state, .collapsed)
        XCTAssertEqual(rig.host.states, [.calibrating, .collapsed])
        XCTAssertEqual(rig.host.count(of: .collapse), 1)
    }

    /// HB 2: `⋮` follows the Always Hidden setting.
    func testAlwaysHiddenMarkFollowsTheSetting() {
        let off = Rig(.native).started()
        XCTAssertNil(off.items.lengths[.alwaysHidden])
        XCTAssertFalse(off.items.writes.contains { $0.role == .alwaysHidden })

        let rig = Rig(.native, alwaysHidden: true)
        rig.items.lengths[.alwaysHidden] = 0
        rig.started()
        XCTAssertEqual(rig.items.lengths[.alwaysHidden], 20)
        rig.collapsed()
        XCTAssertEqual(rig.items.lengths[.alwaysHidden], 0)
        rig.core.expand(.plain)
        while rig.visibility.pendingCount > 0 { rig.visibility.complete() }
        XCTAssertEqual(rig.items.lengths[.alwaysHidden], 20)
    }

    /// HB 3: the private API is missing.
    func testAPIUnavailable() {
        let rig = Rig(.native).started()
        rig.visibility.isAvailable = false
        let index = rig.collapse()
        XCTAssertEqual(rig.result(index), [.unavailable])
        XCTAssertEqual(rig.core.state, .unavailable(.shimUnavailable))
        XCTAssertTrue(rig.visibility.requests.isEmpty)
    }

    /// HB 4: Accessibility is missing; granting it lets the next collapse work.
    func testAccessibilityMissing() {
        let rig = Rig(.native).started()
        rig.host.refusal = .needsPermission
        let index = rig.collapse()
        XCTAssertEqual(rig.result(index), [.refused(.needsPermission)])
        XCTAssertTrue(rig.visibility.requests.isEmpty)
        XCTAssertEqual(rig.core.state, .expanded(.plain))
        rig.host.refusal = nil
        rig.collapsed()
        XCTAssertEqual(rig.core.state, .collapsed)
        XCTAssertEqual(rig.visibility.requests.count, 1)
    }

    /// HB 5: the activation fails.
    func testActivationFails() {
        let rig = Rig(.native).started()
        rig.items.clearWrites()
        let index = rig.collapse()
        rig.reads()
        rig.visibility.complete(.failure(.failed))
        XCTAssertEqual(rig.result(index), [.failed(.activationFailed)])
        XCTAssertEqual(rig.core.state, .expanded(.all))
        XCTAssertEqual(rig.core.lastFailSafe, .activationFailed)
        XCTAssertFalse(rig.items.writes.contains { $0.role == .alwaysHidden })
        XCTAssertEqual(rig.host.count(of: .failSafe(.activationFailed)), 1)
        XCTAssertTrue(rig.visibility.active.isEmpty)
    }

    /// HB 6: expand drops the restriction.
    func testExpandDropsTheRestriction() {
        let rig = Rig(.native).started().collapsed()
        let token = rig.visibility.requests[0].token
        rig.core.expand(.plain)
        XCTAssertEqual(rig.visibility.invalidated, [token])
        XCTAssertTrue(rig.visibility.active.isEmpty)
        XCTAssertEqual(rig.core.state, .expanded(.plain))
        XCTAssertEqual(rig.visibility.requests.count, 1)
        XCTAssertEqual(rig.host.count(of: .expand), 1)
    }

    /// HB 7: Always Hidden on while expanded keeps a restriction, swapped without a gap.
    func testAlwaysHiddenWhileExpanded() {
        let rig = Rig(.native, alwaysHidden: true).started()
        XCTAssertEqual(rig.visibility.requests.map(\.bundles), [plainList])
        XCTAssertEqual(rig.core.heldBundles, plainList)

        rig.collapse()
        XCTAssertEqual(rig.inventory.scopes.last, .restricted(allowed: Set(plainList)))
        rig.reads()
        XCTAssertEqual(rig.visibility.requests.last?.bundles, collapseList)
        // The plain restriction stays until the collapse one is active.
        XCTAssertTrue(rig.visibility.invalidated.isEmpty)
        rig.visibility.complete()
        XCTAssertEqual(rig.visibility.invalidated, [rig.visibility.requests[0].token])
        XCTAssertEqual(rig.core.state, .collapsed)

        rig.core.expand(.plain)
        XCTAssertEqual(rig.visibility.requests.last?.bundles, plainList)
        XCTAssertEqual(rig.visibility.active.count, 1)
        rig.visibility.complete()
        XCTAssertEqual(rig.visibility.active.values.first, plainList)
        XCTAssertEqual(rig.visibility.active.count, 1)
        XCTAssertFalse(rig.visibility.flashed)
    }

    /// HB 8: no unrestricted read while something is hidden; a stale frame of a hidden app isn't trusted.
    func testNoTrustedReadWhileHidden() {
        let rig = Rig(.native, alwaysHidden: true).started()
        rig.collapse()
        // `com.always` is hidden, so Accessibility still reports its old frame, here on the shown side.
        var stale = standardInventory()
        stale.apps[0] = app("com.always", 1420, pid: 10)
        stale.apps[1] = app("com.hidden", 1700, pid: 20)
        rig.reads(with: stale)
        XCTAssertEqual(rig.core.layout?.sections["com.always"], .alwaysHidden)
        // An allowed app's frame is current, so it moves.
        XCTAssertEqual(rig.core.layout?.sections["com.hidden"], .shown)
        XCTAssertEqual(rig.core.layout?.readAt, 100)
        XCTAssertFalse(rig.visibility.requests.last?.bundles.contains("com.always") ?? true)
        XCTAssertFalse(rig.inventory.scopes.dropFirst().contains(.unrestricted))
    }

    /// HB 9: expand during the activation.
    func testExpandDuringActivation() {
        let rig = Rig(.native).started()
        let index = rig.collapse()
        rig.reads()
        rig.core.expand(.plain)
        XCTAssertEqual(rig.result(index), [.superseded])
        XCTAssertEqual(rig.core.state, .expanded(.plain))
        rig.visibility.complete()
        let token = rig.visibility.requests[0].token
        XCTAssertEqual(rig.visibility.invalidated, [token])
        XCTAssertTrue(rig.visibility.active.isEmpty)
        XCTAssertEqual(rig.result(index), [.superseded])
        XCTAssertEqual(rig.core.state, .expanded(.plain))
        XCTAssertFalse(rig.host.markerSet)
    }

    /// HB 10: a display change keeps the bar collapsed.
    func testDisplayChangeKeepsCollapsed() {
        let rig = Rig(.native).started().collapsed()
        rig.core.screenParametersChanged()
        rig.scheduler.advance(1)
        XCTAssertEqual(rig.core.state, .collapsed)
        XCTAssertTrue(rig.visibility.invalidated.isEmpty)
        XCTAssertEqual(rig.visibility.active.count, 1)
    }

    /// HB's Length case. The plan also zeroes `⋮` while collapsed.
    func testLengthCollapseAndExpand() {
        let rig = Rig(.length).started()
        XCTAssertEqual(rig.core.state, .expanded(.plain))
        let index = rig.collapse()
        XCTAssertEqual(rig.result(index), [.collapsed])
        XCTAssertEqual(rig.core.state, .collapsed)
        XCTAssertEqual(rig.items.lengths[.separator], hideL)
        rig.scheduler.tick()
        XCTAssertEqual(rig.core.state, .collapsed)
        rig.core.expand(.plain)
        XCTAssertEqual(rig.core.state, .expanded(.plain))
        XCTAssertEqual(rig.items.lengths[.separator], 20)
        XCTAssertTrue(rig.visibility.requests.isEmpty)
    }
}

// MARK: - Engine behaviour

final class IconsEngineCoreTests: XCTestCase {
    // MARK: Length

    func testLengthAlwaysHiddenLengths() {
        let rig = Rig(.length, alwaysHidden: true).started()
        XCTAssertEqual(rig.items.lengths[.alwaysHidden], hideL)
        XCTAssertEqual(rig.items.lengths[.separator], 20)
        rig.items.clearWrites()
        rig.collapsed()
        XCTAssertEqual(rig.items.writes, [IconsLengthWrite(.separator, hideL), IconsLengthWrite(.alwaysHidden, 0)])
        rig.items.clearWrites()
        rig.core.expand(.plain)
        XCTAssertEqual(rig.items.writes, [IconsLengthWrite(.alwaysHidden, hideL), IconsLengthWrite(.separator, 20)])
        rig.items.clearWrites()
        rig.core.expand(.all)
        XCTAssertEqual(rig.items.writes, [IconsLengthWrite(.alwaysHidden, 20)])
        XCTAssertEqual(rig.core.state, .expanded(.all))
    }

    func testLengthUnplacedAlwaysHiddenIsNeverInflated() {
        let rig = Rig(.length, alwaysHidden: true)
        // `⋮` sits right of the arrow: unplaced.
        rig.items.frames[.alwaysHidden] = IconsRect(x: 1400, y: 0, width: 20, height: 24)
        rig.started()
        XCTAssertEqual(rig.items.lengths[.alwaysHidden], 20)
        rig.collapsed()
        rig.core.expand(.plain)
        XCTAssertEqual(rig.items.lengths[.alwaysHidden], 20)
    }

    func testLengthDividersOff() {
        let rig = Rig(.length, alwaysHidden: true, dividers: false).started()
        rig.update { $0.alwaysHidden = false }
        XCTAssertEqual(rig.items.lengths[.separator], 0)
        rig.collapsed()
        XCTAssertEqual(rig.items.lengths[.separator], hideL)
        rig.core.expand(.all)
        XCTAssertEqual(rig.items.lengths[.separator], 0)
    }

    func testLengthRefusals() {
        let rig = Rig(.length).started()
        rig.items.hidden = [.separator]
        XCTAssertEqual(rig.result(rig.collapse()), [.refused(.dividerHidden)])
        rig.items.hidden = [.toggle]
        XCTAssertEqual(rig.result(rig.collapse()), [.refused(.arrowHidden)])
        rig.items.hidden = []
        // `|` dragged right of the arrow.
        rig.items.frames[.separator] = IconsRect(x: 1400, y: 0, width: 20, height: 24)
        XCTAssertEqual(rig.result(rig.collapse()), [.refused(.arrangement)])
        rig.items.frames[.separator] = IconsRect(x: 1300, y: 0, width: 20, height: 24)
        rig.host.refusal = .exam
        XCTAssertEqual(rig.result(rig.collapse()), [.refused(.exam)])
        XCTAssertEqual(rig.items.lengths[.separator], 20)
    }

    func testLengthRejectedFailsSafe() {
        let rig = Rig(.length).started()
        rig.items.rejectLengths = true
        let index = rig.collapse()
        XCTAssertEqual(rig.result(index), [.collapsed])
        rig.scheduler.tick()
        XCTAssertEqual(rig.core.lastFailSafe, .lengthRejected)
        XCTAssertEqual(rig.core.state, .expanded(.all))
        XCTAssertEqual(rig.items.lengths[.separator], 20)
        XCTAssertEqual(rig.host.count(of: .failSafe(.lengthRejected)), 1)
    }

    func testLengthStateFollowsTheLiveLength() {
        let rig = Rig(.length).started().collapsed()
        // macOS reset the item.
        rig.items.lengths[.separator] = 20
        XCTAssertEqual(rig.core.state, .expanded(.plain))
        rig.items.lengths[.separator] = hideL
        XCTAssertEqual(rig.core.state, .collapsed)
    }

    func testLengthScreenChangesCoalesceAndSkipTrials() {
        let rig = Rig(.length).started().collapsed()
        rig.host.screenList = [IconsScreen(frame: IconsRect(x: 0, y: 0, width: 2560, height: 1440))]
        rig.items.clearWrites()
        rig.core.screenParametersChanged()
        rig.scheduler.advance(0.1)
        rig.core.screenParametersChanged()
        rig.scheduler.advance(0.2)
        XCTAssertTrue(rig.items.writes.isEmpty)
        rig.scheduler.advance(0.1)
        XCTAssertEqual(rig.items.writes, [IconsLengthWrite(.separator, 5120)])

        rig.items.clearWrites()
        rig.core.setDisplayTrialPending(true)
        rig.host.screenList = [IconsScreen(frame: screenFrame)]
        rig.core.screenParametersChanged()
        rig.scheduler.advance(1)
        XCTAssertTrue(rig.items.writes.isEmpty)
        rig.core.setDisplayTrialPending(false)
        XCTAssertEqual(rig.items.writes, [IconsLengthWrite(.separator, hideL)])
    }

    func testLengthScreenChangeRechecksArrangement() {
        let rig = Rig(.length).started().collapsed()
        rig.items.frames[.separator] = IconsRect(x: 1400, y: 0, width: hideL, height: 24)
        rig.core.screenParametersChanged()
        rig.scheduler.advance(1)
        XCTAssertEqual(rig.core.lastFailSafe, .arrangement)
        XCTAssertEqual(rig.items.lengths[.separator], 20)
    }

    func testLengthScreenChangeWhileExpandedPlainOnlyTouchesInflated() {
        let rig = Rig(.length).started()
        rig.items.clearWrites()
        rig.core.screenParametersChanged()
        rig.scheduler.advance(1)
        XCTAssertTrue(rig.items.writes.isEmpty)
    }

    // MARK: Native

    func testNativeTimeoutThenTwoInARow() {
        let rig = Rig(.native).started()
        let first = rig.collapse()
        rig.reads()
        XCTAssertTrue(rig.host.markerSet)
        rig.scheduler.advance(3)
        XCTAssertEqual(rig.result(first), [.failed(.activateTimeout)])
        XCTAssertEqual(rig.core.state, .expanded(.all))
        XCTAssertEqual(rig.host.count(of: .activateTimeout), 1)
        XCTAssertFalse(rig.host.markerSet)
        // The late success is released at once.
        rig.visibility.complete()
        XCTAssertTrue(rig.visibility.active.isEmpty)

        let second = rig.collapse()
        rig.reads()
        rig.scheduler.advance(3)
        XCTAssertEqual(rig.result(second), [.failed(.activateTimeout)])
        XCTAssertEqual(rig.core.state, .unavailable(.timeouts))
        XCTAssertEqual(rig.result(rig.collapse()), [.unavailable])
    }

    func testNativeSuccessResetsTheTimeoutCount() {
        let rig = Rig(.native).started()
        rig.collapse()
        rig.reads()
        rig.scheduler.advance(3)
        rig.visibility.complete()
        rig.collapsed()
        XCTAssertEqual(rig.core.state, .collapsed)
        rig.core.expand(.plain)
        rig.settle(lifo: false)
        rig.collapse()
        rig.reads()
        rig.scheduler.advance(3)
        XCTAssertEqual(rig.core.state, .expanded(.all))
    }

    func testDuplicateCompletionIsCounted() {
        let rig = Rig(.native).started()
        let index = rig.collapse()
        rig.reads()
        let completion = rig.visibility.takeCompletion()
        completion(.success(()))
        completion(.success(()))
        completion(.failure(.failed))
        XCTAssertEqual(rig.result(index), [.collapsed])
        XCTAssertEqual(rig.core.state, .collapsed)
        XCTAssertEqual(rig.host.count(of: .dupCompletion), 2)
    }

    func testCollapsesJoin() {
        let rig = Rig(.native).started()
        let a = rig.collapse()
        let b = rig.collapse()
        rig.reads()
        let c = rig.collapse()
        rig.visibility.complete()
        XCTAssertEqual([rig.result(a), rig.result(b), rig.result(c)], [[.collapsed], [.collapsed], [.collapsed]])
        XCTAssertEqual(rig.visibility.requests.count, 1)
        XCTAssertEqual(rig.result(rig.collapse()), [.collapsed])
    }

    func testKillSwitchBeforeCollapseAndAfterTheRead() {
        let rig = Rig(.native).started()
        rig.host.killSwitch = true
        XCTAssertEqual(rig.result(rig.collapse()), [.unavailable])
        XCTAssertEqual(rig.core.state, .unavailable(.killSwitch))

        let late = Rig(.native).started()
        let index = late.collapse()
        late.host.killSwitch = true
        late.reads()
        XCTAssertEqual(late.result(index), [.unavailable])
        XCTAssertTrue(late.visibility.requests.isEmpty)
    }

    func testKillSwitchPreemptsWhileCollapsed() {
        let rig = Rig(.native).started().collapsed()
        rig.core.killSwitchTurnedOn()
        XCTAssertEqual(rig.core.state, .unavailable(.killSwitch))
        XCTAssertTrue(rig.visibility.active.isEmpty)
        XCTAssertGreaterThan(rig.visibility.invalidateAllCount, 0)
        rig.core.expand(.all)
        XCTAssertEqual(rig.core.state, .unavailable(.killSwitch))
    }

    func testRefusalAfterTheReadRestoresTheMode() {
        let rig = Rig(.native, alwaysHidden: true).started()
        let index = rig.collapse()
        rig.host.refusal = .exam
        rig.reads()
        XCTAssertEqual(rig.result(index), [.refused(.exam)])
        XCTAssertEqual(rig.core.state, .expanded(.plain))
        XCTAssertEqual(rig.core.heldBundles, plainList)
        XCTAssertEqual(rig.visibility.requests.count, 1)
    }

    func testStopDoesNotWait() {
        let rig = Rig(.native, alwaysHidden: true).started()
        let index = rig.collapse()
        rig.reads()
        XCTAssertTrue(rig.host.markerSet)
        rig.core.stop()
        XCTAssertEqual(rig.result(index), [.superseded])
        XCTAssertEqual(rig.core.state, .unavailable(.stopped))
        XCTAssertTrue(rig.visibility.active.isEmpty)
        XCTAssertFalse(rig.host.markerSet)
        XCTAssertEqual(rig.scheduler.pendingCount, 0)
        XCTAssertEqual(rig.items.lengths[.alwaysHidden], 20)
        // The late success is released.
        rig.visibility.complete()
        XCTAssertTrue(rig.visibility.active.isEmpty)
        XCTAssertEqual(rig.core.state, .unavailable(.stopped))
        XCTAssertFalse(rig.host.markerSet)
    }

    func testCrashGuardMarkerBracketsEachActivation() {
        let rig = Rig(.native).started()
        XCTAssertTrue(rig.host.inFlight.isEmpty)
        rig.collapsed()
        XCTAssertEqual(rig.host.inFlight, [true, false])
        rig.core.expand(.plain)
        rig.collapsed()
        XCTAssertEqual(rig.host.inFlight, [true, false, true, false])
    }

    func testPoisonedShim() {
        let rig = Rig(.native).started()
        let index = rig.collapse()
        rig.reads()
        rig.visibility.complete(.failure(.poisoned))
        XCTAssertEqual(rig.result(index), [.failed(.shimPoisoned)])
        XCTAssertEqual(rig.core.state, .unavailable(.shimPoisoned))
    }

    func testSystemItemHiddenDisablesNativeOnThisBuild() {
        let rig = Rig(.native).started()
        rig.inventory.systemAfter = ["com.apple.menuextra.clock"]
        let index = rig.collapse()
        rig.reads()
        rig.visibility.complete()
        XCTAssertEqual(rig.result(index), [.collapsed])
        XCTAssertEqual(rig.host.disabledBuilds, 1)
        XCTAssertEqual(rig.core.state, .unavailable(.disabledBuild))
        XCTAssertEqual(rig.host.count(of: .systemItemHidden), 1)
        XCTAssertTrue(rig.visibility.active.isEmpty)
    }

    func testNowPlayingMissingIsExpected() {
        let rig = Rig(.native).started()
        rig.inventory.systemAfter = ["com.apple.menuextra.clock", "com.apple.menuextra.battery"]
        rig.collapsed()
        XCTAssertEqual(rig.core.state, .collapsed)
        XCTAssertEqual(rig.host.disabledBuilds, 0)
        XCTAssertEqual(rig.inventory.systemReads, 1)
    }

    func testUnusableReadFailsSafe() {
        let rig = Rig(.native).started()
        let index = rig.collapse()
        rig.reads(with: .failure())
        XCTAssertEqual(rig.result(index), [.failed(.unusableRead)])
        XCTAssertTrue(rig.visibility.requests.isEmpty)
        XCTAssertEqual(rig.core.state, .expanded(.all))
    }

    func testNewShownSwapsWhileCollapsed() {
        let rig = Rig(.native).started().collapsed()
        rig.update { $0.newShown = ["com.hidden"] }
        XCTAssertEqual(rig.visibility.requests.last?.bundles,
                       [own, "com.apple.TextInputMenuAgent", "com.hidden", "com.visible"])
        XCTAssertEqual(rig.visibility.active.count, 1)
        rig.visibility.complete()
        XCTAssertEqual(rig.visibility.active.count, 1)
        XCTAssertEqual(rig.core.state, .collapsed)
        XCTAssertFalse(rig.visibility.flashed)
        rig.update { $0.choices = ["com.visible": .alwaysHide] }
        rig.visibility.complete()
        XCTAssertEqual(rig.core.heldBundles, [own, "com.apple.TextInputMenuAgent", "com.hidden"])
    }

    func testInputsChangedWhileCalibratingApplyAfter() {
        let rig = Rig(.native).started()
        rig.collapse()
        rig.reads()
        rig.update { $0.newShown = ["com.hidden"] }
        rig.visibility.complete()
        XCTAssertEqual(rig.visibility.requests.count, 2)
        rig.visibility.complete()
        XCTAssertEqual(rig.core.heldBundles, [own, "com.apple.TextInputMenuAgent", "com.hidden", "com.visible"])
    }

    func testAlwaysHiddenToggledWhileExpandedPlain() {
        let rig = Rig(.native).started()
        XCTAssertTrue(rig.visibility.requests.isEmpty)
        // The module adds `⋮`; the core re-reads, now with it as a boundary.
        rig.items.frames[.alwaysHidden] = IconsRect(x: 1000, y: 0, width: 20, height: 24)
        rig.update { $0.alwaysHidden = true }
        XCTAssertEqual(rig.inventory.scopes.last, .unrestricted)
        rig.reads()
        XCTAssertEqual(rig.visibility.requests.last?.bundles, plainList)
        rig.visibility.complete()
        XCTAssertEqual(rig.core.heldBundles, plainList)
        rig.update { $0.alwaysHidden = false }
        XCTAssertTrue(rig.visibility.active.isEmpty)
        XCTAssertFalse(rig.core.isRestricted)
        XCTAssertEqual(rig.inventory.scopes.last, .unrestricted)
    }

    func testNothingToHideMeansNoPlainRestriction() {
        let rig = Rig(.native, alwaysHidden: true, inventory: standardInventory(always: false)).started()
        XCTAssertTrue(rig.visibility.requests.isEmpty)
        rig.collapsed()
        rig.core.expand(.plain)
        XCTAssertTrue(rig.visibility.active.isEmpty)
    }

    func testExpandAllDropsEverythingAndReads() {
        let rig = Rig(.native, alwaysHidden: true).started().collapsed()
        let reads = rig.inventory.scopes.count
        rig.core.expand(.all)
        XCTAssertTrue(rig.visibility.active.isEmpty)
        XCTAssertEqual(rig.core.state, .expanded(.all))
        XCTAssertEqual(rig.inventory.scopes.count, reads + 1)
        XCTAssertEqual(rig.inventory.scopes.last, .unrestricted)
    }

    func testAgentTerminatedFailsSafe() {
        let rig = Rig(.native).started().collapsed()
        rig.core.agentTerminated()
        XCTAssertEqual(rig.core.lastFailSafe, .agentRestart)
        XCTAssertEqual(rig.host.count(of: .agentRestart), 1)
        XCTAssertTrue(rig.visibility.active.isEmpty)
        XCTAssertEqual(rig.core.state, .expanded(.all))
    }

    func testRefreshWhileRestrictedShowsEverythingFirst() {
        let rig = Rig(.native).started().collapsed()
        rig.core.refreshLayout()
        XCTAssertEqual(rig.core.state, .expanded(.all))
        XCTAssertTrue(rig.visibility.active.isEmpty)
        XCTAssertEqual(rig.inventory.scopes.last, .unrestricted)
    }

    func testUnrestrictedReadReplacesTheCacheAndReportsIt() {
        let cache = IconsLayoutCache(readAt: 5, sections: ["com.gone": .hidden, "com.visible": .hidden])
        let rig = Rig(.native, cache: cache)
        XCTAssertEqual(rig.core.layout?.sections, cache.sections)
        rig.started()
        // Always Hidden is off, so `com.always` is just hidden.
        XCTAssertEqual(rig.core.layout?.sections,
                       ["com.always": .hidden, "com.hidden": .hidden, "com.visible": .shown])
        XCTAssertEqual(rig.core.layout?.readAt, 100)
        XCTAssertEqual(rig.host.layouts.last?.scope, .unrestricted)
        XCTAssertEqual(rig.host.count(of: .started), 1)
    }

    func testNativeStartNeedsBothPorts() {
        let host = FakeHost()
        let core = IconsEngineCore(engine: .native, items: FakeItems(separator: 20, alwaysHidden: nil),
                                   visibility: nil, inventory: nil, scheduler: FakeScheduler(), host: host,
                                   inputs: IconsEngineInputs(ownBundleID: own))
        core.start()
        XCTAssertEqual(core.state, .unavailable(.shimUnavailable))
    }
}

// MARK: - Race matrix

final class IconsEngineRaceTests: XCTestCase {
    private enum Intent: CaseIterable {
        case collapse, expandPlain, expandAll, stop, failSafe, killSwitch, agentTerminated, toggleSetting, screen
    }

    private enum Start: CaseIterable {
        case plainUnrestricted, plainRestricted, all, calibratingRead, calibratingActivate, collapsed, unavailable
    }

    private enum Target: Equatable {
        case collapsed, plain, all, unavailable(IconsUnavailableReason)
    }

    private func setUp(_ engine: IconsEngineKind, _ start: Start) -> (Rig, Target)? {
        switch (engine, start) {
        case (.length, .plainRestricted), (.length, .calibratingRead), (.length, .calibratingActivate):
            return nil
        default: break
        }
        let rig = Rig(engine, alwaysHidden: start != .plainUnrestricted)
        rig.started()
        switch start {
        case .plainUnrestricted, .plainRestricted:
            return (rig, .plain)
        case .all:
            rig.core.expand(.all)
            rig.settle(lifo: false)
            return (rig, .all)
        case .calibratingRead:
            rig.collapse()
            return (rig, .collapsed)
        case .calibratingActivate:
            rig.collapse()
            rig.reads()
            return (rig, .collapsed)
        case .collapsed:
            rig.collapsed()
            return (rig, .collapsed)
        case .unavailable:
            rig.core.killSwitchTurnedOn()
            return (rig, .unavailable(.killSwitch))
        }
    }

    private func apply(_ intent: Intent, _ rig: Rig, _ target: Target) -> Target {
        let unavailable: Bool
        if case .unavailable = target { unavailable = true } else { unavailable = false }
        switch intent {
        case .collapse:
            rig.collapse()
            return unavailable ? target : .collapsed
        case .expandPlain:
            rig.core.expand(.plain)
            return unavailable ? target : .plain
        case .expandAll:
            rig.core.expand(.all)
            return unavailable ? target : .all
        case .stop:
            rig.core.stop()
            return .unavailable(.stopped)
        case .failSafe:
            rig.core.failSafe(.exam)
            return unavailable ? target : .all
        case .killSwitch:
            rig.core.killSwitchTurnedOn()
            return unavailable ? target : .unavailable(.killSwitch)
        case .agentTerminated:
            rig.core.agentTerminated()
            return unavailable ? target : .all
        case .toggleSetting:
            rig.update { $0.alwaysHidden.toggle() }
            return target
        case .screen:
            rig.core.screenParametersChanged()
            return target
        }
    }

    private func expected(_ target: Target) -> IconsEngineState {
        switch target {
        case .collapsed: .collapsed
        case .plain: .expanded(.plain)
        case .all: .expanded(.all)
        case .unavailable(let reason): .unavailable(reason)
        }
    }

    func testEveryPairFromEveryStateSettles() {
        var cases = 0
        for engine in IconsEngineKind.allCases {
            for start in Start.allCases {
                for first in Intent.allCases {
                    for second in Intent.allCases {
                        for lifo in [false, true] {
                            guard let (rig, initial) = setUp(engine, start) else { continue }
                            cases += 1
                            let label = "\(engine) \(start) \(first)→\(second) lifo=\(lifo)"
                            var target = apply(first, rig, initial)
                            target = apply(second, rig, target)
                            rig.settle(lifo: lifo)
                            check(rig, engine, expected(target), label)
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(cases, 1500)
    }

    private func check(_ rig: Rig, _ engine: IconsEngineKind, _ want: IconsEngineState, _ label: String) {
        let state = rig.core.state
        XCTAssertEqual(state, want, label)
        for (index, results) in rig.results.enumerated() {
            XCTAssertEqual(results.count, 1, "collapse \(index) answered \(results) — \(label)")
        }
        XCTAssertFalse(rig.host.markerSet, "marker left set — \(label)")
        let active = rig.visibility.active.count
        // The core's idea of the restriction is the server's.
        XCTAssertEqual(rig.core.heldBundles, active == 1 ? rig.visibility.active.values.first : nil, label)
        XCTAssertEqual(rig.core.isRestricted, active > 0, label)
        switch state {
        case .collapsed:
            if engine == .native { XCTAssertEqual(active, 1, label) }
            if engine == .length { XCTAssertEqual(rig.items.lengths[.separator], hideL, label) }
        case .expanded(.all), .unavailable:
            XCTAssertEqual(active, 0, label)
            XCTAssertLessThanOrEqual(rig.items.lengths[.separator] ?? 0, 20, label)
        case .expanded(.plain):
            XCTAssertLessThanOrEqual(active, 1, label)
            XCTAssertLessThanOrEqual(rig.items.lengths[.separator] ?? 0, 20, label)
            if engine == .native {
                // Plain is restricted exactly when Always Hidden has something to hide.
                let wants = IconsAllowList.keepsPlainRestriction(rig.core.layout, rig.inputs)
                XCTAssertEqual(active, wants ? 1 : 0, label)
            }
        case .calibrating:
            XCTFail("still calibrating — \(label)")
        }
    }
}
