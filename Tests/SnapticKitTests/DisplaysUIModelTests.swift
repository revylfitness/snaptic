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

    // MARK: Mode choices

    private func mode(_ id: Int32, _ pw: Int, _ ph: Int, _ w: Int, _ h: Int, _ hz: Int) -> ModeRef {
        ModeRef(ioModeID: id, pixelWidth: pw, pixelHeight: ph, pointWidth: w, pointHeight: h, refreshMilliHz: hz)
    }

    func testChoicesDedupeAndPreferCurrentRefresh() {
        let modes = [
            mode(1, 3840, 2160, 1920, 1080, 60000), mode(2, 3840, 2160, 1920, 1080, 30000),
            mode(3, 1920, 1080, 1920, 1080, 60000), mode(4, 5120, 2880, 2560, 1440, 30000),
            mode(5, 5120, 2880, 2560, 1440, 60000), mode(6, 2560, 1440, 2560, 1440, 60000),
            mode(7, 0, 0, 0, 0, 60000),
        ]
        let current = mode(2, 3840, 2160, 1920, 1080, 30000)
        let result = DisplayModeChoices.choices(modes, current: current)
        XCTAssertEqual(result.map(\.ioModeID), [4, 6, 2, 3], "30 Hz preferred like the current mode; HiDPI first")
        let noCurrent = DisplayModeChoices.choices(modes, current: nil)
        XCTAssertEqual(noCurrent.map(\.ioModeID), [5, 6, 1, 3], "highest refresh without a current mode")
    }

    func testChoicesAlwaysIncludeCurrent() {
        let current = mode(9, 1680, 1050, 1680, 1050, 60000)
        XCTAssertEqual(DisplayModeChoices.choices([], current: current), [current])
        XCTAssertEqual(DisplayModeChoices.choices([], current: nil), [])
    }

    func testChoicesFuzzedAreUniquePerSize() {
        var rng = SeededGenerator(seed: 0xC401CE)
        for _ in 0..<1_000 {
            let modes = (0..<Int(rng.next() % 30)).map { i -> ModeRef in
                let w = [1280, 1440, 1920, 2560][Int(rng.next() % 4)]
                let scale = rng.next() % 2 == 0 ? 1 : 2
                return mode(Int32(i), w * scale, w * 9 / 16 * scale, w, w * 9 / 16, [30000, 50000, 60000][Int(rng.next() % 3)])
            }
            let current = modes.isEmpty || rng.next() % 3 == 0 ? nil : modes[Int(rng.next() % UInt64(modes.count))]
            let result = DisplayModeChoices.choices(modes, current: current)
            let sizes = result.map { "\($0.pointWidth)x\($0.pointHeight)x\($0.isHiDPI)" }
            XCTAssertEqual(Set(sizes).count, sizes.count)
            if let current { XCTAssertTrue(result.contains(current)) }
            XCTAssertEqual(result.map(\.pointWidth), result.map(\.pointWidth).sorted(by: >))
        }
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
