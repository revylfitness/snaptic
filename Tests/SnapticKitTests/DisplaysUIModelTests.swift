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
}
