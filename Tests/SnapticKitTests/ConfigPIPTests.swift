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
}
