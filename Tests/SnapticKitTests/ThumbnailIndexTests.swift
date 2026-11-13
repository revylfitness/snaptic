import XCTest
@testable import SnapticKit

// 0.5 A1b (§2.3, §2.5, D2-14, X2-11, X2-12, D2-22): the thumbnail index's client cases — isolation between clients,
// stamps, the last release, last-seen entries across a switcher open, `.thumbnails` lookups, the bucket lookup and
// 0.4's limits. The budget cases (120 entries, 96 MB, the oversize skip, 30-minute expiry, `nextExpiry`) are A2a's.

private let dockBucket = 720
private let listBucket = 640
private let previewBucket = 2400

private func key(_ id: UInt32, _ bucket: Int) -> ThumbnailKey { ThumbnailKey(windowID: id, bucket: bucket) }

/// Both clients hold `.thumbnails`, as their leases would after `acquire`.
private func bothClients() -> ThumbnailIndex {
    var index = ThumbnailIndex()
    index.setThumbnails(true, client: .windowSwitcher)
    index.setThumbnails(true, client: .dockPreviews)
    return index
}

@discardableResult
private func store(_ index: inout ThumbnailIndex, _ key: ThumbnailKey, _ client: ModuleID, now: Double = 0)
    -> ThumbnailIndex.InsertResult {
    index.insert(key, stamp: index.stamp(for: client), now: now)
}

final class ThumbnailIndexTests: XCTestCase {
    // MARK: Client isolation

    func testOneClientsPruneNeverTouchesTheOthersEntries() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher)
        store(&index, key(2, dockBucket), .dockPreviews)
        store(&index, key(3, dockBucket), .dockPreviews)
        // The switcher lists window 1 only; windows 2 and 3 are the Dock's.
        let dropped = index.prune(keeping: [1], client: .windowSwitcher, now: 1)
        XCTAssertEqual(dropped, [])
        XCTAssertEqual(index.count, 3)
        // The Dock lists neither 1 nor 3: only its own entry for 3 goes.
        XCTAssertEqual(index.prune(keeping: [2], client: .dockPreviews, now: 1), [key(3, dockBucket)])
        XCTAssertNotNil(index.entries[key(1, listBucket)])
        XCTAssertNotNil(index.entries[key(2, dockBucket)])
    }

    func testOneClientsInvalidateNeverTouchesTheOthersCapturesOrEntries() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher)
        store(&index, key(2, dockBucket), .dockPreviews)
        let switcherStamp = index.stamp(for: .windowSwitcher)
        let dockStamp = index.stamp(for: .dockPreviews)
        index.invalidate(client: .windowSwitcher)
        XCTAssertFalse(index.isCurrent(switcherStamp))
        XCTAssertTrue(index.isCurrent(dockStamp))
        XCTAssertEqual(index.insert(key(3, listBucket), stamp: switcherStamp, now: 1), .refused)
        XCTAssertEqual(index.insert(key(4, dockBucket), stamp: dockStamp, now: 1), .stored(evicted: []))
        // Invalidating keeps entries: the switcher's closing doesn't empty its cache.
        XCTAssertEqual(Set(index.entries.keys), [key(1, listBucket), key(2, dockBucket), key(4, dockBucket)])
    }

    func testOneClientsPurgeNeverTouchesTheOthersEntries() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher)
        store(&index, key(1, previewBucket), .windowSwitcher)
        store(&index, key(2, dockBucket), .dockPreviews)
        let dockStamp = index.stamp(for: .dockPreviews)
        XCTAssertEqual(index.purge(client: .windowSwitcher), [key(1, listBucket), key(1, previewBucket)])
        XCTAssertEqual(Array(index.entries.keys), [key(2, dockBucket)])
        XCTAssertTrue(index.isCurrent(dockStamp))
        XCTAssertEqual(index.lookup(windowID: 2, bucket: dockBucket, client: .dockPreviews, now: 1), key(2, dockBucket))
    }

    // MARK: Stamps (§2.5, X2-12)

    func testAStaleStampIsRefused() {
        var index = bothClients()
        let stamp = index.stamp(for: .dockPreviews)
        index.invalidate(client: .dockPreviews)
        XCTAssertEqual(index.insert(key(1, dockBucket), stamp: stamp, now: 0), .refused)
        XCTAssertEqual(index.count, 0)
        // A fresh stamp after the bump stores.
        XCTAssertEqual(store(&index, key(1, dockBucket), .dockPreviews), .stored(evicted: []))
    }

    func testACaptureThatFinishesAfterPurgeClientIsRefused() {
        var index = bothClients()
        store(&index, key(1, dockBucket), .dockPreviews)
        let inFlight = index.stamp(for: .dockPreviews)   // a capture starts
        _ = index.purge(client: .dockPreviews)           // returns at once; waits for nothing
        XCTAssertEqual(index.count, 0)
        XCTAssertEqual(index.insert(key(2, dockBucket), stamp: inFlight, now: 1), .refused)   // it lands late
        XCTAssertEqual(index.count, 0)
    }

    func testPurgeAllBumpsTheEpochForEveryClient() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher)
        store(&index, key(2, dockBucket), .dockPreviews)
        let switcherStamp = index.stamp(for: .windowSwitcher)
        let dockStamp = index.stamp(for: .dockPreviews)
        XCTAssertEqual(Set(index.purgeAll()), [key(1, listBucket), key(2, dockBucket)])
        XCTAssertEqual(index.count, 0)
        XCTAssertFalse(index.isCurrent(switcherStamp))
        XCTAssertFalse(index.isCurrent(dockStamp))
        XCTAssertEqual(index.insert(key(3, dockBucket), stamp: dockStamp, now: 1), .refused)
        // Generations are untouched; only the epoch moved.
        XCTAssertEqual(index.generation(of: .dockPreviews), dockStamp.generation)
    }

    // MARK: Leases

    func testReleaseRefusesTheClientsCapturesInFlight() {
        var ledger = WindowLeaseLedger()
        var index = ThumbnailIndex()
        _ = index.apply(ledger.acquire(.windowSwitcher, needs: [.recency, .thumbnails], now: 0), ledger: ledger)
        _ = index.apply(ledger.acquire(.dockPreviews, needs: [.thumbnails], now: 0), ledger: ledger)
        store(&index, key(1, listBucket), .windowSwitcher)
        store(&index, key(2, dockBucket), .dockPreviews)
        let inFlight = index.stamp(for: .dockPreviews)
        let dropped = index.apply(ledger.release(.dockPreviews, now: 1), ledger: ledger)
        XCTAssertEqual(dropped, [key(2, dockBucket)])
        XCTAssertEqual(index.insert(key(3, dockBucket), stamp: inFlight, now: 1), .refused)
        XCTAssertEqual(Array(index.entries.keys), [key(1, listBucket)])
        XCTAssertEqual(index.thumbnailClients, [.windowSwitcher])
    }

    func testTheLastReleaseEmptiesTheIndex() {
        var ledger = WindowLeaseLedger()
        var index = ThumbnailIndex()
        _ = index.apply(ledger.acquire(.windowSwitcher, needs: [.recency, .thumbnails], now: 0), ledger: ledger)
        _ = index.apply(ledger.acquire(.dockPreviews, needs: [.thumbnails], now: 0), ledger: ledger)
        store(&index, key(1, listBucket), .windowSwitcher)
        store(&index, key(2, dockBucket), .dockPreviews)
        let switcherStamp = index.stamp(for: .windowSwitcher)
        _ = index.apply(ledger.release(.dockPreviews, now: 1), ledger: ledger)
        let dropped = index.apply(ledger.release(.windowSwitcher, now: 2), ledger: ledger)
        XCTAssertEqual(dropped, [key(1, listBucket)])
        XCTAssertEqual(index.count, 0)
        XCTAssertTrue(index.order.isEmpty)
        XCTAssertTrue(index.thumbnailClients.isEmpty)
        XCTAssertFalse(index.isCurrent(switcherStamp))
        XCTAssertEqual(index.insert(key(3, listBucket), stamp: switcherStamp, now: 2), .refused)
    }

    // MARK: Last-seen (D2-14)

    func testOpeningTheSwitcherKeepsAMinimizedWindowsLastSeenEntry() {
        var index = bothClients()
        // Window 7 was on screen: the Dock and the switcher both captured it. Then it was minimized.
        store(&index, key(7, dockBucket), .dockPreviews)
        store(&index, key(7, listBucket), .windowSwitcher)
        store(&index, key(8, listBucket), .windowSwitcher)
        // The switcher opens. It invalidates its last batch, then prunes to the windows that still exist (7 and 8).
        index.invalidate(client: .windowSwitcher)
        XCTAssertEqual(index.prune(keeping: [7, 8], client: .windowSwitcher, now: 10), [])
        XCTAssertEqual(index.lookup(windowID: 7, bucket: dockBucket, client: .dockPreviews, now: 10), key(7, dockBucket))
        XCTAssertEqual(index.lookup(windowID: 7, bucket: listBucket, client: .windowSwitcher, now: 10),
                       key(7, listBucket))
        // Even a prune to the on-screen windows only never reaches the Dock's last-seen entry.
        XCTAssertEqual(index.prune(keeping: [8], client: .windowSwitcher, now: 10), [key(7, listBucket)])
        XCTAssertEqual(index.lookup(windowID: 7, bucket: dockBucket, client: .dockPreviews, now: 10), key(7, dockBucket))
    }

    func testPruneDropsTheClientsEntriesForWindowsThatAreGone() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher)
        store(&index, key(1, previewBucket), .windowSwitcher)
        store(&index, key(2, listBucket), .windowSwitcher)
        XCTAssertEqual(index.prune(keeping: [2], client: .windowSwitcher, now: 1),
                       [key(1, listBucket), key(1, previewBucket)])
        XCTAssertEqual(index.order, [key(2, listBucket)])
    }

    // MARK: `.thumbnails` (X2-11)

    func testDroppingThumbnailsPurgesThatClient() {
        var ledger = WindowLeaseLedger()
        var index = ThumbnailIndex()
        _ = index.apply(ledger.acquire(.windowSwitcher, needs: [.recency, .thumbnails], now: 0), ledger: ledger)
        _ = index.apply(ledger.acquire(.dockPreviews, needs: [.thumbnails], now: 0), ledger: ledger)
        store(&index, key(1, listBucket), .windowSwitcher)
        store(&index, key(2, dockBucket), .dockPreviews)
        let inFlight = index.stamp(for: .dockPreviews)
        let commands = ledger.update(.dockPreviews, needs: [], now: 1)
        XCTAssertTrue(commands.contains(.purge(.dockPreviews)))
        XCTAssertEqual(index.apply(commands, ledger: ledger), [key(2, dockBucket)])
        XCTAssertEqual(Array(index.entries.keys), [key(1, listBucket)])
        XCTAssertEqual(index.insert(key(3, dockBucket), stamp: inFlight, now: 1), .refused)
        // A capture started after the update is refused too: the Dock holds no `.thumbnails`.
        XCTAssertEqual(store(&index, key(3, dockBucket), .dockPreviews, now: 1), .refused)
    }

    func testAClientWithoutThumbnailsGetsNothingFromAnyLookup() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher)
        store(&index, key(1, dockBucket), .dockPreviews)
        index.setThumbnails(false, client: .dockPreviews)
        // The switcher's entry for window 1 is still there, but the Dock gets nothing, at any bucket.
        XCTAssertNotNil(index.entries[key(1, listBucket)])
        for bucket in [listBucket, dockBucket, previewBucket] {
            XCTAssertNil(index.lookup(windowID: 1, bucket: bucket, client: .dockPreviews, now: 1))
        }
        XCTAssertEqual(index.lookup(windowID: 1, bucket: dockBucket, client: .windowSwitcher, now: 1), key(1, listBucket))
    }

    func testEntriesAreSharedOnlyWhileBothClientsHoldThumbnails() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher)
        XCTAssertEqual(index.lookup(windowID: 1, bucket: dockBucket, client: .dockPreviews, now: 1), key(1, listBucket))
        // The switcher turns thumbnails off: its entries go, so the Dock can't see them either.
        XCTAssertEqual(index.setThumbnails(false, client: .windowSwitcher), [key(1, listBucket)])
        XCTAssertNil(index.lookup(windowID: 1, bucket: dockBucket, client: .dockPreviews, now: 1))
    }

    // MARK: Bucket lookup

    func testTheLookupTakesTheSmallestLargerBucketElseTheLargestSmallerOne() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher)
        store(&index, key(1, previewBucket), .windowSwitcher)
        store(&index, key(1, dockBucket), .dockPreviews)
        XCTAssertEqual(index.lookup(windowID: 1, bucket: 700, client: .dockPreviews, now: 1), key(1, dockBucket))
        XCTAssertEqual(index.lookup(windowID: 1, bucket: listBucket, client: .dockPreviews, now: 1), key(1, listBucket))
        XCTAssertEqual(index.lookup(windowID: 1, bucket: 800, client: .windowSwitcher, now: 1), key(1, previewBucket))
        XCTAssertEqual(index.lookup(windowID: 1, bucket: 3000, client: .windowSwitcher, now: 1), key(1, previewBucket))
        XCTAssertEqual(index.lookup(windowID: 1, bucket: 100, client: .windowSwitcher, now: 1), key(1, listBucket))
        XCTAssertNil(index.lookup(windowID: 2, bucket: listBucket, client: .windowSwitcher, now: 1))
        // With only a smaller one cached, the largest smaller one is shown.
        _ = index.purge(client: .windowSwitcher)
        XCTAssertEqual(index.lookup(windowID: 1, bucket: previewBucket, client: .windowSwitcher, now: 1),
                       key(1, dockBucket))
    }

    func testTheSameKeyTakenByAnotherClientMovesToThatClient() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher)
        store(&index, key(1, listBucket), .dockPreviews, now: 5)
        XCTAssertEqual(index.entries[key(1, listBucket)], .init(client: .dockPreviews, capturedAt: 5))
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index.purge(client: .windowSwitcher), [])
        XCTAssertEqual(index.purge(client: .dockPreviews), [key(1, listBucket)])
    }

    // MARK: 0.4's limits until A2a (D2-22)

    func testAnIndexKeepsFortyEntries() {
        var index = bothClients()
        XCTAssertEqual(index.limits, ThumbnailLimits(maxEntries: 40, maxAge: 300))
        for id in UInt32(1)...40 { store(&index, key(id, listBucket), .windowSwitcher, now: Double(id)) }
        XCTAssertEqual(index.count, 40)
        // Storing window 1 again makes it the most recent, so window 2 is the least recent.
        store(&index, key(1, listBucket), .windowSwitcher, now: 41)
        XCTAssertEqual(store(&index, key(41, dockBucket), .dockPreviews, now: 42), .stored(evicted: [key(2, listBucket)]))
        XCTAssertEqual(index.count, 40)
        XCTAssertNil(index.lookup(windowID: 2, bucket: listBucket, client: .windowSwitcher, now: 42))
        // A lookup doesn't make an entry recent, as in 0.4.
        _ = index.lookup(windowID: 3, bucket: listBucket, client: .windowSwitcher, now: 42)
        XCTAssertEqual(store(&index, key(42, dockBucket), .dockPreviews, now: 43), .stored(evicted: [key(3, listBucket)]))
    }

    func testAnEntryExpiresFiveMinutesAfterItsCapture() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher, now: 100)
        XCTAssertEqual(index.lookup(windowID: 1, bucket: listBucket, client: .windowSwitcher, now: 399.9),
                       key(1, listBucket))
        XCTAssertNil(index.lookup(windowID: 1, bucket: listBucket, client: .windowSwitcher, now: 400))
        // An expired entry is skipped by the lookup, which falls back to another bucket.
        store(&index, key(1, previewBucket), .windowSwitcher, now: 200)
        XCTAssertEqual(index.lookup(windowID: 1, bucket: listBucket, client: .windowSwitcher, now: 400),
                       key(1, previewBucket))
        // Prune drops the client's expired entries even for windows it keeps.
        XCTAssertEqual(index.prune(keeping: [1], client: .windowSwitcher, now: 400), [key(1, listBucket)])
        XCTAssertEqual(index.order, [key(1, previewBucket)])
    }
}
