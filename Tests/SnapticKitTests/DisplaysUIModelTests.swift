import XCTest
@testable import SnapticKit

final class DisplaysUIModelTests: XCTestCase {
    private let all = Set(DisplayFeature.allCases)

    // MARK: Names

    func testEveryFeatureHasDistinctTitleAndSummary() {
        let titles = DisplayFeature.allCases.map(DisplaysUIText.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        for feature in DisplayFeature.allCases {
            XCTAssertFalse(DisplaysUIText.title(feature).isEmpty)
            XCTAssertFalse(DisplaysUIText.summary(feature).isEmpty)
        }
    }

    func testEveryFeaturePageIsListedAndNamed() {
        for feature in DisplayFeature.allCases {
            let page = FeatureGraph.spec(feature).page
            XCTAssertTrue(DisplaysUIText.pageOrder.contains(page), "\(feature) page \(page)")
            XCTAssertNotEqual(DisplaysUIText.pageTitle(page), page)
        }
        XCTAssertEqual(Set(DisplaysUIText.pageOrder).count, DisplaysUIText.pageOrder.count)
    }

    func testPermissionNameFollowsOS() {
        XCTAssertEqual(DisplaysUIText.permissionName(.accessibility, osMajor: 15), "Accessibility")
        XCTAssertEqual(DisplaysUIText.permissionName(.accessibility, osMajor: 27), "Device Control and Data Access")
        XCTAssertEqual(DisplaysUIText.permissionName(.screenRecording, osMajor: 27), "Screen & System Audio Recording")
    }

    func testInputNames() {
        XCTAssertEqual(DisplaysUIText.inputName(0x0F), "DisplayPort 1")
        XCTAssertEqual(DisplaysUIText.inputName(0x11), "HDMI 1")
        XCTAssertEqual(DisplaysUIText.inputName(0x0111), "HDMI 1", "the high byte is ignored")
        XCTAssertEqual(DisplaysUIText.inputName(0x42), "Input 0x42")
        XCTAssertFalse(DisplaysUIText.commonInputs.isEmpty)
    }

    func testModeAndRefreshLabels() {
        let m = ModeRef(ioModeID: 1, pixelWidth: 3840, pixelHeight: 2160, pointWidth: 1920, pointHeight: 1080, refreshMilliHz: 60000)
        XCTAssertEqual(DisplaysUIText.modeLabel(m), "1920 × 1080 HiDPI, 60 Hz")
        XCTAssertEqual(DisplaysUIText.refreshLabel(59940), "59.94 Hz")
        XCTAssertEqual(DisplaysUIText.refreshLabel(59500), "59.5 Hz")
        XCTAssertEqual(DisplaysUIText.refreshLabel(23976), "23.98 Hz")
        XCTAssertEqual(DisplaysUIText.refreshLabel(59999), "60 Hz")
        let lo = ModeRef(ioModeID: 2, pixelWidth: 1280, pixelHeight: 720, pointWidth: 1280, pointHeight: 720, refreshMilliHz: 0)
        XCTAssertEqual(DisplaysUIText.modeLabel(lo), "1280 × 720")
    }

    func testDiagonal() {
        XCTAssertEqual(DisplaysUIText.diagonalInches(widthMM: 597, heightMM: 336)!, 27, accuracy: 0.1)
        XCTAssertNil(DisplaysUIText.diagonalInches(widthMM: 0, heightMM: 300))
        XCTAssertNil(DisplaysUIText.diagonalInches(widthMM: .nan, heightMM: 300))
    }

    // MARK: Mode checks

    private func mode(_ id: Int32, _ pw: Int, _ ph: Int, _ w: Int, _ h: Int, _ hz: Int) -> ModeRef {
        ModeRef(ioModeID: id, pixelWidth: pw, pixelHeight: ph, pointWidth: w, pointHeight: h, refreshMilliHz: hz)
    }

    func testHiDPINearNative() {
        // 1440p monitor: macOS offers 1280×720 HiDPI at most.
        let qhd = [mode(1, 2560, 1440, 1280, 720, 60000), mode(2, 2560, 1440, 2560, 1440, 60000)]
        XCTAssertFalse(DisplayModeChoices.hasHiDPINearNative(qhd, nativePixelWidth: 2560))
        // 4K monitor: 2560×1440 HiDPI exists.
        let uhd = [mode(1, 5120, 2880, 2560, 1440, 60000), mode(2, 3840, 2160, 1920, 1080, 60000)]
        XCTAssertTrue(DisplayModeChoices.hasHiDPINearNative(uhd, nativePixelWidth: 3840))
        XCTAssertTrue(DisplayModeChoices.hasHiDPINearNative([], nativePixelWidth: 0))
    }

    // MARK: Onboarding

    func testBasicsTurnsOnTheStandardSetOnly() {
        let raw = DisplaysOnboardingPlan.raw(chips: [.basics], maxEDRPotential: 1, available: all)
        let on = Set(DisplaysOnboardingPlan.turnedOn(raw))
        let standard = Set(DisplayFeature.allCases.filter { FeatureGraph.spec($0).defaultState == .standard })
        XCTAssertEqual(on, standard)
        XCTAssertTrue(DisplaysOnboardingPlan.permissions(raw).isEmpty)
        // Every switchable feature is written, so the selection is exact.
        for f in DisplayFeature.allCases where FeatureGraph.spec(f).defaultState != .always {
            XCTAssertNotNil(raw[f], "\(f)")
        }
        XCTAssertNil(raw[.overview])
    }

    func testKeysChipNeedsAccessibility() {
        let raw = DisplaysOnboardingPlan.raw(chips: [.keys], maxEDRPotential: 1, available: all)
        XCTAssertEqual(raw[.brightnessKeys], true)
        XCTAssertEqual(raw[.volumeKeys], true)
        XCTAssertEqual(raw[.ddcControls], true)
        XCTAssertEqual(raw[.resolution], false)
        XCTAssertEqual(DisplaysOnboardingPlan.permissions(raw), [.accessibility])
    }

    func testExtraBrightnessOnlyWithEDR() {
        XCTAssertFalse(DisplaysOnboardingPlan.isOffered(.extraBrightness, maxEDRPotential: 1))
        XCTAssertTrue(DisplaysOnboardingPlan.isOffered(.extraBrightness, maxEDRPotential: 2))
        let without = DisplaysOnboardingPlan.raw(chips: [.extraBrightness], maxEDRPotential: 1, available: all)
        XCTAssertTrue(DisplaysOnboardingPlan.turnedOn(without).isEmpty)
        let with = DisplaysOnboardingPlan.raw(chips: [.extraBrightness], maxEDRPotential: 4, available: all)
        XCTAssertEqual(with[.xdr], true)
        XCTAssertEqual(with[.brightness], true, "closure turns on what XDR requires")
        XCTAssertEqual(with[.brightnessGamma], true, "first available 'any' requirement")
    }

    func testMoreHasNoBetaAndNoProtectionOrBroadcast() {
        let raw = DisplaysOnboardingPlan.raw(chips: [.more], maxEDRPotential: 4, available: all)
        let on = DisplaysOnboardingPlan.turnedOn(raw)
        XCTAssertFalse(on.contains { FeatureGraph.spec($0).beta })
        XCTAssertFalse(on.contains(.protection))
        XCTAssertFalse(on.contains(.osdBroadcast))
        XCTAssertTrue(on.contains(.layouts))
        XCTAssertTrue(on.contains(.color))
    }

    func testSharperTextExtraAndPIP() {
        let raw = DisplaysOnboardingPlan.raw(chips: [.sharperText, .pip], extra: [.smartHiDPI], maxEDRPotential: 1, available: all)
        XCTAssertEqual(raw[.resolution], true)
        XCTAssertEqual(raw[.smartHiDPI], true)
        XCTAssertEqual(raw[.pip], true)
        XCTAssertEqual(DisplaysOnboardingPlan.permissions(raw), [.screenRecording])
    }

    func testUnavailableAnyRequirementPicksNextAvailable() {
        let available = all.subtracting([.brightnessGamma])
        let raw = DisplaysOnboardingPlan.raw(chips: [.extraBrightness], maxEDRPotential: 4, available: available)
        XCTAssertEqual(raw[.brightnessOverlay], true)
        XCTAssertEqual(raw[.brightnessGamma], false)
    }

    func testFuzzedSelectionsAreClosed() {
        var rng = SeededGenerator(seed: 0xC41B5)
        let chips = OnboardingChip.allCases
        for _ in 0..<2_000 {
            let chosen = Set(chips.filter { _ in rng.next() % 2 == 0 })
            let available = Set(DisplayFeature.allCases.filter { _ in rng.next() % 8 != 0 })
            let raw = DisplaysOnboardingPlan.raw(chips: chosen, maxEDRPotential: Double(rng.next() % 3), available: available)
            // Everything turned on has its "all" requirements on as well.
            for f in DisplaysOnboardingPlan.turnedOn(raw) {
                for r in FeatureGraph.spec(f).requiresAll { XCTAssertEqual(raw[r], true, "\(f) needs \(r)") }
                let any = FeatureGraph.spec(f).requiresAny
                if !any.isEmpty { XCTAssertTrue(any.contains { raw[$0] == true }, "\(f) needs one of \(any)") }
            }
        }
    }

    // MARK: Display icons

    func testCuratedSymbolsPassTheIdentityRuleAndAreUnique() {
        let symbols = DisplaysUIText.displaySymbols.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count)
        XCTAssertEqual(Set(DisplaysUIText.displaySymbols.map(\.title)).count, symbols.count)
        for symbol in symbols {
            var identity = PerDisplayIdentity()
            identity.symbol = symbol
            XCTAssertEqual(identity.sanitized().symbol, symbol, "\(symbol) would be dropped by sanitized()")
            XCTAssertTrue(DisplaysUIText.isCuratedSymbol(symbol))
        }
        XCTAssertFalse(DisplaysUIText.isCuratedSymbol(nil))
        XCTAssertFalse(DisplaysUIText.isCuratedSymbol("trash"))
    }

    // MARK: EDID view

    func testEDIDHexAndBase64() {
        XCTAssertEqual(EDIDText.hex([]), "")
        XCTAssertEqual(EDIDText.hex([0x00, 0xFF, 0x0A], perLine: 2), "00 FF\n0A")
        let sample = EDIDInfoTests.sample()
        let lines = EDIDText.hex(sample).split(separator: "\n")
        XCTAssertEqual(lines.count, 8)
        XCTAssertEqual(lines.first, "00 FF FF FF FF FF FF 00 10 AC 34 12 78 56 34 12")
        XCTAssertEqual(Data(base64Encoded: EDIDText.base64(sample)), Data(sample))
        XCTAssertEqual(EDIDText.hex([1, 2, 3], perLine: 0), "01\n02\n03", "a zero width is treated as one")
    }

    func testEDIDSummaryRows() throws {
        let sample = EDIDInfoTests.sample(withCTA: true)
        let info = try XCTUnwrap(EDIDInfo.parse(sample))
        let rows = EDIDText.summary(info, byteCount: sample.count)
        let byLabel = Dictionary(rows.map { ($0.label, $0.value) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(byLabel["Manufacturer"], "DEL")
        XCTAssertEqual(byLabel["Product code"], "0x1234")
        XCTAssertEqual(byLabel["Product name"], "DELL U2720Q")
        XCTAssertEqual(byLabel["Serial number"], "••••23", "the serial is masked on the page")
        XCTAssertEqual(byLabel["Manufactured"], "Week 10, 2020")
        XCTAssertEqual(byLabel["EDID version"], "1.4")
        XCTAssertEqual(byLabel["Input"], "Digital")
        XCTAssertEqual(byLabel["Preferred timing"], "3840 × 2160")
        XCTAssertEqual(byLabel["HDR static metadata"], "Yes")
        XCTAssertEqual(byLabel["Extension blocks"], "1")
        XCTAssertEqual(byLabel["Checksums"], "Valid")
        XCTAssertEqual(byLabel["Size"], "256 bytes")
        XCTAssertTrue(byLabel["White point"]?.hasSuffix(", 0.329") == true)
        XCTAssertTrue(byLabel["Image size"]?.hasPrefix("597 × 336 mm") == true)
        XCTAssertFalse(rows.contains { $0.value.contains("ABC123") })
    }

    func testEDIDManufacturedAndFileName() {
        XCTAssertNil(EDIDText.manufactured(week: 10, year: 0))
        XCTAssertEqual(EDIDText.manufactured(week: 0, year: 2021), "2021")
        XCTAssertEqual(EDIDText.manufactured(week: 0xFF, year: 2021), "Model year 2021")
        XCTAssertEqual(EDIDText.manufactured(week: 60, year: 2021), "2021")
        XCTAssertEqual(EDIDText.exportFileName(displayName: "DELL U2720Q"), "DELL U2720Q EDID.bin")
        XCTAssertEqual(EDIDText.exportFileName(displayName: "../../etc/passwd"), "etcpasswd EDID.bin")
        XCTAssertEqual(EDIDText.exportFileName(displayName: "  "), "Display EDID.bin")
        XCTAssertLessThanOrEqual(EDIDText.exportFileName(displayName: String(repeating: "x", count: 500)).count, 57)
    }

    func testEDIDSummaryFuzzedNeverTraps() {
        var rng = SeededGenerator(seed: 0xED1D)
        let base = EDIDInfoTests.sample(withCTA: true)
        for _ in 0..<500 {
            var bytes = base
            for _ in 0..<Int(rng.next() % 40) { bytes[Int(rng.next() % UInt64(bytes.count))] = UInt8(rng.next() & 0xFF) }
            bytes = Array(bytes.prefix(Int(rng.next() % UInt64(bytes.count + 1))))
            guard let info = EDIDInfo.parse(bytes) else { continue }
            let rows = EDIDText.summary(info, byteCount: bytes.count)
            XCTAssertFalse(rows.isEmpty)
            XCTAssertFalse(EDIDText.hex(bytes).isEmpty)
        }
    }

    // MARK: Diagnostics

    func testMask() {
        XCTAssertEqual(DiagnosticsText.mask("ABC123456"), "••••56")
        XCTAssertEqual(DiagnosticsText.mask("123"), "••••")
        XCTAssertEqual(DiagnosticsText.shortKey(DisplayKey(rawValue: String(repeating: "ab", count: 16))!), "abab…")
    }

    func testScrubMasksIdentifierRows() {
        XCTAssertEqual(DiagnosticsText.scrub(label: "Serial number", value: "CN0123456789").value, "••••89")
        XCTAssertEqual(DiagnosticsText.scrub(label: "EDID UUID", value: "x").value, "••••")
        XCTAssertEqual(DiagnosticsText.scrub(label: "Transport", value: "wired").value, "wired")
    }

    func testScrubMasksUUIDsAndLongHexInText() {
        let text = "host for 1E2D3C4B-5A69-7887-96A5-B4C3D2E1F000 key 0123456789abcdef0123456789abcdef pid 4242"
        let out = DiagnosticsText.scrubText(text)
        XCTAssertFalse(out.contains("1E2D3C4B"))
        XCTAssertFalse(out.contains("0123456789abcdef"))
        XCTAssertTrue(out.contains("pid 4242"))
        XCTAssertTrue(out.contains("••••00"))
        XCTAssertEqual(DiagnosticsText.scrubText("line\nbreak\u{7}"), "line break?")
        XCTAssertEqual(DiagnosticsText.scrubText(String(repeating: "z", count: 2000)).count, DiagnosticsText.maxValueLength)
    }

    func testReportLayout() {
        let report = DiagnosticsText.report(
            header: "Snaptic diagnostics",
            sections: [DiagnosticsSection(title: "System", rows: [DiagnosticsRow("OS", "15.1")]),
                       DiagnosticsSection(title: "Empty", rows: [])],
            events: ["10:00:00 [modules] started"])
        XCTAssertTrue(report.hasPrefix("Snaptic diagnostics\n"))
        XCTAssertTrue(report.contains("## System\n- OS: 15.1\n"))
        XCTAssertTrue(report.contains("## Empty\n(none)\n"))
        XCTAssertTrue(report.contains("## Recent events (1)\n10:00:00 [modules] started\n"))
    }

    // MARK: W7, W17a

    func testTurnOffListsAndClearsDependents() {
        // .pipFilters requires .pip.
        var raw: [DisplayFeature: Bool] = [.pip: true, .pipFilters: true]
        let deps = FeatureTurnOff.dependents(of: .pip, raw: raw, effective: [.pip, .pipFilters])
        XCTAssertEqual(deps, [.pipFilters])
        let changes = FeatureTurnOff.changes(.pip, dependents: deps)
        XCTAssertEqual(changes, [.pip: false, .pipFilters: false])
        for (f, on) in changes { raw[f] = on }
        // Turning PIP on again brings only PIP back.
        let after = FeatureGraph.enabling(.pip, raw: raw, available: Set(DisplayFeature.allCases))
        XCTAssertEqual(after[.pipFilters], false, "W7: the dependent's flag stays off")
    }

    func testTurnOffIncludesSwitchedOnButPausedDependents() {
        let raw: [DisplayFeature: Bool] = [.pip: true, .pipFilters: true]
        // Filters on but not effective (e.g. paused): still listed, since its flag goes off.
        XCTAssertEqual(FeatureTurnOff.dependents(of: .pip, raw: raw, effective: [.pip]), [.pipFilters])
        XCTAssertEqual(FeatureTurnOff.dependents(of: .pipFilters, raw: raw, effective: [.pip, .pipFilters]), [])
    }

    func testTurnOffNeverTouchesAlwaysOnAndIsClosedForEveryFeature() {
        let all = Set(DisplayFeature.allCases)
        var raw: [DisplayFeature: Bool] = [:]
        for f in DisplayFeature.allCases { raw[f] = true }
        let effective = FeatureGraph.resolve(raw: raw, killSwitches: [], safeMode: false, unavailable: [], panicLatch: false)
        for feature in DisplayFeature.allCases where FeatureGraph.spec(feature).defaultState != .always {
            let deps = FeatureTurnOff.dependents(of: feature, raw: raw, effective: effective)
            XCTAssertFalse(deps.contains(feature))
            XCTAssertTrue(deps.allSatisfy { FeatureGraph.spec($0).defaultState != .always })
            var after = raw
            for (f, on) in FeatureTurnOff.changes(feature, dependents: deps) { after[f] = on }
            // Nothing left switched on depends on what went off: the raw flags match what runs.
            let resolved = FeatureGraph.resolve(raw: after, killSwitches: [], safeMode: false, unavailable: [], panicLatch: false)
            let switchedOn = all.filter { FeatureGraph.rawState($0, in: after) }
            XCTAssertEqual(resolved, switchedOn, "turning off \(feature) leaves no orphaned flags")
        }
    }

    func testHeaderNeverActsAndDisclosureIsDedicated() {
        XCTAssertFalse(DisplayBlockDisclosure.headerClickActs)
        XCTAssertEqual(DisplayBlockDisclosure.control(showHeader: true, forceExpanded: false, collapsed: false), .collapse)
        XCTAssertEqual(DisplayBlockDisclosure.control(showHeader: true, forceExpanded: false, collapsed: true), .expand)
        XCTAssertEqual(DisplayBlockDisclosure.control(showHeader: true, forceExpanded: true, collapsed: true), .none)
        XCTAssertEqual(DisplayBlockDisclosure.control(showHeader: false, forceExpanded: false, collapsed: true), .none)
    }
}

// MARK: - 0.3 root page, feature groups, live resolution, diagnostics events (F step 2)

final class DisplaysRootModelTests: XCTestCase {
    private func mode(_ w: Int, _ h: Int, hiDPI: Bool = true, hz: Int = 60, id: Int32 = 1, isDefault: Bool = false,
                      native: Bool = false, depth: Int = 8) -> DisplayModeDescriptor {
        let scale = hiDPI ? 2 : 1
        let ref = ModeRef(ioModeID: id, pixelWidth: w * scale, pixelHeight: h * scale, pointWidth: w, pointHeight: h,
                          refreshMilliHz: hz * 1000)
        return DisplayModeDescriptor(ref: ref, isNative: native, isDefault: isDefault, isUsableForDesktop: true,
                                     ioFlags: 0, bitDepth: depth)
    }

    func testStatusLine() {
        XCTAssertEqual(DisplaysRootText.status(displayCount: 0), "No displays")
        XCTAssertEqual(DisplaysRootText.status(displayCount: -3), "No displays")
        XCTAssertEqual(DisplaysRootText.status(displayCount: 1), "1 display")
        XCTAssertEqual(DisplaysRootText.status(displayCount: 2), "2 displays")
        XCTAssertNil(DisplaysRootText.navigationValue(isOn: nil))
        XCTAssertEqual(DisplaysRootText.navigationValue(isOn: true), "On")
        XCTAssertEqual(DisplaysRootText.navigationValue(isOn: false), "Off")
    }

    // MARK: Feature groups (PLAN 0.3 §4.8 "Displays: feature switches")

    func testUseSnapticForMatchesThePlan() {
        let useFor = Set(DisplaysFeatureGroupsModel.useSnapticFor.flatMap(\.features))
        XCTAssertEqual(useFor, [.resolution, .brightness, .shortcuts, .osd, .rotation, .disconnect, .mainDisplay,
                                .arrangement, .mirroring])
        let experimental = Set(DisplaysFeatureGroupsModel.experimental.flatMap(\.features))
        XCTAssertEqual(experimental, [.hiddenModes, .autoBrightness, .osdBroadcast, .underscan, .hdrToggle])
        XCTAssertTrue(useFor.isDisjoint(with: experimental))
        let all = DisplaysFeatureGroupsModel.useSnapticFor + DisplaysFeatureGroupsModel.experimental
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        for item in all {
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertLessThanOrEqual(item.help.count, 90, item.id)
            XCTAssertTrue(item.help.hasSuffix("."), item.id)
            XCTAssertFalse(item.title.lowercased().hasPrefix("enable"), item.id)
            XCTAssertTrue(item.features.allSatisfy { FeatureGraph.spec($0).defaultState != .always }, item.id)
        }
        XCTAssertTrue(DisplaysFeatureGroupsModel.experimental.allSatisfy { $0.badge == .experimental })
        XCTAssertEqual(DisplaysFeatureGroupsModel.useSnapticFor.first { $0.id == "disconnect" }?.badge, .beta)
    }

    func testArrangementSwitchWritesAllThreeAndShowsArrangement() {
        guard let item = DisplaysFeatureGroupsModel.useSnapticFor.first(where: { $0.id == "arrangement" }) else {
            return XCTFail("arrangement switch")
        }
        XCTAssertEqual(item.shown, .arrangement)
        XCTAssertEqual(DisplaysFeatureGroupsModel.changes(item, on: true),
                       [.arrangement: true, .mainDisplay: true, .mirroring: true])
        XCTAssertEqual(DisplaysFeatureGroupsModel.changes(item, on: false),
                       [.arrangement: false, .mainDisplay: false, .mirroring: false])
        var raw: [DisplayFeature: Bool] = [.arrangement: true, .mainDisplay: false, .mirroring: true]
        XCTAssertTrue(item.isOn(raw: raw))
        XCTAssertTrue(item.isMixed(raw: raw))
        raw[.mainDisplay] = true
        XCTAssertFalse(item.isMixed(raw: raw))
    }

    // MARK: Live resolution

    func testSizesPutDefaultFirstThenLargestAndMarkLowResolutionTwins() {
        let modes = [
            mode(1280, 832, id: 1),
            mode(1512, 982, id: 2, isDefault: true),
            mode(1512, 982, hz: 120, id: 3),
            mode(1800, 1169, id: 4),
            mode(1800, 1169, hiDPI: false, id: 5),
            mode(3024, 1964, hiDPI: false, id: 6, native: true),
        ]
        let sizes = LiveResolution.sizes(modes, current: modes[1].ref, favorites: [modes[0].ref])
        XCTAssertEqual(sizes.map(\.title), ["Default — 1512 × 982", "3024 × 1964", "1800 × 1169",
                                            "1800 × 1169 (low resolution)", "1280 × 832"])
        XCTAssertEqual(sizes.filter(\.isDefault).count, 1)
        XCTAssertTrue(sizes[4].isFavorite)
        XCTAssertTrue(sizes[1].isNative)
        XCTAssertEqual(Set(sizes.map(\.id)).count, sizes.count)
    }

    func testCurrentSizeIsAlwaysListedAndZeroSizesAreIgnored() {
        let current = mode(1024, 768, hiDPI: false, id: 9).ref
        let sizes = LiveResolution.sizes([mode(1920, 1080), mode(0, 0)], current: current)
        XCTAssertEqual(sizes.map(\.title), ["1920 × 1080", "1024 × 768"])
        XCTAssertTrue(LiveResolution.sizes([], current: nil).isEmpty)
    }

    func testOnlyOneDefaultAndTheHiDPIOneWins() {
        let sizes = LiveResolution.sizes([mode(1920, 1080, hiDPI: false, id: 1, isDefault: true),
                                          mode(1440, 900, id: 2, isDefault: true)], current: nil)
        XCTAssertEqual(sizes.first?.title, "Default — 1440 × 900")
        XCTAssertEqual(sizes.filter(\.isDefault).count, 1)
    }

    func testSizeChoiceKeepsTheRefreshRateWhenItCan() {
        let current = mode(1512, 982, hz: 120, id: 3).ref
        let modes = [mode(1800, 1169, hz: 60, id: 4), mode(1800, 1169, hz: 120, id: 5), mode(1800, 1169, hz: 100, id: 6),
                     mode(1280, 832, hz: 60, id: 7)]
        let id1800 = LiveResolution.sizeID(pointWidth: 1800, pointHeight: 1169, hiDPI: true)
        XCTAssertEqual(LiveResolution.mode(forSize: id1800, in: modes, current: current)?.ioModeID, 5)
        let id1280 = LiveResolution.sizeID(pointWidth: 1280, pointHeight: 832, hiDPI: true)
        XCTAssertEqual(LiveResolution.mode(forSize: id1280, in: modes, current: current)?.ioModeID, 7)
        XCTAssertEqual(LiveResolution.mode(forSize: LiveResolution.sizeID(of: current), in: modes, current: current), current)
        XCTAssertNil(LiveResolution.mode(forSize: "1x1h", in: modes, current: current))
    }

    func testSizeChoicePrefersDeeperColorOnATie() {
        let modes = [mode(1920, 1080, id: 1, depth: 8), mode(1920, 1080, id: 2, depth: 10)]
        let id = LiveResolution.sizeID(pointWidth: 1920, pointHeight: 1080, hiDPI: true)
        XCTAssertEqual(LiveResolution.mode(forSize: id, in: modes, current: nil)?.ioModeID, 2)
    }

    func testRefreshRatesForTheCurrentSize() {
        let current = mode(1512, 982, hz: 120, id: 3).ref
        var modes = [mode(1512, 982, hz: 60, id: 2), mode(1512, 982, hz: 120, id: 3), mode(1800, 1169, hz: 50, id: 4)]
        modes.append(DisplayModeDescriptor(ref: ModeRef(ioModeID: 8, pixelWidth: 3024, pixelHeight: 1964, pointWidth: 1512,
                                                        pointHeight: 982, refreshMilliHz: 59_940),
                                           isNative: false, isDefault: false, isUsableForDesktop: true, ioFlags: 0,
                                           bitDepth: 8))
        modes.append(DisplayModeDescriptor(ref: ModeRef(ioModeID: 9, pixelWidth: 3024, pixelHeight: 1964, pointWidth: 1512,
                                                        pointHeight: 982, refreshMilliHz: 60_004),
                                           isNative: false, isDefault: false, isUsableForDesktop: true, ioFlags: 0,
                                           bitDepth: 8))
        let rates = LiveResolution.refreshRates(modes, current: current)
        XCTAssertEqual(rates.map(\.title), ["120 Hz", "60 Hz", "59.94 Hz"])
        XCTAssertEqual(LiveResolution.choice(for: 60_003, in: rates), 60_000)
        XCTAssertNil(LiveResolution.choice(for: 75_000, in: rates))
        XCTAssertEqual(LiveResolution.mode(forRefresh: 60_000, in: modes, current: current)?.ioModeID, 2)
        XCTAssertEqual(LiveResolution.mode(forRefresh: 120_000, in: modes, current: current), current)
        XCTAssertNil(LiveResolution.mode(forRefresh: 50_000, in: modes, current: current))
        XCTAssertTrue(LiveResolution.refreshRates(modes, current: nil).isEmpty)
    }

    /// Seeded fuzz: whatever the mode list, the pop-ups are consistent with it.
    func testResolutionChoicesFuzz() {
        var rng = SeededGenerator(seed: 0xF0_2026)
        func pick(_ n: Int) -> Int { Int(rng.next() % UInt64(n)) }
        let widths = [0, 800, 1024, 1280, 1512, 1920, 2560]
        let rates = [0, 50_000, 59_940, 60_000, 60_005, 120_000]
        for _ in 0..<400 {
            var modes: [DisplayModeDescriptor] = []
            for i in 0..<pick(12) {
                let w = widths[pick(widths.count)]
                modes.append(mode(w, w * 10 / 16, hiDPI: pick(2) == 0, hz: 0, id: Int32(i), isDefault: pick(5) == 0,
                                  depth: [8, 10][pick(2)]))
                modes[modes.count - 1].ref.refreshMilliHz = rates[pick(rates.count)]
            }
            let current: ModeRef? = modes.isEmpty || pick(4) == 0 ? nil : modes[pick(modes.count)].ref
            let sizes = LiveResolution.sizes(modes, current: current)
            XCTAssertEqual(Set(sizes.map(\.id)).count, sizes.count)
            XCTAssertLessThanOrEqual(sizes.filter(\.isDefault).count, 1)
            if sizes.contains(where: \.isDefault) { XCTAssertTrue(sizes[0].isDefault) }
            if let current, current.pointWidth > 0, current.pointHeight > 0 {
                XCTAssertTrue(sizes.contains { $0.id == LiveResolution.sizeID(of: current) })
            }
            for size in sizes {
                if let chosen = LiveResolution.mode(forSize: size.id, in: modes, current: current) {
                    XCTAssertEqual(LiveResolution.sizeID(of: chosen), size.id)
                } else {
                    XCTAssertEqual(current.map(LiveResolution.sizeID(of:)), size.id, "only the current size may be unlisted")
                }
            }
            let refresh = LiveResolution.refreshRates(modes, current: current)
            XCTAssertEqual(refresh.map(\.milliHz), refresh.map(\.milliHz).sorted(by: >))
            for (a, b) in zip(refresh, refresh.dropFirst()) {
                XCTAssertGreaterThan(a.milliHz - b.milliHz, LiveResolution.refreshTolerance)
            }
            for rate in refresh {
                if let chosen = LiveResolution.mode(forRefresh: rate.milliHz, in: modes, current: current), let current {
                    XCTAssertEqual(LiveResolution.sizeID(of: chosen), LiveResolution.sizeID(of: current))
                }
            }
        }
    }

    // MARK: Diagnostics events

    func testExportedEventsDropAwakeAndKeepTheNewest() {
        let awake = EventCategory(rawValue: "awake")
        let entries: [(Int, EventCategory)] = [(1, .modules), (2, awake), (3, .ddc), (4, awake), (5, .registry)]
        let kept = DiagnosticsText.exportedEvents(entries, category: { $0.1 }, limit: 2)
        XCTAssertEqual(kept.map { $0.0 }, [3, 5])
        XCTAssertEqual(DiagnosticsText.exportedEvents(entries, category: { $0.1 }, limit: 10).map { $0.0 }, [1, 3, 5])
        XCTAssertTrue(DiagnosticsText.exportedEvents(entries, category: { $0.1 }, limit: 0).isEmpty)
        XCTAssertTrue(DiagnosticsText.exportedEvents(entries, category: { $0.1 }, limit: -1).isEmpty)
    }
}
