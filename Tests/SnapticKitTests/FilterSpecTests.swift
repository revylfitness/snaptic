import XCTest
@testable import SnapticKit

final class FilterSpecTests: XCTestCase {
    func testEveryKindHasExactlyOneDescriptor() {
        let kinds = FilterSpec.all.map(\.kind)
        XCTAssertEqual(Set(kinds).count, kinds.count, "duplicate descriptors")
        XCTAssertEqual(Set(kinds), Set(FilterKind.allCases))
        for kind in FilterKind.allCases {
            XCTAssertEqual(FilterSpec.descriptor(kind).kind, kind)
        }
    }

    func testEveryCategoryIsPopulated() {
        for category in FilterCategory.allCases {
            XCTAssertFalse(FilterSpec.kinds(in: category).isEmpty, category.rawValue)
            XCTAssertFalse(category.title.isEmpty)
        }
    }

    func testAllowlistCoversExactlyTheDescriptorsAndPipelineFilters() {
        for d in FilterSpec.all {
            XCTAssertTrue(FilterSpec.isAllowed(ciName: d.ciName), d.ciName)
            XCTAssertTrue(d.ciName.hasPrefix("CI"), d.ciName)
        }
        XCTAssertTrue(FilterSpec.isAllowed(ciName: "CIColorCubeWithColorSpace"))
        XCTAssertTrue(FilterSpec.isAllowed(ciName: "CIColorMatrix"))
        for name in ["CIBarsSwipeTransition", "CIQRCodeGenerator", "MyPlugInFilter", "", "cigaussianblur"] {
            XCTAssertFalse(FilterSpec.isAllowed(ciName: name), name)
        }
        XCTAssertEqual(FilterSpec.allowedCINames, Set(FilterSpec.all.map(\.ciName)).union(FilterSpec.internalCINames))
    }

    func testParametersAreWellFormed() {
        for d in FilterSpec.all {
            let keys = d.parameters.map(\.key)
            XCTAssertEqual(Set(keys).count, keys.count, "\(d.kind) has duplicate keys")
            XCTAssertFalse(d.title.isEmpty)
            for p in d.parameters {
                XCTAssertLessThan(p.min, p.max, "\(d.kind).\(p.key)")
                XCTAssertTrue((p.min...p.max).contains(p.defaultValue), "\(d.kind).\(p.key)")
                XCTAssertFalse(p.title.isEmpty)
            }
        }
    }

    func testPlanFilterListIsCovered() {
        // PLAN §10 names these explicitly.
        let required: [FilterKind] = [.exposure, .brightness, .contrast, .saturation, .vibrance, .gamma, .hue, .temperature,
                                      .highlightShadow, .sepia, .posterize, .invert, .monochrome, .photoNoir, .thermal,
                                      .xray, .comic, .sharpen, .unsharpMask, .gaussianBlur, .motionBlur, .noiseReduction,
                                      .median, .pixellate, .hexPixellate, .crystallize, .pointillize, .edges, .edgeWork,
                                      .vignette, .bloom, .gloom, .dotScreen, .lineScreen, .hatchedScreen, .cmykHalftone]
        for kind in required { XCTAssertNotNil(FilterSpec.all.first { $0.kind == kind }, kind.rawValue) }
    }

    func testInstanceDefaultsAndClamping() {
        var f = FilterInstance(kind: .gaussianBlur)
        XCTAssertTrue(f.enabled)
        XCTAssertEqual(f.value("radius"), 5)
        XCTAssertTrue(f.isDefault)
        f.values["radius"] = 1e9
        f.values["bogus"] = 3
        XCTAssertEqual(f.value("radius"), 50)
        XCTAssertEqual(f.value("bogus"), 0)
        let s = f.sanitized()
        XCTAssertEqual(s.values, ["radius": 50])
        f.values["radius"] = .nan
        XCTAssertEqual(f.sanitized().values["radius"], 5)
        f.values["radius"] = -.infinity
        XCTAssertEqual(f.sanitized().values["radius"], 5)
        f.values = [:]
        XCTAssertEqual(f.sanitized().values["radius"], 5)
    }

    func testResolveBindings() throws {
        var hue = FilterInstance(kind: .hue)
        hue.values["angle"] = 90
        let r = try XCTUnwrap(FilterSpec.resolve(hue))
        XCTAssertEqual(r.ciName, "CIHueAdjust")
        XCTAssertEqual(r.scalars["inputAngle"] ?? 0, Double.pi / 2, accuracy: 1e-12)

        var temp = FilterInstance(kind: .temperature)
        temp.values["temperature"] = 4000
        temp.values["tint"] = 20
        let t = try XCTUnwrap(FilterSpec.resolve(temp))
        XCTAssertEqual(t.vectors["inputTargetNeutral"], [4000, 20])
        XCTAssertEqual(t.vectors["inputNeutral"], [6500, 0])

        let mono = try XCTUnwrap(FilterSpec.resolve(FilterInstance(kind: .monochrome)))
        XCTAssertEqual(mono.colors["inputColor"], [0.6, 0.6, 0.6, 1])
        XCTAssertEqual(mono.scalars["inputIntensity"], 1)

        let pix = try XCTUnwrap(FilterSpec.resolve(FilterInstance(kind: .pixellate)))
        XCTAssertEqual(pix.centerKeys, ["inputCenter"])
        XCTAssertFalse(pix.expandsExtent)
        XCTAssertTrue(try XCTUnwrap(FilterSpec.resolve(FilterInstance(kind: .bloom))).expandsExtent)

        XCTAssertNil(FilterSpec.resolve(FilterInstance(kind: .invert, enabled: false)))
        let invert = try XCTUnwrap(FilterSpec.resolve(FilterInstance(kind: .invert)))
        XCTAssertTrue(invert.scalars.isEmpty)
    }

    func testResolveChainSkipsDisabledAndCaps() {
        var chain = (0..<40).map { FilterInstance(kind: FilterKind.allCases[$0 % FilterKind.allCases.count]) }
        chain[0].enabled = false
        let resolved = FilterSpec.resolveChain(chain)
        XCTAssertEqual(resolved.count, FilterSpec.maxFiltersPerChain - 1)
        XCTAssertEqual(resolved.first?.ciName, FilterSpec.descriptor(chain[1].kind).ciName)
    }

    func testDecodingDropsUnknownKindsAndKeepsTheRest() throws {
        let json = """
        [{"kind":"sepia","enabled":false,"values":{"intensity":0.3}},
         {"kind":"futureFilter","values":{}},
         {"kind":"edges","enabled":"yes","values":"bad"},
         7]
        """
        let list = try JSONDecoder().decode(PIPLossyList<FilterInstance>.self, from: Data(json.utf8))
        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.items[0].kind, .sepia)
        XCTAssertFalse(list.items[0].enabled)
        XCTAssertEqual(list.items[0].value("intensity"), 0.3, accuracy: 1e-12)
        XCTAssertEqual(list.items[1].kind, .edges)
        XCTAssertTrue(list.items[1].enabled)
        XCTAssertEqual(list.items[1].value("intensity"), 1)

        let round = try JSONDecoder().decode(FilterInstance.self, from: JSONEncoder().encode(list.items[0]))
        XCTAssertEqual(round, list.items[0])
    }

    func testFuzzedValuesAlwaysResolveInsideRanges() {
        var rng = SeededGenerator(seed: 0xF1173)
        let specials: [Double] = [.nan, .infinity, -.infinity, 1e300, -1e300, 0, -0.0]
        for _ in 0..<5000 {
            let kind = FilterKind.allCases[Int(rng.next() % UInt64(FilterKind.allCases.count))]
            var f = FilterInstance(kind: kind, enabled: rng.next() % 5 != 0)
            for p in FilterSpec.descriptor(kind).parameters {
                switch rng.next() % 3 {
                case 0: f.values[p.key] = specials[Int(rng.next() % UInt64(specials.count))]
                case 1: f.values[p.key] = Double(Int64(bitPattern: rng.next()) % 100_000) / 7
                default: f.values[p.key] = nil
                }
            }
            let s = f.sanitized()
            for p in FilterSpec.descriptor(kind).parameters {
                let v = s.values[p.key] ?? .nan
                XCTAssertTrue(v >= p.min && v <= p.max, "\(kind).\(p.key) = \(v)")
            }
            if let r = FilterSpec.resolve(f) {
                XCTAssertTrue(f.enabled)
                for v in r.scalars.values { XCTAssertTrue(v.isFinite) }
                for v in r.vectors.values.joined() { XCTAssertTrue(v.isFinite) }
            } else {
                XCTAssertFalse(f.enabled)
            }
        }
    }

    // MARK: Settings sliders (0.3 §4.1)

    func testSliderStylesReachTheDefaultAndFitTheRange() {
        for descriptor in FilterSpec.all {
            for p in descriptor.parameters {
                let style = p.sliderStyle
                XCTAssertFalse(style.title.isEmpty, "\(descriptor.kind) \(p.key)")
                if let step = style.step {
                    XCTAssertGreaterThan(step, 0)
                    XCTAssertLessThan(step, p.max - p.min)
                    let snapped = SliderMath.clampSnap(p.defaultValue, range: p.min...p.max, step: step)
                    XCTAssertEqual(snapped, p.defaultValue, accuracy: 1e-9, "\(descriptor.kind) \(p.key)")
                }
                XCTAssertTrue(SliderMath.isDefault(value: p.defaultValue, default: p.defaultValue, step: style.step))
                let shown = SliderMath.format(p.defaultValue, style.format, decimalSeparator: ".")
                XCTAssertEqual(SliderMath.parse(shown, style.format, decimalSeparator: ".") ?? .nan, p.defaultValue,
                               accuracy: 0.051, "\(descriptor.kind) \(p.key): \(shown)")
            }
        }
    }

    func testSliderStylesByUnit() {
        func param(_ unit: FilterUnit, _ min: Double, _ max: Double, _ value: Double) -> FilterParameter {
            FilterParameter("k", "Amount", min, max, value, unit: unit, binding: .scalar("inputK"))
        }
        XCTAssertEqual(param(.degrees, -180, 180, 0).sliderStyle,
                       FilterSliderStyle(title: "Amount (°)", format: .plain(digits: 0), step: 1))
        XCTAssertEqual(param(.kelvin, 2000, 20000, 6500).sliderStyle,
                       FilterSliderStyle(title: "Amount", format: .kelvin, step: 50))
        XCTAssertEqual(param(.pixels, 0, 25, 2.5).sliderStyle,
                       FilterSliderStyle(title: "Amount (px)", format: .plain(digits: 1), step: 0.5))
        XCTAssertEqual(param(.ev, -3, 3, 0).sliderStyle,
                       FilterSliderStyle(title: "Amount (EV)", format: .plain(digits: 2), step: 0.05))
        XCTAssertEqual(param(.none, 2, 30, 6).sliderStyle,
                       FilterSliderStyle(title: "Amount", format: .plain(digits: 0), step: 1))
        XCTAssertEqual(param(.none, 0, 1, 0.7).sliderStyle,
                       FilterSliderStyle(title: "Amount", format: .plain(digits: 2), step: 0.01))
        // A default off the grid drops the step (and whole-number display) so the default stays reachable.
        XCTAssertEqual(param(.degrees, -180, 180, 0.5).sliderStyle,
                       FilterSliderStyle(title: "Amount (°)", format: .plain(digits: 1), step: nil))
        XCTAssertNil(param(.pixels, 0, 0.3, 0.1).sliderStyle.step)
    }
}
