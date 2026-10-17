import CoreImage
import CoreVideo
import Foundation
import SnapticKit

/// The CoreImage chain of one session (PLAN §10, §4.10(5)): built-in filters only,
/// by allowlisted name, plus an optional `.cube` color cube. Configured from the
/// main thread with plain values; the CIFilter objects are built and used only on
/// the capture queue. Plugins are never loaded.
final class FilterPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private var chain: [ResolvedFilter] = []
    private var lut: CubeLUT?
    private var generation: UInt64 = 0

    // Capture-queue state.
    private var builtGeneration: UInt64 = .max
    private var filters: [(CIFilter, ResolvedFilter)] = []
    private var lutMatrix: CIFilter?
    private var lutCube: CIFilter?
    private var context: CIContext?
    private var pool: CVPixelBufferPool?
    private var poolWidth = 0
    private var poolHeight = 0
    private var failures: UInt64 = 0
    private var rendered: UInt64 = 0

    /// CoreImage's own built-in list, checked in addition to the Kit allowlist.
    private static let builtIn: Set<String> = Set(CIFilter.filterNames(inCategory: kCICategoryBuiltIn))

    init() {}

    /// Whether frames go through CoreImage at all.
    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !chain.isEmpty || lut != nil
    }

    var stats: (rendered: UInt64, failures: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (rendered, failures)
    }

    /// Main thread: the new chain applies from the next frame.
    func configure(chain: [ResolvedFilter], lut: CubeLUT?) {
        lock.lock()
        self.chain = chain.filter { FilterSpec.isAllowed(ciName: $0.ciName) }
        self.lut = lut?.renderable
        generation &+= 1
        lock.unlock()
    }

    /// Capture queue: the filtered frame, or nil to show the input unchanged.
    func process(_ input: CVPixelBuffer) -> CVPixelBuffer? {
        lock.lock()
        let gen = generation
        let wantChain = chain
        let wantLUT = lut
        lock.unlock()
        guard !wantChain.isEmpty || wantLUT != nil else {
            if builtGeneration != gen { teardown(); builtGeneration = gen }
            return nil
        }
        if builtGeneration != gen {
            build(wantChain, wantLUT)
            builtGeneration = gen
        }
        guard let context = context ?? makeContext() else { return fail() }
        self.context = context

        var image = CIImage(cvPixelBuffer: input)
        let extent = image.extent
        guard !extent.isEmpty, extent.isInfinite == false else { return fail() }
        for (filter, spec) in filters {
            let source = spec.expandsExtent ? image.clampedToExtent() : image
            filter.setValue(source, forKey: kCIInputImageKey)
            for key in spec.centerKeys where filter.inputKeys.contains(key) {
                filter.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: key)
            }
            guard let out = filter.outputImage else { continue }
            image = out.cropped(to: extent)
        }
        if let cube = lutCube {
            if let matrix = lutMatrix {
                matrix.setValue(image, forKey: kCIInputImageKey)
                if let out = matrix.outputImage { image = out }
            }
            cube.setValue(image, forKey: kCIInputImageKey)
            if let out = cube.outputImage { image = out.cropped(to: extent) }
        }
        filters.forEach { $0.0.setValue(nil, forKey: kCIInputImageKey) }

        let width = CVPixelBufferGetWidth(input), height = CVPixelBufferGetHeight(input)
        guard let output = makeBuffer(width: width, height: height) else { return fail() }
        let space = CVImageBufferGetColorSpace(input)?.takeUnretainedValue() ?? CGColorSpace(name: CGColorSpace.sRGB)
        context.render(image, to: output, bounds: extent, colorSpace: space)
        if let space { CVBufferSetAttachment(output, kCVImageBufferCGColorSpaceKey, space, .shouldPropagate) }
        lock.lock()
        rendered &+= 1
        lock.unlock()
        return output
    }

    /// Capture queue (or after the stream stopped): frees CoreImage state.
    func reset() {
        teardown()
        context = nil
        builtGeneration = .max
    }

    // MARK: Building

    private func fail() -> CVPixelBuffer? {
        lock.lock()
        failures &+= 1
        lock.unlock()
        return nil
    }

    private func teardown() {
        filters = []
        lutMatrix = nil
        lutCube = nil
        pool = nil
        poolWidth = 0
        poolHeight = 0
    }

    private func build(_ chain: [ResolvedFilter], _ lut: CubeLUT?) {
        filters = chain.compactMap { spec in Self.makeFilter(spec).map { ($0, spec) } }
        lutMatrix = nil
        lutCube = nil
        guard let lut else { return }
        guard FilterSpec.isAllowed(ciName: "CIColorCubeWithColorSpace"), Self.builtIn.contains("CIColorCubeWithColorSpace"),
              let cube = CIFilter(name: "CIColorCubeWithColorSpace") else { return }
        let keys = cube.inputKeys
        guard keys.contains("inputCubeDimension"), keys.contains("inputCubeData") else { return }
        cube.setValue(NSNumber(value: lut.size), forKey: "inputCubeDimension")
        cube.setValue(lut.rgbaFloatData(), forKey: "inputCubeData")
        if keys.contains("inputColorSpace"), let srgb = CGColorSpace(name: CGColorSpace.sRGB) {
            cube.setValue(srgb, forKey: "inputColorSpace")
        }
        lutCube = cube
        if !lut.hasUnitDomain, Self.builtIn.contains("CIColorMatrix"), let matrix = CIFilter(name: "CIColorMatrix") {
            let s = lut.inputScale.map { CGFloat($0) }, b = lut.inputBias.map { CGFloat($0) }
            let values: [(String, CIVector)] = [
                ("inputRVector", CIVector(x: s[0], y: 0, z: 0, w: 0)),
                ("inputGVector", CIVector(x: 0, y: s[1], z: 0, w: 0)),
                ("inputBVector", CIVector(x: 0, y: 0, z: s[2], w: 0)),
                ("inputAVector", CIVector(x: 0, y: 0, z: 0, w: 1)),
                ("inputBiasVector", CIVector(x: b[0], y: b[1], z: b[2], w: 0)),
            ]
            for (key, v) in values where matrix.inputKeys.contains(key) { matrix.setValue(v, forKey: key) }
            lutMatrix = matrix
        }
    }

    /// Only allowlisted built-ins, and only keys the filter declares (an unknown key
    /// would raise an Objective-C exception).
    private static func makeFilter(_ spec: ResolvedFilter) -> CIFilter? {
        guard FilterSpec.isAllowed(ciName: spec.ciName), builtIn.contains(spec.ciName),
              let filter = CIFilter(name: spec.ciName) else { return nil }
        filter.setDefaults()
        let keys = Set(filter.inputKeys)
        for (key, value) in spec.scalars where keys.contains(key) {
            filter.setValue(NSNumber(value: value), forKey: key)
        }
        for (key, value) in spec.vectors where keys.contains(key) && !value.isEmpty {
            let floats = value.map { CGFloat($0) }
            filter.setValue(CIVector(values: floats, count: floats.count), forKey: key)
        }
        for (key, value) in spec.colors where keys.contains(key) && value.count == 4 {
            filter.setValue(CIColor(red: CGFloat(value[0]), green: CGFloat(value[1]), blue: CGFloat(value[2]),
                                    alpha: CGFloat(value[3])), forKey: key)
        }
        return filter
    }

    private func makeContext() -> CIContext? {
        var options: [CIContextOption: Any] = [.cacheIntermediates: false]
        if let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) { options[.workingColorSpace] = linear }
        return CIContext(options: options)
    }

    private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        guard width > 0, height > 0 else { return nil }
        if pool == nil || poolWidth != width || poolHeight != height {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            let poolAttributes: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
            var created: CVPixelBufferPool?
            guard CVPixelBufferPoolCreate(nil, poolAttributes as CFDictionary, attributes as CFDictionary, &created)
                    == kCVReturnSuccess, let created else { return nil }
            pool = created
            poolWidth = width
            poolHeight = height
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess else { return nil }
        return buffer
    }
}

/// Imported LUT tables, stored as copies of the picked files in Snaptic's support
/// folder (0700 directory, 0600 files, atomic writes). Blocking I/O: call off main.
enum PIPLUTStore {
    static func directory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("Snaptic", isDirectory: true)
            .appendingPathComponent("Displays", isDirectory: true)
            .appendingPathComponent("LUTs", isDirectory: true)
    }

    static func path(for id: StableID) -> String? {
        directory()?.appendingPathComponent("\(id.rawValue).cube").path
    }

    /// Reads and validates a user-picked file (PLAN §4.10(6)), then stores a copy.
    static func importFile(atPath source: String, id: StableID) throws -> CubeLUT {
        let data = try CubeLUT.readPickedFile(atPath: source)
        let lut = try CubeLUT.parse(data)
        try write(data, id: id)
        return lut
    }

    static func load(_ id: StableID) throws -> CubeLUT {
        guard let path = path(for: id) else { throw CubeLUTError.unreadable }
        return try CubeLUT.parse(CubeLUT.readPickedFile(atPath: path))
    }

    static func delete(_ id: StableID) {
        guard let path = path(for: id) else { return }
        _ = unlink(path)
    }

    private static func ensureDirectory() throws -> URL {
        guard let dir = directory() else { throw CubeLUTError.unreadable }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(dir.path, &info) == 0, (UInt32(info.st_mode) & 0o170000) == 0o040000, info.st_uid == getuid() else {
            throw CubeLUTError.unreadable
        }
        _ = chmod(dir.path, 0o700)
        return dir
    }

    private static func write(_ data: Data, id: StableID) throws {
        let dir = try ensureDirectory()
        let destination = dir.appendingPathComponent("\(id.rawValue).cube").path
        let temp = dir.appendingPathComponent(".\(id.rawValue).\(UInt32.random(in: 0...UInt32.max)).tmp").path
        let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CubeLUTError.unreadable }
        var ok = true
        data.withUnsafeBytes { raw in
            guard var p = raw.baseAddress else { return }
            var left = raw.count
            while left > 0 {
                let n = Darwin.write(fd, p, left)
                if n < 0 {
                    if errno == EINTR { continue }
                    ok = false
                    return
                }
                left -= n
                p += n
            }
        }
        if ok, fsync(fd) != 0 { ok = false }
        _ = close(fd)
        guard ok, rename(temp, destination) == 0 else {
            _ = unlink(temp)
            throw CubeLUTError.unreadable
        }
        let dirFD = open(dir.path, O_RDONLY | O_CLOEXEC)
        if dirFD >= 0 {
            _ = fsync(dirFD)
            _ = close(dirFD)
        }
    }
}
