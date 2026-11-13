import XCTest
@testable import SnapticKit

// 0.5 A1b (§2.3, §2.5, D2-14, X2-11, X2-12, D2-22): the thumbnail index's client cases — isolation between clients,
// stamps, the last release, last-seen entries across a switcher open, `.thumbnails` lookups, the bucket lookup and
// 0.4's limits. A2a (§2.3, §2.5, §4.9, §4.10, X2-13, X3-10): the budget cases — 120 entries, 96 MB, the oversize
// skip, the 30-minute expiry and `nextExpiry` — plus the privacy drop and the 30 s pacing rule.

private let dockBucket = 720
private let listBucket = 640
private let previewBucket = 2400

private func key(_ id: UInt32, _ bucket: Int) -> ThumbnailKey { ThumbnailKey(windowID: id, bucket: bucket) }

/// Both clients hold `.thumbnails`, as their leases would after `acquire`.
private func bothClients(_ limits: ThumbnailLimits = .v05) -> ThumbnailIndex {
    var index = ThumbnailIndex(limits: limits)
    index.setThumbnails(true, client: .windowSwitcher)
    index.setThumbnails(true, client: .dockPreviews)
    return index
}

@discardableResult
private func store(_ index: inout ThumbnailIndex, _ key: ThumbnailKey, _ client: ModuleID, now: Double = 0,
                   bytes: Int = 0) -> ThumbnailIndex.InsertResult {
    index.insert(key, stamp: index.stamp(for: client), now: now, bytes: bytes)
}

/// `bytesPerRow × height` of a 32-bit image, as `WindowCapture` counts it.
private func imageBytes(_ width: Int, _ height: Int) -> Int { width * 4 * height }

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
        XCTAssertEqual(index.totalBytes, 0)
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index.purge(client: .windowSwitcher), [])
        XCTAssertEqual(index.purge(client: .dockPreviews), [key(1, listBucket)])
    }

    // MARK: 0.4's limits, no longer the default (D2-22)

    func testTheV04LimitsKeepFortyEntries() {
        var index = bothClients(.v04)
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

    func testAV04EntryExpiresFiveMinutesAfterItsCapture() {
        var index = bothClients(.v04)
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

    // MARK: A2a's budget (§2.3, §4.9, X2-13)

    func testTheDefaultLimitsAre120Entries96MBAnd30Minutes() {
        let index = ThumbnailIndex()
        XCTAssertEqual(index.limits, .v05)
        XCTAssertEqual(index.limits.maxEntries, 120)
        XCTAssertEqual(index.limits.maxBytes, 96_000_000)
        XCTAssertEqual(index.limits.maxEntryBytes, 16_000_000)
        XCTAssertEqual(index.limits.maxAge, 30 * 60)
    }

    func testAnIndexKeeps120Entries() {
        var index = bothClients()
        // Small images, so the entry count binds before the bytes do (120 × 160 KB = 19.2 MB).
        let small = imageBytes(200, 200)
        for id in UInt32(1)...120 {
            store(&index, key(id, listBucket), .windowSwitcher, now: Double(id), bytes: small)
        }
        XCTAssertEqual(index.count, 120)
        XCTAssertEqual(index.totalBytes, 120 * small)
        // The 121st evicts the least recently stored, whoever owns it.
        XCTAssertEqual(store(&index, key(121, dockBucket), .dockPreviews, now: 121, bytes: small),
                       .stored(evicted: [key(1, listBucket)]))
        XCTAssertEqual(index.count, 120)
        XCTAssertEqual(index.totalBytes, 120 * small)
    }

    func testAnIndexKeeps96MBEvictingTheLeastRecentlyStored() {
        var index = bothClients()
        store(&index, key(1, dockBucket), .dockPreviews, now: 1, bytes: 5_000_000)
        store(&index, key(2, dockBucket), .dockPreviews, now: 2, bytes: 5_000_000)
        for id in UInt32(3)...8 {
            store(&index, key(id, previewBucket), .windowSwitcher, now: Double(id), bytes: 14_000_000)
        }
        XCTAssertEqual(index.totalBytes, 94_000_000)
        // Storing a key again counts only its new bytes, and makes it the most recent.
        store(&index, key(2, dockBucket), .dockPreviews, now: 9, bytes: 1_000)
        XCTAssertEqual(index.totalBytes, 89_001_000)
        // 16 MB more is over 96 MB: the least recently stored go, whoever owns them, until it fits.
        XCTAssertEqual(store(&index, key(9, previewBucket), .windowSwitcher, now: 10, bytes: 16_000_000),
                       .stored(evicted: [key(1, dockBucket), key(3, previewBucket)]))
        XCTAssertEqual(index.totalBytes, 86_001_000)
        XCTAssertEqual(index.count, 7)
        // Purges give the bytes back.
        _ = index.purge(client: .dockPreviews)
        XCTAssertEqual(index.totalBytes, 86_000_000)
        _ = index.purgeAll()
        XCTAssertEqual(index.totalBytes, 0)
    }

    func testAnEntryOver16MBIsSkippedNotStored() {
        var index = bothClients()
        // A 2400-pixel preview of a 3:2 window fits; a squarer 4:3 one is over 16 MB (X3-10).
        XCTAssertEqual(imageBytes(2400, 1600), 15_360_000)
        XCTAssertEqual(store(&index, key(1, previewBucket), .windowSwitcher, now: 1, bytes: imageBytes(2400, 1600)),
                       .stored(evicted: []))
        XCTAssertEqual(store(&index, key(1, previewBucket), .windowSwitcher, now: 2, bytes: imageBytes(2400, 1800)),
                       .skipped)
        // The key's previous entry stays, and nothing else moves.
        XCTAssertEqual(index.entries[key(1, previewBucket)]?.capturedAt, 1)
        XCTAssertEqual(index.totalBytes, 15_360_000)
        XCTAssertEqual(store(&index, key(2, previewBucket), .windowSwitcher, now: 3, bytes: 16_000_000),
                       .stored(evicted: []))
        XCTAssertEqual(store(&index, key(3, previewBucket), .windowSwitcher, now: 4, bytes: 16_000_001), .skipped)
        XCTAssertNil(index.entries[key(3, previewBucket)])
        // A stale stamp is refused before its size counts.
        let stale = index.stamp(for: .windowSwitcher)
        index.invalidate(client: .windowSwitcher)
        XCTAssertEqual(index.insert(key(4, previewBucket), stamp: stale, now: 5, bytes: 20_000_000), .refused)
    }

    func testAnEntryExpiresThirtyMinutesAfterItsCapture() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher, now: 100)
        XCTAssertEqual(index.lookup(windowID: 1, bucket: listBucket, client: .windowSwitcher, now: 1_899.9),
                       key(1, listBucket))
        XCTAssertNil(index.lookup(windowID: 1, bucket: listBucket, client: .windowSwitcher, now: 1_900))
        // Five minutes no longer expire anything.
        XCTAssertEqual(index.prune(keeping: [1], client: .windowSwitcher, now: 400), [])
        XCTAssertEqual(index.prune(keeping: [1], client: .windowSwitcher, now: 1_900), [key(1, listBucket)])
    }

    func testNextExpiryIsTheOldestEntrysAndTheSweepDropsWhatExpired() {
        var index = bothClients()
        XCTAssertNil(index.nextExpiry)   // an empty store has no timer
        store(&index, key(1, listBucket), .windowSwitcher, now: 100, bytes: 10)
        store(&index, key(2, dockBucket), .dockPreviews, now: 50, bytes: 20)
        store(&index, key(3, listBucket), .windowSwitcher, now: 300, bytes: 30)
        XCTAssertEqual(index.nextExpiry, 1_850)
        XCTAssertEqual(index.expire(now: 1_849), [])
        // The sweep drops every client's expired entries, then the timer moves to the next one.
        XCTAssertEqual(index.expire(now: 1_910), [key(1, listBucket), key(2, dockBucket)])
        XCTAssertEqual(index.nextExpiry, 2_100)
        XCTAssertEqual(index.totalBytes, 30)
        XCTAssertEqual(index.expire(now: 2_100), [key(3, listBucket)])
        XCTAssertNil(index.nextExpiry)
        XCTAssertEqual(index.totalBytes, 0)
    }

    func testEachEntryRecordsItsSourceAndCaptureTime() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher, now: 5, bytes: 100)
        let stamp = index.stamp(for: .dockPreviews)
        XCTAssertEqual(index.insert(key(2, dockBucket), stamp: stamp, now: 6, bytes: 200, source: .privateCapture),
                       .stored(evicted: []))
        XCTAssertEqual(index.entries[key(1, listBucket)],
                       .init(client: .windowSwitcher, capturedAt: 5, bytes: 100, source: .sck))
        XCTAssertEqual(index.entries[key(2, dockBucket)]?.source, .privateCapture)
        XCTAssertEqual(ThumbnailSource.privateCapture.rawValue, "private")
    }

    // MARK: Privacy (§4.10)

    func testAWindowThatTurnsPrivateLosesEveryClientsEntries() {
        var index = bothClients()
        store(&index, key(1, listBucket), .windowSwitcher, bytes: 10)
        store(&index, key(1, previewBucket), .windowSwitcher, bytes: 20)
        store(&index, key(1, dockBucket), .dockPreviews, bytes: 30)
        store(&index, key(2, listBucket), .windowSwitcher, bytes: 40)
        XCTAssertEqual(index.forget(windowIDs: [1]), [key(1, listBucket), key(1, previewBucket), key(1, dockBucket)])
        XCTAssertEqual(index.order, [key(2, listBucket)])
        XCTAssertEqual(index.totalBytes, 40)
        XCTAssertNil(index.lookup(windowID: 1, bucket: dockBucket, client: .dockPreviews, now: 1))
        XCTAssertEqual(index.forget(windowIDs: []), [])
    }

    // MARK: Pacing (§4.9)

    func testAWindowIsCapturedAtMostOncePer30SecondsUnlessItsDirty() {
        var index = bothClients()
        XCTAssertTrue(index.needsCapture(windowID: 1, bucket: listBucket, client: .windowSwitcher, now: 0))
        store(&index, key(1, listBucket), .windowSwitcher, now: 0)
        XCTAssertFalse(index.needsCapture(windowID: 1, bucket: listBucket, client: .windowSwitcher, now: 29.9))
        XCTAssertTrue(index.needsCapture(windowID: 1, bucket: listBucket, client: .windowSwitcher, now: 30))
        // A dirty window is captured again at once; the new capture clears it.
        index.markDirty([1])
        XCTAssertTrue(index.needsCapture(windowID: 1, bucket: listBucket, client: .windowSwitcher, now: 1))
        store(&index, key(1, listBucket), .windowSwitcher, now: 2)
        XCTAssertFalse(index.needsCapture(windowID: 1, bucket: listBucket, client: .windowSwitcher, now: 3))
        // Another client's fresh, larger capture counts; a smaller one doesn't.
        store(&index, key(2, dockBucket), .dockPreviews, now: 0)
        XCTAssertFalse(index.needsCapture(windowID: 2, bucket: listBucket, client: .windowSwitcher, now: 1))
        XCTAssertTrue(index.needsCapture(windowID: 1, bucket: dockBucket, client: .dockPreviews, now: 3))
        // Without `.thumbnails` the lookup is empty, so nothing counts as fresh.
        index.setThumbnails(false, client: .dockPreviews)
        XCTAssertTrue(index.needsCapture(windowID: 1, bucket: dockBucket, client: .dockPreviews, now: 3))
    }
}
