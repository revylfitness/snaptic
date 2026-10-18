import XCTest
@testable import SnapticKit

final class ConfigPIPTests: XCTestCase {
    private let keyA = DisplayKey(rawValue: String(repeating: "a", count: 32))!
    private let keyB = DisplayKey(rawValue: String(repeating: "b", count: 32))!

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    // MARK: Configuration model

    func testDefaults() {
        let c = PIPConfiguration()
        XCTAssertEqual(c.kind, .window)
        XCTAssertEqual(c.level, .floating)
        XCTAssertEqual(c.opacity, 1)
        XCTAssertEqual(c.fps, 30)
        XCTAssertTrue(c.lockAspect)
        XCTAssertNil(c.crop)
        XCTAssertFalse(c.autoStart)
        XCTAssertEqual(c.sanitized(), c)
        let g = PIPConfig()
        XCTAssertEqual(g.protectedBundlePrefixes, PIPPrivacy.defaultProtectedPrefixes)
        XCTAssertTrue(g.pauseWhenOccluded)
        XCTAssertTrue(g.stopHotkeyEnabled)
        XCTAssertEqual(g.sanitized(), g)
        XCTAssertEqual(PerDisplayPIP().sanitized(), PerDisplayPIP())
    }

    func testRoundTrip() throws {
        var c = PIPConfiguration(name: "Office", kind: .fullScreen)
        c.target = keyB
        c.crop = PIPRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5)
        c.windowFrame = PIPRect(x: 10, y: 20, width: 640, height: 360)
        c.filters = [FilterInstance(kind: .sepia), FilterInstance(kind: .gaussianBlur, enabled: false)]
        c.lutID = StableID()
        c.rotation = 90
        c.scaling = .integer
        c.nativeModeWhileStreaming = true
        XCTAssertEqual(try roundTrip(c), c)

        var g = PIPConfig()
        g.windowConfigurations = [PIPConfiguration(name: "Window")]
        g.luts = [PIPLUTReference(name: "Film", size: 33)]
        g.firstRunAcknowledged = true
        XCTAssertEqual(try roundTrip(g), g)

        var config = DisplaysConfig()
        PIPConfig.add(c, source: .display(keyA), to: &config)
        let decoded = try roundTrip(config)
        XCTAssertEqual(decoded.perDisplay[keyA]?.pip.configurations, [c])
    }

    func testLossyDecoding() throws {
        let json = """
        {"id":"not-a-uuid","name":17,"kind":"hologram","opacity":"x","fps":60,"rotation":180,
         "crop":{"x":"bad"},"filters":[{"kind":"sepia"},{"kind":"nope"}],"level":"aboveAll","target":"zz"}
        """
        let c = try JSONDecoder().decode(PIPConfiguration.self, from: Data(json.utf8))
        XCTAssertEqual(c.name, PIPConfiguration().name)
        XCTAssertEqual(c.kind, .window)
        XCTAssertEqual(c.opacity, 1)
        XCTAssertEqual(c.fps, 60)
        XCTAssertEqual(c.rotation, 180)
        XCTAssertNil(c.crop)
        XCTAssertNil(c.target)
        XCTAssertEqual(c.level, .aboveAll)
        XCTAssertEqual(c.filters.map(\.kind), [.sepia])

        let g = try JSONDecoder().decode(PIPConfig.self, from: Data(#"{"windowConfigurations":[1,{},{"name":"ok"}],"luts":"x"}"#.utf8))
        XCTAssertEqual(g.windowConfigurations.count, 2)
        XCTAssertEqual(g.windowConfigurations[1].name, "ok")
        XCTAssertEqual(g.luts, [])
        XCTAssertEqual(g.protectedBundlePrefixes, PIPPrivacy.defaultProtectedPrefixes)

        let empty = try JSONDecoder().decode(PerDisplayPIP.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, PerDisplayPIP())
    }

    /// Every PIP list decodes through Kit `LossyArray`: attempts are bounded (a long run of bad elements stops the
    /// read, so a valid element past the cap is never reached), not successes; the sanitizers then apply the caps.
    func testListDecodingBoundsAttemptsNotSuccesses() throws {
        let cap = LossyArray<PIPConfiguration>.maxElements
        let garbage = Array(repeating: "1", count: cap).joined(separator: ",")
        let late = #"{"name":"late"}"#
        let g = try JSONDecoder().decode(PIPConfig.self, from: Data(
            #"{"windowConfigurations":[\#(garbage),\#(late)],"luts":[\#(garbage),{"name":"L","size":33}]}"#.utf8))
        XCTAssertEqual(g.windowConfigurations, [])
        XCTAssertEqual(g.luts, [])
        let per = try JSONDecoder().decode(PerDisplayPIP.self, from: Data(#"{"configurations":[\#(garbage),\#(late)]}"#.utf8))
        XCTAssertEqual(per.configurations, [])

        // Bad elements before the cap are skipped and the rest kept.
        let mixed = try JSONDecoder().decode(PIPConfig.self, from: Data(#"{"windowConfigurations":[1,"x",\#(late),null]}"#.utf8))
        XCTAssertEqual(mixed.windowConfigurations.map(\.name), ["late"])

        // Valid elements past the old 256-success stop still decode; sanitizing applies the real caps.
        let filters = Array(repeating: #"{"kind":"sepia"}"#, count: 300).joined(separator: ",")
        let c = try JSONDecoder().decode(PIPConfiguration.self, from: Data(#"{"filters":[\#(filters)]}"#.utf8))
        XCTAssertEqual(c.filters.count, 300)
        XCTAssertEqual(c.sanitized().filters.count, PIPConfiguration.maxFilters)
        let many = Array(repeating: late, count: 300).joined(separator: ",")
        let big = try JSONDecoder().decode(PIPConfig.self, from: Data(#"{"windowConfigurations":[\#(many)]}"#.utf8))
        XCTAssertEqual(big.windowConfigurations.count, 300)
        XCTAssertEqual(big.sanitized().windowConfigurations.count, PIPConfig.maxWindowConfigurations)
    }

    func testSanitizeClamps() {
        var c = PIPConfiguration(name: "  \u{202E}Evil\u{0007}  ")
        c.opacity = 0
        c.fps = 500
        c.rotation = -90
        c.underscanPercent = 5000
        c.windowFrame = PIPRect(x: -1e9, y: .nan, width: 1, height: 1e9)
        c.crop = PIPRect(x: -1, y: 0.5, width: 5, height: 0.001)
        c.filters = (0..<30).map { _ in FilterInstance(kind: .invert) }
        c.nativeModeWhileStreaming = true
        let s = c.sanitized()
        XCTAssertEqual(s.name, "Evil")
        XCTAssertEqual(s.opacity, 0.1)
        XCTAssertEqual(s.fps, 120)
        XCTAssertEqual(s.rotation, 270)
        XCTAssertEqual(s.underscanPercent, 200)
        XCTAssertNil(s.windowFrame, "a NaN frame is dropped")
        XCTAssertEqual(s.crop, PIPRect(x: 0, y: 0.5, width: 1, height: PIPConfiguration.minCropFraction))
        XCTAssertEqual(s.filters.count, PIPConfiguration.maxFilters)
        XCTAssertFalse(s.nativeModeWhileStreaming, "window PIPs never change modes")
        XCTAssertEqual(s.sanitized(), s)

        c.windowFrame = PIPRect(x: -1e9, y: 0, width: 1, height: 1e9)
        XCTAssertEqual(c.sanitized().windowFrame,
                       PIPRect(x: -PIPConfiguration.maxWindowOrigin, y: 0, width: PIPConfiguration.minWindowSide,
                               height: PIPConfiguration.maxWindowSide))
        c.fps = 0
        XCTAssertEqual(c.sanitized().fps, 0, "0 means the display's rate")
        c.fps = -4
        XCTAssertEqual(c.sanitized().fps, 1)
        c.name = String(repeating: "x", count: 500)
        XCTAssertEqual(c.sanitized().name.unicodeScalars.count, PIPConfiguration.maxNameScalars)
        c.name = "   "
        XCTAssertEqual(c.sanitized().name, PIPConfiguration().name)
        c.crop = PIPRect(x: 0, y: 0, width: 1, height: 1)
        XCTAssertNil(c.sanitized().crop, "a full crop is no crop")
    }

    func testRotationNormalization() {
        let cases: [(Int, Int)] = [(0, 0), (44, 0), (46, 90), (90, 90), (180, 180), (269, 270), (300, 270), (359, 0),
                                   (360, 0), (-90, 270), (-180, 180), (725, 0), (Int.max, 0)]
        for (input, expected) in cases where input != Int.max {
            XCTAssertEqual(PIPConfiguration.normalizedRotation(input), expected, "\(input)")
        }
        XCTAssertTrue([0, 90, 180, 270].contains(PIPConfiguration.normalizedRotation(Int.max)))
        XCTAssertTrue([0, 90, 180, 270].contains(PIPConfiguration.normalizedRotation(Int.min)))
    }

    func testGlobalSanitize() {
        var g = PIPConfig()
        g.protectedBundlePrefixes = ["com.example.app", "com", "", "a..b", "*", "com.example.app", "x.y", "has space.z"]
        let dup = PIPConfiguration(name: "A")
        g.windowConfigurations = [dup, dup] + (0..<20).map { PIPConfiguration(name: "W\($0)") }
        g.luts = [PIPLUTReference(name: "ok", size: 33), PIPLUTReference(name: "bad", size: 1),
                  PIPLUTReference(name: "", size: 129), PIPLUTReference(name: "  ", size: 2)]
        let s = g.sanitized()
        XCTAssertEqual(s.protectedBundlePrefixes, ["com.example.app", "x.y"])
        XCTAssertEqual(s.windowConfigurations.count, PIPConfig.maxWindowConfigurations)
        XCTAssertEqual(Set(s.windowConfigurations.map(\.id)).count, s.windowConfigurations.count)
        XCTAssertEqual(s.luts.map(\.size), [33, 2])
        XCTAssertEqual(s.luts[1].name, "LUT")

        g.protectedBundlePrefixes = (0..<100).map { "com.example.a\($0)" }
        XCTAssertEqual(g.sanitized().protectedBundlePrefixes.count, PIPConfig.maxProtectedPrefixes)

        var per = PerDisplayPIP()
        per.configurations = (0..<12).map { PIPConfiguration(name: "D\($0)") }
        XCTAssertEqual(per.sanitized().configurations.count, PerDisplayPIP.maxConfigurations)
    }

    // MARK: Access helpers

    func testEntriesAddUpdateRemove() throws {
        var config = DisplaysConfig()
        let a = PIPConfiguration(name: "Left")
        let b = PIPConfiguration(name: "Right", kind: .fullScreen)
        let w = PIPConfiguration(name: "Window")
        XCTAssertTrue(PIPConfig.add(b, source: .display(keyB), to: &config))
        XCTAssertTrue(PIPConfig.add(a, source: .display(keyA), to: &config))
        XCTAssertTrue(PIPConfig.add(w, source: .window, to: &config))
        let entries = PIPConfig.entries(in: config)
        XCTAssertEqual(entries.map(\.configuration.name), ["Left", "Right", "Window"])
        XCTAssertEqual(entries.map(\.source), [.display(keyA), .display(keyB), .window])
        XCTAssertEqual(PIPConfig.entry(w.id, in: config)?.source, .window)

        XCTAssertTrue(PIPConfig.update(a.id, in: &config) { $0.opacity = 7; $0.id = StableID() })
        let updated = try XCTUnwrap(PIPConfig.entry(a.id, in: config))
        XCTAssertEqual(updated.configuration.opacity, 1, "updates are sanitized")
        XCTAssertTrue(PIPConfig.update(w.id, in: &config) { $0.name = "Picked" })
        XCTAssertEqual(PIPConfig.entry(w.id, in: config)?.configuration.name, "Picked")
        XCTAssertFalse(PIPConfig.update(StableID(), in: &config) { _ in })

        // Same id in two places: the first entry wins.
        PIPConfig.add(a, source: .display(keyB), to: &config)
        XCTAssertEqual(PIPConfig.entries(in: config).filter { $0.configuration.id == a.id }.count, 1)

        XCTAssertTrue(PIPConfig.remove(a.id, from: &config))
        XCTAssertNil(PIPConfig.entry(a.id, in: config))
        XCTAssertFalse(PIPConfig.remove(a.id, from: &config))
        XCTAssertTrue(PIPConfig.remove(w.id, from: &config))
        XCTAssertEqual(PIPConfig.entries(in: config).map(\.configuration.id), [b.id])
    }

    func testAddRespectsCaps() {
        var config = DisplaysConfig()
        for i in 0..<PerDisplayPIP.maxConfigurations {
            XCTAssertTrue(PIPConfig.add(PIPConfiguration(name: "\(i)"), source: .display(keyA), to: &config))
        }
        XCTAssertFalse(PIPConfig.add(PIPConfiguration(), source: .display(keyA), to: &config))
        for i in 0..<PIPConfig.maxWindowConfigurations {
            XCTAssertTrue(PIPConfig.add(PIPConfiguration(name: "\(i)"), source: .window, to: &config))
        }
        XCTAssertFalse(PIPConfig.add(PIPConfiguration(), source: .window, to: &config))
    }

    func testRemoveLUTClearsReferences() {
        var config = DisplaysConfig()
        let lut = PIPLUTReference(name: "Film", size: 17)
        config.pip.luts = [lut]
        var a = PIPConfiguration(name: "A")
        a.lutID = lut.id
        var w = PIPConfiguration(name: "W")
        w.lutID = lut.id
        PIPConfig.add(a, source: .display(keyA), to: &config)
        PIPConfig.add(w, source: .window, to: &config)
        PIPConfig.removeLUT(lut.id, from: &config)
        XCTAssertTrue(config.pip.luts.isEmpty)
        XCTAssertTrue(PIPConfig.entries(in: config).allSatisfy { $0.configuration.lutID == nil })
    }

    // MARK: Privacy

    func testPrivacyRules() {
        let prefixes = ["com.lastpass", "com.apple.Passwords"]
        XCTAssertTrue(PIPPrivacy.matches("com.lastpass", prefixes: prefixes))
        XCTAssertTrue(PIPPrivacy.matches("com.lastpass.LastPass", prefixes: prefixes))
        XCTAssertFalse(PIPPrivacy.matches("com.lastpassword", prefixes: prefixes))
        XCTAssertFalse(PIPPrivacy.matches(nil, prefixes: prefixes))
        XCTAssertFalse(PIPPrivacy.matches("", prefixes: prefixes))

        let own = "app.snaptic.Snaptic"
        XCTAssertFalse(PIPPrivacy.isCaptureAllowed(bundleID: own, ownBundleID: own, protected: []))
        XCTAssertFalse(PIPPrivacy.isCaptureAllowed(bundleID: "com.apple.notificationcenterui", ownBundleID: own, protected: []))
        XCTAssertFalse(PIPPrivacy.isCaptureAllowed(bundleID: "com.lastpass.LastPass", ownBundleID: own, protected: prefixes))
        XCTAssertTrue(PIPPrivacy.isCaptureAllowed(bundleID: "com.apple.Safari", ownBundleID: own, protected: prefixes))
        XCTAssertTrue(PIPPrivacy.isCaptureAllowed(bundleID: nil, ownBundleID: own, protected: prefixes))
        XCTAssertTrue(PIPPrivacy.isCaptureAllowed(bundleID: own, ownBundleID: nil, protected: []))

        XCTAssertTrue(PIPPrivacy.isPrivateWindow(title: "Mozilla Firefox Private Browsing", bundleID: "org.mozilla.firefox"))
        XCTAssertTrue(PIPPrivacy.isPrivateWindow(title: "Docs (Incognito)", bundleID: "com.example.editor"))
        XCTAssertTrue(PIPPrivacy.isPrivateWindow(title: nil, bundleID: "com.apple.Safari"))
        XCTAssertTrue(PIPPrivacy.isPrivateWindow(title: "", bundleID: "com.google.Chrome"))
        XCTAssertFalse(PIPPrivacy.isPrivateWindow(title: "", bundleID: "com.apple.finder"))
        XCTAssertFalse(PIPPrivacy.isPrivateWindow(title: "News", bundleID: "com.apple.Safari"))
        XCTAssertFalse(PIPPrivacy.isPrivateWindow(title: nil, bundleID: nil))

        for p in PIPPrivacy.defaultProtectedPrefixes { XCTAssertTrue(PIPPrivacy.isValidPrefix(p), p) }
        for p in ["com", "", ".com", "com.", "a..b", "com.*", "com.ex ample", "com.ex/ample"] {
            XCTAssertFalse(PIPPrivacy.isValidPrefix(p), p)
        }
    }

    // MARK: CLI

    func testCommandParsing() {
        XCTAssertEqual(PIPCommand.parse(["list"]), .list)
        XCTAssertEqual(PIPCommand.parse(["LS"]), .list)
        XCTAssertEqual(PIPCommand.parse(["start", "Office", "left"]), .start("Office left"))
        XCTAssertEqual(PIPCommand.parse(["stop", "  x "]), .stop("x"))
        XCTAssertEqual(PIPCommand.parse(["stop-all"]), .stopAll)
        XCTAssertEqual(PIPCommand.parse(["hide-all"]), .hideAll)
        XCTAssertEqual(PIPCommand.parse(["show-all"]), .showAll)
        XCTAssertEqual(PIPCommand.parse(["pause-all"]), .pauseAll)
        XCTAssertEqual(PIPCommand.parse(["resume-all"]), .resumeAll)
        XCTAssertNil(PIPCommand.parse([]))
        XCTAssertNil(PIPCommand.parse(["start"]))
        XCTAssertNil(PIPCommand.parse(["start", "  "]))
        XCTAssertNil(PIPCommand.parse(["list", "extra"]))
        XCTAssertNil(PIPCommand.parse(["stop-all", "now"]))
        XCTAssertNil(PIPCommand.parse(["record"]))
        XCTAssertNil(PIPCommand.parse(["start"] + Array(repeating: "a", count: 40)))
        if case .start(let q)? = PIPCommand.parse(["start", String(repeating: "q", count: 1000)]) {
            XCTAssertEqual(q.unicodeScalars.count, 256)
        } else {
            XCTFail("long names are truncated, not refused")
        }
        XCTAssertFalse(PIPCommand.usage.isEmpty)
    }

    func testDisplaySelectorParsing() {
        XCTAssertEqual(PIPCommand.parse(["start", "--display", "2"]), .startDisplay("2"))
        XCTAssertEqual(PIPCommand.parse(["start", "-d", "main"]), .startDisplay("main"))
        XCTAssertEqual(PIPCommand.parse(["START", "--DISPLAY", "id:5"]), .startDisplay("id:5"))
        XCTAssertEqual(PIPCommand.parse(["stop", "--display=all"]), .stopDisplay("all"))
        XCTAssertEqual(PIPCommand.parse(["stop", "--display", "LG", "UltraFine"]), .stopDisplay("LG UltraFine"))
        XCTAssertEqual(PIPCommand.parse(["stop", "--display=Studio", "Display"]), .stopDisplay("Studio Display"))
        XCTAssertEqual(PIPCommand.parse(["stop", "-d", "", "  mouse "]), .stopDisplay("mouse"))
        // A missing or oversized selector is a usage error, never a name lookup.
        XCTAssertNil(PIPCommand.parse(["start", "--display"]))
        XCTAssertNil(PIPCommand.parse(["stop", "-d", "  "]))
        XCTAssertNil(PIPCommand.parse(["stop", "--display="]))
        XCTAssertNil(PIPCommand.parse(["start", "--display", String(repeating: "x", count: 129)]))
        XCTAssertEqual(PIPCommand.parse(["start", "--display", String(repeating: "x", count: 128)]),
                       .startDisplay(String(repeating: "x", count: 128)))
        // The flag only counts first; elsewhere it is part of a configuration name.
        XCTAssertEqual(PIPCommand.parse(["start", "Office", "--display"]), .start("Office --display"))
        XCTAssertEqual(PIPCommand.parse(["stop", "2"]), .stop("2"))
        XCTAssertNil(PIPCommand.parse(["list", "--display", "2"]))
        XCTAssertNil(PIPCommand.parse(["stop-all", "--display", "2"]))
        XCTAssertTrue(PIPCommand.usage.contains("--display"))
    }

    func testDisplayParsingFuzz() {
        var rng = SeededGenerator(seed: 0x5E1EC7)
        let pieces = ["start", "stop", "--display", "-d", "--display=", "2", "main", "all", "id:", "x", " ", "", "é", "\u{0}", "--"]
        for _ in 0..<2000 {
            let count = Int(rng.next() % 7)
            var args: [String] = []
            for _ in 0..<count { args.append(pieces[Int(rng.next() % UInt64(pieces.count))]) }
            switch PIPCommand.parse(args) {
            case .startDisplay(let sel)?, .stopDisplay(let sel)?:
                XCTAssertFalse(sel.isEmpty)
                XCTAssertLessThanOrEqual(sel.utf8.count, 128)
                XCTAssertEqual(sel, sel.trimmingCharacters(in: .whitespacesAndNewlines))
            case .start(let q)?, .stop(let q)?:
                XCTAssertFalse(q.isEmpty)
            default: break
            }
        }
    }

    func testPreferredForDisplay() {
        let stream = PIPConfiguration(name: "Stream", kind: .fullScreen)
        let pip = PIPConfiguration(name: "PIP", kind: .window)
        let pip2 = PIPConfiguration(name: "PIP 2", kind: .window)
        XCTAssertEqual(PIPLookup.preferredForDisplay([stream, pip, pip2])?.id, pip.id)
        XCTAssertEqual(PIPLookup.preferredForDisplay([stream])?.id, stream.id)
        XCTAssertNil(PIPLookup.preferredForDisplay([]))
    }

    func testLookup() {
        let a = PIPConfiguration(name: "Office Left")
        let b = PIPConfiguration(name: "Office Right")
        let c = PIPConfiguration(name: "TV")
        let d = PIPConfiguration(name: "tv")
        let items = [a, b, c]
        XCTAssertEqual(PIPLookup.find(a.id.rawValue, in: items), .found(a.id))
        XCTAssertEqual(PIPLookup.find(a.id.rawValue.lowercased(), in: items), .found(a.id))
        XCTAssertEqual(PIPLookup.find("office right", in: items), .found(b.id))
        XCTAssertEqual(PIPLookup.find("office l", in: items), .found(a.id))
        XCTAssertEqual(PIPLookup.find("Office", in: items), .ambiguous(2))
        XCTAssertEqual(PIPLookup.find("tv", in: items), .found(c.id))
        XCTAssertEqual(PIPLookup.find("tv", in: items + [d]), .ambiguous(2))
        XCTAssertEqual(PIPLookup.find("Kitchen", in: items), .notFound)
        XCTAssertEqual(PIPLookup.find("", in: items), .notFound)
        XCTAssertEqual(PIPLookup.find(StableID().rawValue, in: items), .notFound)
    }

    // MARK: Geometry

    func testVisibleSize() {
        let s = PIPSize(width: 1920, height: 1080)
        XCTAssertEqual(PIPGeometry.visibleSize(source: s, crop: nil, rotation: 0), s)
        XCTAssertEqual(PIPGeometry.visibleSize(source: s, crop: nil, rotation: 90), PIPSize(width: 1080, height: 1920))
        let crop = PIPRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        XCTAssertEqual(PIPGeometry.visibleSize(source: s, crop: crop, rotation: 270), PIPSize(width: 540, height: 960))
    }

    func testContentRectModes() {
        let content = PIPSize(width: 1920, height: 1080)
        let bounds = PIPSize(width: 1000, height: 1000)
        let fit = PIPGeometry.contentRect(contentPixels: content, in: bounds, scaling: .fit, underscanPercent: 100, backingScale: 2)
        XCTAssertEqual(Double(fit.width), 1000, accuracy: 1e-9)
        XCTAssertEqual(Double(fit.height), 562.5, accuracy: 1e-9)
        XCTAssertEqual(Double(fit.midY), 500, accuracy: 1e-9)
        let fill = PIPGeometry.contentRect(contentPixels: content, in: bounds, scaling: .fill, underscanPercent: 100, backingScale: 2)
        XCTAssertEqual(Double(fill.height), 1000, accuracy: 1e-9)
        XCTAssertEqual(Double(fill.midX), 500, accuracy: 1e-9)
        let one = PIPGeometry.contentRect(contentPixels: content, in: bounds, scaling: .oneToOne, underscanPercent: 100, backingScale: 2)
        XCTAssertEqual(Double(one.width), 960, accuracy: 1e-9)
        let small = PIPSize(width: 400, height: 300)
        let integer = PIPGeometry.contentRect(contentPixels: small, in: bounds, scaling: .integer, underscanPercent: 100, backingScale: 2)
        XCTAssertEqual(Double(integer.width), 1000, accuracy: 1e-9, "5× 400 px = 2000 px = 1000 pt")
        let tooBig = PIPGeometry.contentRect(contentPixels: PIPSize(width: 4000, height: 4000), in: bounds, scaling: .integer,
                                             underscanPercent: 100, backingScale: 1)
        XCTAssertEqual(Double(tooBig.width), 1000, accuracy: 1e-9, "below 1× falls back to fit")
        let under = PIPGeometry.contentRect(contentPixels: content, in: bounds, scaling: .fit, underscanPercent: 50, backingScale: 2)
        XCTAssertEqual(Double(under.width), 500, accuracy: 1e-9)
        XCTAssertEqual(Double(under.midX), 500, accuracy: 1e-9)
        let degenerate = PIPGeometry.contentRect(contentPixels: .zero, in: bounds, scaling: .fit, underscanPercent: 100, backingScale: 2)
        XCTAssertEqual(degenerate.size, bounds)
    }

    func testSnapAndCaptureSize() {
        let visible = PIPSize(width: 1600, height: 900)
        XCTAssertEqual(PIPGeometry.snapped(PIPSize(width: 430, height: 100), visible: visible), PIPSize(width: 400, height: 225))
        XCTAssertEqual(PIPGeometry.snapped(PIPSize(width: 10, height: 10), visible: visible), PIPSize(width: 400, height: 225))

        let c = PIPGeometry.captureSize(sourcePixels: PIPSize(width: 3840, height: 2160), viewPixels: PIPSize(width: 960, height: 540),
                                        fullResolution: false)
        XCTAssertEqual(c, PIPSize(width: 960, height: 540))
        let up = PIPGeometry.captureSize(sourcePixels: PIPSize(width: 800, height: 600), viewPixels: PIPSize(width: 4000, height: 3000),
                                         fullResolution: false)
        XCTAssertEqual(up, PIPSize(width: 800, height: 600), "never upscaled")
        let full = PIPGeometry.captureSize(sourcePixels: PIPSize(width: 3840, height: 2160), viewPixels: PIPSize(width: 100, height: 100),
                                           fullResolution: true)
        XCTAssertEqual(full, PIPSize(width: 3840, height: 2160))
        let huge = PIPGeometry.captureSize(sourcePixels: PIPSize(width: 20000, height: 1000), viewPixels: .zero, fullResolution: true)
        XCTAssertLessThanOrEqual(Double(huge.width), PIPGeometry.maxCaptureSide)
        let odd = PIPGeometry.captureSize(sourcePixels: PIPSize(width: 1001, height: 3), viewPixels: .zero, fullResolution: true)
        XCTAssertEqual(Int(odd.width) % 2, 0)
        XCTAssertGreaterThanOrEqual(Double(odd.height), 16)
    }

    func testSourcePointMapping() {
        func p(_ x: Double, _ y: Double) -> PIPPoint { PIPPoint(x: x, y: y) }
        // Clockwise quarter turn: the source's top-left corner is shown top-right.
        XCTAssertEqual(PIPGeometry.sourcePoint(view: p(1, 0), crop: nil, rotation: 90, flipHorizontal: false, flipVertical: false), p(0, 0))
        XCTAssertEqual(PIPGeometry.sourcePoint(view: p(1, 1), crop: nil, rotation: 90, flipHorizontal: false, flipVertical: false), p(1, 0))
        XCTAssertEqual(PIPGeometry.sourcePoint(view: p(0, 0), crop: nil, rotation: 270, flipHorizontal: false, flipVertical: false), p(1, 0))
        XCTAssertEqual(PIPGeometry.sourcePoint(view: p(0.25, 0), crop: nil, rotation: 0, flipHorizontal: true, flipVertical: false), p(0.75, 0))
        XCTAssertEqual(PIPGeometry.sourcePoint(view: p(0, 0.25), crop: nil, rotation: 180, flipHorizontal: false, flipVertical: true), p(1, 0.25))
        let crop = PIPRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        XCTAssertEqual(PIPGeometry.sourcePoint(view: p(0.5, 0.5), crop: crop, rotation: 0, flipHorizontal: false, flipVertical: false), p(0.75, 0.75))
        XCTAssertEqual(PIPGeometry.sourcePoint(view: p(-4, 9), crop: nil, rotation: 0, flipHorizontal: false, flipVertical: false), p(0, 1))
    }

    func testViewPointInvertsSourcePoint() {
        var rng = SeededGenerator(seed: 0x9E0)
        for _ in 0..<2000 {
            let rotation = [0, 90, 180, 270][Int(rng.next() % 4)]
            let fh = rng.next() % 2 == 0, fv = rng.next() % 2 == 0
            let crop: PIPRect? = rng.next() % 2 == 0 ? nil
                : PIPRect(x: Double(rng.next() % 50) / 100, y: Double(rng.next() % 50) / 100,
                          width: 0.1 + Double(rng.next() % 40) / 100, height: 0.1 + Double(rng.next() % 40) / 100)
            let v = PIPPoint(x: Double(rng.next() % 1000) / 999, y: Double(rng.next() % 1000) / 999)
            let s = PIPGeometry.sourcePoint(view: v, crop: crop, rotation: rotation, flipHorizontal: fh, flipVertical: fv)
            let back = PIPGeometry.viewPoint(source: s, crop: crop, rotation: rotation, flipHorizontal: fh, flipVertical: fv)
            XCTAssertEqual(Double(back.x), Double(v.x), accuracy: 1e-9)
            XCTAssertEqual(Double(back.y), Double(v.y), accuracy: 1e-9)
        }
    }

    func testCropFromDragComposesWithCurrentCrop() throws {
        let first = try XCTUnwrap(PIPGeometry.cropFromDrag(start: PIPPoint(x: 0.5, y: 0.5), end: PIPPoint(x: 1, y: 1), current: nil,
                                                           rotation: 0, flipHorizontal: false, flipVertical: false))
        XCTAssertEqual(first, PIPRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        let second = try XCTUnwrap(PIPGeometry.cropFromDrag(start: PIPPoint(x: 0, y: 0), end: PIPPoint(x: 0.5, y: 0.5), current: first,
                                                            rotation: 0, flipHorizontal: false, flipVertical: false))
        XCTAssertEqual(second, PIPRect(x: 0.5, y: 0.5, width: 0.25, height: 0.25))
        XCTAssertNil(PIPGeometry.cropFromDrag(start: PIPPoint(x: 0.5, y: 0.5), end: PIPPoint(x: 0.505, y: 0.9), current: nil,
                                              rotation: 0, flipHorizontal: false, flipVertical: false))
    }

    func testFrameInterval() {
        XCTAssertEqual(PIPGeometry.frameInterval(fps: 30, displayRefresh: 60), 1.0 / 30, accuracy: 1e-12)
        XCTAssertEqual(PIPGeometry.frameInterval(fps: 0, displayRefresh: 120), 1.0 / 120, accuracy: 1e-12)
        XCTAssertEqual(PIPGeometry.frameInterval(fps: 0, displayRefresh: 0), 1.0 / 60, accuracy: 1e-12)
        XCTAssertEqual(PIPGeometry.frameInterval(fps: 0, displayRefresh: 240), 1.0 / 120, accuracy: 1e-12)
        XCTAssertEqual(PIPGeometry.frameInterval(fps: 0, displayRefresh: .nan), 1.0 / 60, accuracy: 1e-12)
        XCTAssertEqual(PIPGeometry.frameInterval(fps: 999, displayRefresh: 60), 1.0 / 120, accuracy: 1e-12)
    }

    // MARK: Menu plan

    private func entry(_ name: String, _ source: PIPSourceRef, kind: PIPKind = .window, target: DisplayKey? = nil) -> PIPEntry {
        var c = PIPConfiguration(name: name, kind: kind)
        c.target = target
        return PIPEntry(source: source, configuration: c)
    }

    func testMenuPlanIsAbsentWithoutSavedConfigurations() {
        XCTAssertNil(PIPMenuPlan.plan(entries: [], running: [], connected: [keyA]))
    }

    func testMenuPlanMarksRunningAndAvailable() throws {
        let a = entry("A", .display(keyA))
        let offline = entry("Offline", .display(keyB))
        let window = entry("Window", .window)
        let plan = try XCTUnwrap(PIPMenuPlan.plan(entries: [a, offline, window], running: [a.configuration.id],
                                                  connected: [keyA]))
        XCTAssertEqual(plan.rows.map(\.name), ["A", "Offline", "Window"])
        XCTAssertEqual(plan.rows.map(\.running), [true, false, false])
        XCTAssertEqual(plan.rows.map(\.available), [true, false, true])
        XCTAssertFalse(plan.truncated)
        XCTAssertTrue(plan.anyRunning)
        let idle = try XCTUnwrap(PIPMenuPlan.plan(entries: [a], running: [], connected: [keyA]))
        XCTAssertFalse(idle.anyRunning)
    }

    func testMenuPlanStreamAvailability() {
        // A stream needs its source and a different, connected target.
        XCTAssertTrue(PIPMenuPlan.isAvailable(entry("S", .display(keyA), kind: .fullScreen, target: keyB), connected: [keyA, keyB]))
        XCTAssertFalse(PIPMenuPlan.isAvailable(entry("S", .display(keyA), kind: .fullScreen, target: keyB), connected: [keyA]))
        XCTAssertFalse(PIPMenuPlan.isAvailable(entry("S", .display(keyA), kind: .fullScreen, target: keyA), connected: [keyA, keyB]))
        XCTAssertFalse(PIPMenuPlan.isAvailable(entry("S", .display(keyA), kind: .fullScreen, target: nil), connected: [keyA, keyB]))
        XCTAssertTrue(PIPMenuPlan.isAvailable(entry("W", .window), connected: []))
        XCTAssertFalse(PIPMenuPlan.isAvailable(entry("W", .window, kind: .fullScreen, target: keyB), connected: []))
        XCTAssertTrue(PIPMenuPlan.isAvailable(entry("W", .window, kind: .fullScreen, target: keyB), connected: [keyB]))
        // A running configuration is always clickable (to stop it).
        let s = entry("S", .display(keyA), kind: .fullScreen, target: keyB)
        XCTAssertEqual(PIPMenuPlan.plan(entries: [s], running: [s.configuration.id], connected: [])?.rows.first?.available, true)
    }

    func testMenuPlanKeepsRunningRowsWhenTruncating() throws {
        let entries = (0..<14).map { entry("P\($0)", .window) }
        let running: Set<StableID> = [entries[12].configuration.id, entries[13].configuration.id]
        let plan = try XCTUnwrap(PIPMenuPlan.plan(entries: entries, running: running, connected: []))
        XCTAssertEqual(plan.rows.count, PIPMenuPlan.maxRows)
        XCTAssertTrue(plan.truncated)
        XCTAssertEqual(plan.rows.map(\.name), ["P0", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "P12", "P13"])
        let exact = try XCTUnwrap(PIPMenuPlan.plan(entries: Array(entries.prefix(10)), running: [], connected: []))
        XCTAssertFalse(exact.truncated)
        XCTAssertEqual(PIPMenuPlan.plan(entries: entries, running: [], connected: [], limit: 0)?.rows.count, 1)
    }

    func testFuzzedMenuPlanInvariants() throws {
        var rng = SeededGenerator(seed: 0x919E)
        let keys = [keyA, keyB]
        for _ in 0..<500 {
            let count = Int(rng.next() % 20)
            let entries: [PIPEntry] = (0..<count).map { i in
                let source: PIPSourceRef = rng.next() % 3 == 0 ? .window : .display(keys[Int(rng.next() % 2)])
                let kind: PIPKind = rng.next() % 2 == 0 ? .window : .fullScreen
                return entry("E\(i)", source, kind: kind, target: rng.next() % 4 == 0 ? nil : keys[Int(rng.next() % 2)])
            }
            let running = Set(entries.filter { _ in rng.next() % 4 == 0 }.map(\.configuration.id))
            let connected = Set(keys.filter { _ in rng.next() % 2 == 0 })
            let limit = 1 + Int(rng.next() % 12)
            guard let plan = PIPMenuPlan.plan(entries: entries, running: running, connected: connected, limit: limit) else {
                XCTAssertTrue(entries.isEmpty)
                continue
            }
            XCTAssertEqual(plan.rows.count, min(limit, entries.count))
            XCTAssertEqual(plan.truncated, entries.count > limit)
            XCTAssertEqual(plan.anyRunning, !running.isEmpty)
            // Rows keep saved order and are a subset.
            let order = entries.map(\.configuration.id)
            let indices = plan.rows.compactMap { row in order.firstIndex(of: row.id) }
            XCTAssertEqual(indices.count, plan.rows.count)
            XCTAssertEqual(indices, indices.sorted())
            XCTAssertEqual(Set(indices).count, indices.count)
            // Running rows survive truncation whenever they fit.
            let shownRunning = plan.rows.filter(\.running).count
            XCTAssertEqual(shownRunning, min(running.count, limit))
            for row in plan.rows {
                XCTAssertEqual(row.running, running.contains(row.id))
                if row.running { XCTAssertTrue(row.available) }
            }
        }
    }

    // MARK: Fuzzing

    func testFuzzedJSONNeverTrapsAndSanitizeIsIdempotent() throws {
        var rng = SeededGenerator(seed: 0x5A11)
        var base = PIPConfiguration(name: "Base", kind: .fullScreen)
        base.target = keyA
        base.crop = PIPRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        base.filters = [FilterInstance(kind: .vignette)]
        var per = PerDisplayPIP()
        per.configurations = [base]
        let original = Array(try JSONEncoder().encode(per))
        let alphabet = Array("{}[]\":,0123456789.-etruefalsnul ".utf8)
        for _ in 0..<2000 {
            var bytes = original
            for _ in 0..<(1 + Int(rng.next() % 3)) {
                let i = Int(rng.next() % UInt64(bytes.count))
                bytes[i] = alphabet[Int(rng.next() % UInt64(alphabet.count))]
            }
            guard let decoded = try? JSONDecoder().decode(PerDisplayPIP.self, from: Data(bytes)) else { continue }
            let s = decoded.sanitized()
            XCTAssertEqual(s.sanitized(), s)
            for c in s.configurations {
                XCTAssertTrue(PIPConfiguration.opacityRange.contains(c.opacity))
                XCTAssertTrue(c.fps == 0 || PIPConfiguration.fpsRange.contains(c.fps))
                XCTAssertTrue([0, 90, 180, 270].contains(c.rotation))
                if let crop = c.crop {
                    XCTAssertTrue(crop.x >= 0 && crop.y >= 0 && crop.x + crop.width <= 1 + 1e-12 && crop.y + crop.height <= 1 + 1e-12)
                }
            }
        }
    }

    // MARK: Settings text and limits (0.3 §4.3)

    func testDefaultNames() {
        XCTAssertEqual(PIPSettingsText.defaultName(sourceName: nil, kind: .window, targetName: nil), "Window PIP")
        XCTAssertEqual(PIPSettingsText.defaultName(sourceName: "Built-in Display", kind: .window, targetName: "DELL"),
                       "Built-in Display PIP")
        XCTAssertEqual(PIPSettingsText.defaultName(sourceName: "Built-in Display", kind: .fullScreen, targetName: "DELL"),
                       "Built-in Display → DELL")
        // A stream without a target yet is named like a window.
        XCTAssertEqual(PIPSettingsText.defaultName(sourceName: "A", kind: .fullScreen, targetName: nil), "A PIP")
        // Names stay within the configuration's limit.
        let long = String(repeating: "x", count: 200)
        let name = PIPSettingsText.defaultName(sourceName: long, kind: .fullScreen, targetName: long)
        XCTAssertLessThanOrEqual(name.unicodeScalars.count, PIPConfiguration.maxNameScalars)
        XCTAssertEqual(PIPConfiguration.cleanName(name), name)
    }

    func testSubtitleOrderAndParts() {
        var c = PIPConfiguration(kind: .window)
        XCTAssertEqual(PIPSettingsText.subtitle(c, sourceName: "Built-in Display", targetName: nil),
                       "Built-in Display · 30 fps")
        c.fps = 0
        XCTAssertEqual(PIPSettingsText.subtitle(c, sourceName: nil, targetName: nil), "A window you choose")
        c.kind = .fullScreen
        c.crop = PIPRect(x: 0, y: 0, width: 0.5, height: 0.5)
        c.rotation = 90
        c.flipVertical = true
        c.filters = [FilterInstance(kind: .sepia)]
        c.autoStart = true
        XCTAssertEqual(PIPSettingsText.subtitle(c, sourceName: "A", targetName: "B"),
                       "A · Full screen on B · Cropped · Rotated 90° · Flipped · Filters · Offers to start")
        XCTAssertEqual(PIPSettingsText.subtitle(c, sourceName: "A", targetName: nil),
                       "A · Choose a display to stream onto · Cropped · Rotated 90° · Flipped · Filters · Offers to start")
        // Only enabled filters count; a lookup table does.
        c.filters = [FilterInstance(kind: .sepia, enabled: false)]
        XCTAssertFalse(PIPSettingsText.subtitle(c, sourceName: "A", targetName: "B").contains("Filters"))
        c.lutID = StableID()
        XCTAssertTrue(PIPSettingsText.subtitle(c, sourceName: "A", targetName: "B").contains("Filters"))
    }

    func testCropText() {
        XCTAssertEqual(PIPSettingsText.crop(nil), "None")
        XCTAssertEqual(PIPSettingsText.crop(PIPRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4)), "50% × 40% at 10%, 20%")
        // Out-of-range crops are shown as they would apply (normalized), never as raw numbers.
        let odd = PIPSettingsText.crop(PIPRect(x: -1, y: 0, width: 5, height: 0.5))
        XCTAssertFalse(odd.contains("-"))
        XCTAssertEqual(PIPSettingsText.crop(PIPRect(x: .nan, y: 0, width: 1, height: 1)),
                       PIPSettingsText.crop(PIPRect(x: .nan, y: 0, width: 1, height: 1).normalizedCrop()))
    }

    func testCanAddAndRefusals() {
        var config = DisplaysConfig()
        XCTAssertTrue(PIPSettingsText.canAdd(source: .window, in: config))
        XCTAssertTrue(PIPSettingsText.canAdd(source: .display(keyA), in: config))
        for _ in 0..<PerDisplayPIP.maxConfigurations {
            XCTAssertTrue(PIPConfig.add(PIPConfiguration(), source: .display(keyA), to: &config))
        }
        XCTAssertFalse(PIPSettingsText.canAdd(source: .display(keyA), in: config))
        XCTAssertTrue(PIPSettingsText.canAdd(source: .display(keyB), in: config))
        XCTAssertNotNil(PIPSettingsText.addRefusal(PIPConfiguration(), source: .display(keyA), in: config))
        XCTAssertNil(PIPSettingsText.addRefusal(PIPConfiguration(), source: .display(keyB), in: config))
        for _ in 0..<PIPConfig.maxWindowConfigurations {
            XCTAssertTrue(PIPConfig.add(PIPConfiguration(), source: .window, to: &config))
        }
        XCTAssertFalse(PIPSettingsText.canAdd(source: .window, in: config))

        var stream = PIPConfiguration(kind: .fullScreen)
        XCTAssertEqual(PIPSettingsText.addRefusal(stream, source: .display(keyB), in: config),
                       "Choose a display to stream onto.")
        stream.target = keyB
        XCTAssertNotNil(PIPSettingsText.addRefusal(stream, source: .display(keyB), in: config))
        stream.target = keyA
        XCTAssertNil(PIPSettingsText.addRefusal(stream, source: .display(keyB), in: config))
    }

    func testPrivacyListHelpers() {
        XCTAssertTrue(PIPPrivacy.isDefaultList(PIPPrivacy.defaultProtectedPrefixes))
        XCTAssertTrue(PIPPrivacy.isDefaultList(PIPPrivacy.defaultProtectedPrefixes.reversed()))
        XCTAssertFalse(PIPPrivacy.isDefaultList(Array(PIPPrivacy.defaultProtectedPrefixes.dropLast())))
        XCTAssertFalse(PIPPrivacy.isDefaultList(PIPPrivacy.defaultProtectedPrefixes + ["com.example.app"]))
        XCTAssertFalse(PIPPrivacy.isDefaultList(PIPPrivacy.defaultProtectedPrefixes + [PIPPrivacy.defaultProtectedPrefixes[0]]))

        XCTAssertEqual(PIPPrivacy.sanitizedPrefixes(["com.a.b", "bad", "com.a.b", "", "org.x", "a..b", "com.é.x"]),
                       ["com.a.b", "org.x"])
        let many = (0..<200).map { "com.example.app\($0)" }
        let clean = PIPPrivacy.sanitizedPrefixes(many)
        XCTAssertEqual(clean.count, PIPConfig.maxProtectedPrefixes)
        XCTAssertEqual(clean, Array(many.prefix(PIPConfig.maxProtectedPrefixes)))
        // The config's sanitizer uses the same rule.
        var pip = PIPConfig()
        pip.protectedBundlePrefixes = many + ["bad"]
        XCTAssertEqual(pip.sanitized().protectedBundlePrefixes, clean)
    }

    func testFuzzedPrefixListsSanitizeIdempotently() {
        var rng = SeededGenerator(seed: 0x9C1D)
        let alphabet = Array("abcXYZ09.-_ é/".unicodeScalars)
        for _ in 0..<500 {
            let list = (0..<Int(rng.next() % 80)).map { _ -> String in
                var s = String.UnicodeScalarView()
                for _ in 0..<Int(rng.next() % 12) { s.append(alphabet[Int(rng.next() % UInt64(alphabet.count))]) }
                return String(s)
            }
            let clean = PIPPrivacy.sanitizedPrefixes(list)
            XCTAssertEqual(PIPPrivacy.sanitizedPrefixes(clean), clean)
            XCTAssertLessThanOrEqual(clean.count, PIPConfig.maxProtectedPrefixes)
            XCTAssertEqual(Set(clean).count, clean.count)
            XCTAssertTrue(clean.allSatisfy(PIPPrivacy.isValidPrefix))
        }
    }
}
