import Foundation

// The allowlist of CoreImage built-in filters PIP and streams may use (PLAN §10,
// §4.10(5)). Only names listed here are ever passed to CoreImage; plugins are never
// loaded. Every parameter has a range, and stored values are clamped to it.

package enum FilterCategory: String, Codable, CaseIterable, Sendable {
    case color, looks, detail, stylize

    package var title: String {
        switch self {
        case .color: return L("Color")
        case .looks: return L("Looks")
        case .detail: return L("Detail")
        case .stylize: return L("Stylize")
        }
    }
}

/// Snaptic's filter ids (persisted).
package enum FilterKind: String, Codable, CaseIterable, Sendable {
    // Color
    case exposure, brightness, contrast, saturation, vibrance, gamma, hue, temperature, highlightShadow
    // Looks
    case sepia, posterize, invert, monochrome
    case photoNoir, photoChrome, photoInstant, photoFade, photoTransfer, photoProcess, photoMono, photoTonal
    case thermal, xray, comic
    // Detail
    case sharpen, unsharpMask, gaussianBlur, motionBlur, noiseReduction, median
    // Stylize
    case pixellate, hexPixellate, crystallize, pointillize, edges, edgeWork, vignette, bloom, gloom
    case dotScreen, lineScreen, hatchedScreen, cmykHalftone
}

package enum FilterUnit: String, Sendable {
    case none, degrees, kelvin, pixels, ev
}

/// One adjustable value of a filter.
package struct FilterParameter: Equatable, Sendable {
    /// How the stored value reaches CoreImage.
    package enum Binding: Equatable, Sendable {
        case scalar(String)
        /// Stored in degrees, passed in radians.
        case angle(String)
        /// The x or y component of a 2-vector input.
        case vectorX(String)
        case vectorY(String)
    }

    /// Persisted key (stable, independent of CoreImage's names).
    package let key: String
    package let title: String
    package let min: Double
    package let max: Double
    package let defaultValue: Double
    package let unit: FilterUnit
    package let binding: Binding

    package init(_ key: String, _ title: String, _ min: Double, _ max: Double, _ defaultValue: Double,
                 unit: FilterUnit = .none, binding: Binding) {
        self.key = key
        self.title = title
        self.min = min
        self.max = max
        self.defaultValue = defaultValue
        self.unit = unit
        self.binding = binding
    }

    package func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return Swift.min(max, Swift.max(min, value))
    }

    /// How Settings shows this value as a `SliderSetting` (0.3 §4.1): the title with its unit where `ValueFormat` has
    /// none ("Angle (°)", "Radius (px)"), the format of the typed field, and the step. The step is dropped when the
    /// default wouldn't sit on its grid, so the default is always reachable.
    package var sliderStyle: FilterSliderStyle {
        let span = max - min
        var format: ValueFormat
        var step: Double?
        var title = self.title
        switch unit {
        case .degrees:
            format = .plain(digits: 0)
            step = 1
            title = L("\(self.title) (°)")
        case .kelvin:
            format = .kelvin
            step = 50
        case .pixels:
            format = .plain(digits: 1)
            step = 0.5
            title = L("\(self.title) (px)")
        case .ev:
            format = .plain(digits: 2)
            step = 0.05
            title = L("\(self.title) (EV)")
        case .none:
            let integral = [min, max, defaultValue].allSatisfy { $0.rounded() == $0 }
            if integral && span >= 10 {
                format = .plain(digits: 0)
                step = 1
            } else {
                format = .plain(digits: 2)
                step = 0.01
            }
        }
        if let s = step, !(s > 0 && s < span && FilterParameter.onGrid(defaultValue, from: min, step: s)) {
            step = nil
            if case .plain(let digits) = format, digits == 0 { format = .plain(digits: 1) }
        }
        return FilterSliderStyle(title: title, format: format, step: step)
    }

    private static func onGrid(_ value: Double, from origin: Double, step: Double) -> Bool {
        let n = (value - origin) / step
        return abs(n - n.rounded()) < 1e-6
    }
}

/// A filter parameter's slider in Settings (`FilterParameter.sliderStyle`).
package struct FilterSliderStyle: Equatable, Sendable {
    package let title: String
    package let format: ValueFormat
    package let step: Double?

    package init(title: String, format: ValueFormat, step: Double?) {
        self.title = title
        self.format = format
        self.step = step
    }
}

/// A fixed (non-user) vector or color input.
package struct FilterFixedInput: Equatable, Sendable {
    package let key: String
    package let values: [Double]
    package let isColor: Bool

    package init(_ key: String, _ values: [Double], isColor: Bool = false) {
        self.key = key
        self.values = values
        self.isColor = isColor
    }
}

package struct FilterDescriptor: Equatable, Sendable {
    package let kind: FilterKind
    package let ciName: String
    package let category: FilterCategory
    package let title: String
    package let parameters: [FilterParameter]
    package let fixed: [FilterFixedInput]
    /// Inputs set to the image center (`inputCenter`).
    package let centerKeys: [String]
    /// The output extends beyond the input (blurs, bloom): clamp first, crop after.
    package let expandsExtent: Bool

    package init(_ kind: FilterKind, _ ciName: String, _ category: FilterCategory, _ title: String,
                 _ parameters: [FilterParameter] = [], fixed: [FilterFixedInput] = [], centerKeys: [String] = [],
                 expandsExtent: Bool = false) {
        self.kind = kind
        self.ciName = ciName
        self.category = category
        self.title = title
        self.parameters = parameters
        self.fixed = fixed
        self.centerKeys = centerKeys
        self.expandsExtent = expandsExtent
    }

    package func parameter(_ key: String) -> FilterParameter? { parameters.first { $0.key == key } }
}

/// A filter as the user configured it (persisted in a PIP configuration).
package struct FilterInstance: Codable, Equatable, Sendable {
    package var kind: FilterKind
    package var enabled: Bool
    package var values: [String: Double]

    package init(kind: FilterKind, enabled: Bool = true) {
        self.kind = kind
        self.enabled = enabled
        values = Dictionary(FilterSpec.descriptor(kind).parameters.map { ($0.key, $0.defaultValue) },
                            uniquingKeysWith: { first, _ in first })
    }

    private enum CodingKeys: String, CodingKey { case kind, enabled, values }

    /// An unknown kind fails (the list decoder drops the entry); everything else is lossy.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(FilterKind.self, forKey: .kind)
        enabled = c.lossy(.enabled, true)
        values = c.lossy(.values, [:])
    }

    package func value(_ key: String) -> Double {
        guard let p = FilterSpec.descriptor(kind).parameter(key) else { return 0 }
        return p.clamp(values[key] ?? p.defaultValue)
    }

    /// Known keys only, every value present and inside its range.
    package func sanitized() -> FilterInstance {
        var copy = self
        copy.values = Dictionary(FilterSpec.descriptor(kind).parameters.map {
            ($0.key, $0.clamp(values[$0.key] ?? $0.defaultValue))
        }, uniquingKeysWith: { first, _ in first })
        return copy
    }

    package var isDefault: Bool {
        FilterSpec.descriptor(kind).parameters.allSatisfy { value($0.key) == $0.defaultValue }
    }
}

/// A filter resolved to CoreImage inputs, ready for the pipeline.
package struct ResolvedFilter: Equatable, Sendable {
    package let ciName: String
    package let scalars: [String: Double]
    package let vectors: [String: [Double]]
    package let colors: [String: [Double]]
    package let centerKeys: [String]
    package let expandsExtent: Bool
}

package enum FilterSpec {
    package static let maxFiltersPerChain = 16

    /// CoreImage filters the pipeline itself uses (LUT and its domain mapping).
    package static let internalCINames: Set<String> = ["CIColorCubeWithColorSpace", "CIColorMatrix"]

    package static let all: [FilterDescriptor] = {
        typealias P = FilterParameter
        let center = ["inputCenter"]
        func screen(_ kind: FilterKind, _ ci: String, _ title: String, minWidth: Double, extra: [P] = []) -> FilterDescriptor {
            FilterDescriptor(kind, ci, .stylize, title, [
                P("width", L("Width"), minWidth, 50, 6, unit: .pixels, binding: .scalar("inputWidth")),
                P("angle", L("Angle"), -180, 180, 0, unit: .degrees, binding: .angle("inputAngle")),
                P("sharpness", L("Sharpness"), 0, 1, 0.7, binding: .scalar("inputSharpness")),
            ] + extra, centerKeys: center)
        }
        return [
            // Color
            FilterDescriptor(.exposure, "CIExposureAdjust", .color, L("Exposure"), [
                P("ev", L("Exposure"), -3, 3, 0, unit: .ev, binding: .scalar("inputEV")),
            ]),
            FilterDescriptor(.brightness, "CIColorControls", .color, L("Brightness"), [
                P("brightness", L("Brightness"), -0.5, 0.5, 0, binding: .scalar("inputBrightness")),
            ]),
            FilterDescriptor(.contrast, "CIColorControls", .color, L("Contrast"), [
                P("contrast", L("Contrast"), 0.25, 2, 1, binding: .scalar("inputContrast")),
            ]),
            FilterDescriptor(.saturation, "CIColorControls", .color, L("Saturation"), [
                P("saturation", L("Saturation"), 0, 2, 1, binding: .scalar("inputSaturation")),
            ]),
            FilterDescriptor(.vibrance, "CIVibrance", .color, L("Vibrance"), [
                P("amount", L("Amount"), -1, 1, 0, binding: .scalar("inputAmount")),
            ]),
            FilterDescriptor(.gamma, "CIGammaAdjust", .color, L("Gamma"), [
                P("power", L("Power"), 0.25, 4, 1, binding: .scalar("inputPower")),
            ]),
            FilterDescriptor(.hue, "CIHueAdjust", .color, L("Hue"), [
                P("angle", L("Angle"), -180, 180, 0, unit: .degrees, binding: .angle("inputAngle")),
            ]),
            FilterDescriptor(.temperature, "CITemperatureAndTint", .color, L("Temperature"), [
                P("temperature", L("Temperature"), 2000, 20000, 6500, unit: .kelvin, binding: .vectorX("inputTargetNeutral")),
                P("tint", L("Tint"), -150, 150, 0, binding: .vectorY("inputTargetNeutral")),
            ], fixed: [FilterFixedInput("inputNeutral", [6500, 0])]),
            FilterDescriptor(.highlightShadow, "CIHighlightShadowAdjust", .color, L("Highlights & Shadows"), [
                P("highlights", L("Highlights"), 0, 1, 1, binding: .scalar("inputHighlightAmount")),
                P("shadows", L("Shadows"), -1, 1, 0, binding: .scalar("inputShadowAmount")),
            ]),
            // Looks
            FilterDescriptor(.sepia, "CISepiaTone", .looks, L("Sepia"), [
                P("intensity", L("Intensity"), 0, 1, 1, binding: .scalar("inputIntensity")),
            ]),
            FilterDescriptor(.posterize, "CIColorPosterize", .looks, L("Posterize"), [
                P("levels", L("Levels"), 2, 30, 6, binding: .scalar("inputLevels")),
            ]),
            FilterDescriptor(.invert, "CIColorInvert", .looks, L("Invert")),
            FilterDescriptor(.monochrome, "CIColorMonochrome", .looks, L("Monochrome"), [
                P("intensity", L("Intensity"), 0, 1, 1, binding: .scalar("inputIntensity")),
            ], fixed: [FilterFixedInput("inputColor", [0.6, 0.6, 0.6, 1], isColor: true)]),
            FilterDescriptor(.photoNoir, "CIPhotoEffectNoir", .looks, L("Noir")),
            FilterDescriptor(.photoChrome, "CIPhotoEffectChrome", .looks, L("Chrome")),
            FilterDescriptor(.photoInstant, "CIPhotoEffectInstant", .looks, L("Instant")),
            FilterDescriptor(.photoFade, "CIPhotoEffectFade", .looks, L("Fade")),
            FilterDescriptor(.photoTransfer, "CIPhotoEffectTransfer", .looks, L("Transfer")),
            FilterDescriptor(.photoProcess, "CIPhotoEffectProcess", .looks, L("Process")),
            FilterDescriptor(.photoMono, "CIPhotoEffectMono", .looks, L("Mono")),
            FilterDescriptor(.photoTonal, "CIPhotoEffectTonal", .looks, L("Tonal")),
            FilterDescriptor(.thermal, "CIThermal", .looks, L("Thermal")),
            FilterDescriptor(.xray, "CIXRay", .looks, L("X-Ray")),
            FilterDescriptor(.comic, "CIComicEffect", .looks, L("Comic")),
            // Detail
            FilterDescriptor(.sharpen, "CISharpenLuminance", .detail, L("Sharpen"), [
                P("sharpness", L("Sharpness"), 0, 2, 0.4, binding: .scalar("inputSharpness")),
            ]),
            FilterDescriptor(.unsharpMask, "CIUnsharpMask", .detail, L("Unsharp Mask"), [
                P("radius", L("Radius"), 0, 25, 2.5, unit: .pixels, binding: .scalar("inputRadius")),
                P("intensity", L("Intensity"), 0, 2, 0.5, binding: .scalar("inputIntensity")),
            ], expandsExtent: true),
            FilterDescriptor(.gaussianBlur, "CIGaussianBlur", .detail, L("Gaussian Blur"), [
                P("radius", L("Radius"), 0, 50, 5, unit: .pixels, binding: .scalar("inputRadius")),
            ], expandsExtent: true),
            FilterDescriptor(.motionBlur, "CIMotionBlur", .detail, L("Motion Blur"), [
                P("radius", L("Radius"), 0, 50, 10, unit: .pixels, binding: .scalar("inputRadius")),
                P("angle", L("Angle"), -180, 180, 0, unit: .degrees, binding: .angle("inputAngle")),
            ], expandsExtent: true),
            FilterDescriptor(.noiseReduction, "CINoiseReduction", .detail, L("Noise Reduction"), [
                P("noise", L("Noise level"), 0, 0.1, 0.02, binding: .scalar("inputNoiseLevel")),
                P("sharpness", L("Sharpness"), 0, 2, 0.4, binding: .scalar("inputSharpness")),
            ]),
            FilterDescriptor(.median, "CIMedianFilter", .detail, L("Median")),
            // Stylize
            FilterDescriptor(.pixellate, "CIPixellate", .stylize, L("Pixellate"), [
                P("scale", L("Scale"), 1, 100, 8, unit: .pixels, binding: .scalar("inputScale")),
            ], centerKeys: center),
            FilterDescriptor(.hexPixellate, "CIHexagonalPixellate", .stylize, L("Hexagonal Pixellate"), [
                P("scale", L("Scale"), 1, 100, 8, unit: .pixels, binding: .scalar("inputScale")),
            ], centerKeys: center),
            FilterDescriptor(.crystallize, "CICrystallize", .stylize, L("Crystallize"), [
                P("radius", L("Radius"), 1, 100, 20, unit: .pixels, binding: .scalar("inputRadius")),
            ], centerKeys: center),
            FilterDescriptor(.pointillize, "CIPointillize", .stylize, L("Pointillize"), [
                P("radius", L("Radius"), 1, 100, 10, unit: .pixels, binding: .scalar("inputRadius")),
            ], centerKeys: center),
            FilterDescriptor(.edges, "CIEdges", .stylize, L("Edges"), [
                P("intensity", L("Intensity"), 0, 10, 1, binding: .scalar("inputIntensity")),
            ]),
            FilterDescriptor(.edgeWork, "CIEdgeWork", .stylize, L("Edge Work"), [
                P("radius", L("Radius"), 0, 20, 3, unit: .pixels, binding: .scalar("inputRadius")),
            ]),
            FilterDescriptor(.vignette, "CIVignette", .stylize, L("Vignette"), [
                P("intensity", L("Intensity"), 0, 2, 1, binding: .scalar("inputIntensity")),
                P("radius", L("Radius"), 0, 2, 1, binding: .scalar("inputRadius")),
            ]),
            FilterDescriptor(.bloom, "CIBloom", .stylize, L("Bloom"), [
                P("radius", L("Radius"), 0, 100, 10, unit: .pixels, binding: .scalar("inputRadius")),
                P("intensity", L("Intensity"), 0, 1, 0.5, binding: .scalar("inputIntensity")),
            ], expandsExtent: true),
            FilterDescriptor(.gloom, "CIGloom", .stylize, L("Gloom"), [
                P("radius", L("Radius"), 0, 100, 10, unit: .pixels, binding: .scalar("inputRadius")),
                P("intensity", L("Intensity"), 0, 1, 0.5, binding: .scalar("inputIntensity")),
            ], expandsExtent: true),
            screen(.dotScreen, "CIDotScreen", L("Dot Screen"), minWidth: 1),
            screen(.lineScreen, "CILineScreen", L("Line Screen"), minWidth: 1),
            screen(.hatchedScreen, "CIHatchedScreen", L("Hatched Screen"), minWidth: 1),
            screen(.cmykHalftone, "CICMYKHalftone", L("CMYK Halftone"), minWidth: 2, extra: [
                P("gcr", L("Gray replacement"), 0, 1, 1, binding: .scalar("inputGCR")),
                P("ucr", L("Undercolor removal"), 0, 1, 0.5, binding: .scalar("inputUCR")),
            ]),
        ]
    }()

    private static let byKind: [FilterKind: FilterDescriptor] = {
        var map: [FilterKind: FilterDescriptor] = [:]
        for d in all where map[d.kind] == nil { map[d.kind] = d }
        return map
    }()

    /// Total over FilterKind (tested); the fallback (never used) is a parameterless no-op.
    package static func descriptor(_ kind: FilterKind) -> FilterDescriptor {
        byKind[kind] ?? FilterDescriptor(kind, "CIColorControls", .color, kind.rawValue)
    }

    /// Every CoreImage name Snaptic may instantiate.
    package static let allowedCINames: Set<String> = Set(all.map(\.ciName)).union(internalCINames)

    package static func isAllowed(ciName: String) -> Bool { allowedCINames.contains(ciName) }

    package static func kinds(in category: FilterCategory) -> [FilterKind] {
        all.filter { $0.category == category }.map(\.kind)
    }

    /// CoreImage inputs for one instance; nil when it is disabled.
    package static func resolve(_ instance: FilterInstance) -> ResolvedFilter? {
        guard instance.enabled else { return nil }
        let d = descriptor(instance.kind)
        guard isAllowed(ciName: d.ciName) else { return nil }
        var scalars: [String: Double] = [:]
        var vectors: [String: [Double]] = [:]
        var colors: [String: [Double]] = [:]
        for f in d.fixed {
            if f.isColor { colors[f.key] = f.values } else { vectors[f.key] = f.values }
        }
        for p in d.parameters {
            let v = instance.value(p.key)
            switch p.binding {
            case .scalar(let key):
                scalars[key] = v
            case .angle(let key):
                scalars[key] = v * Double.pi / 180
            case .vectorX(let key):
                var vec = vectors[key] ?? [0, 0]
                vec[0] = v
                vectors[key] = vec
            case .vectorY(let key):
                var vec = vectors[key] ?? [0, 0]
                vec[1] = v
                vectors[key] = vec
            }
        }
        return ResolvedFilter(ciName: d.ciName, scalars: scalars, vectors: vectors, colors: colors,
                              centerKeys: d.centerKeys, expandsExtent: d.expandsExtent)
    }

    /// The enabled filters of a chain, in order, at most `maxFiltersPerChain`.
    package static func resolveChain(_ chain: [FilterInstance]) -> [ResolvedFilter] {
        Array(chain.prefix(maxFiltersPerChain).compactMap { resolve($0.sanitized()) })
    }
}
