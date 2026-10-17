import Foundation
import SnapticKit
import SnapticShims

/// The `--virtual-host` helper (PLAN §9.3, R5.6): one process, one CGVirtualDisplay.
/// It never touches NSApplication, NSScreen, UserDefaults or TCC-guarded APIs. The display
/// disappears when this process exits, so parent death (EOF on stdin) and `shutdown` both
/// simply exit.
enum VirtualHostMain {
    static func run(_ arguments: [String]) -> Never {
        let session = VirtualHostSession()
        let args = HelperPrologue.run(arguments, kind: .virtualHost, onLine: { line in session.handle(line) })
        HelperPrologue.requireProtocol(args, VirtualHostProtocol.version)
        guard let writer = HelperPipeWriter(duplicating: 1, onBroken: { exit(0) }) else { exit(70) }
        session.writer = writer
        CFRunLoopRun()
        exit(0)
    }
}

/// Helper-side state. Used only on the main queue (lines are delivered there).
private final class VirtualHostSession: @unchecked Sendable {
    var writer: HelperPipeWriter?
    private var display: SNVirtualDisplayHandle?
    private var backing: VirtualBacking?
    private var hiDPI = false
    private var hdr = false

    func handle(_ line: Data) {
        guard let message = VirtualHostProtocol.decodeMessage(line) else {
            reply(.failed(requestID: nil, reason: .invalidRequest))
            return
        }
        switch message {
        case .hello(let version, _):
            if version == VirtualHostProtocol.version {
                reply(.ready(protocolVersion: VirtualHostProtocol.version))
            } else {
                reply(.failed(requestID: nil, reason: .protocolMismatch))
                finish(HelperPrologue.exitProtocolMismatch)
            }
        case .create(let rid, let spec, let initial, let serial, let backing):
            create(rid, spec: spec, initial: initial, serial: serial, backing: backing)
        case .setModes(let rid, let modes):
            setModes(rid, modes)
        case .shutdown:
            display?.invalidate()
            display = nil
            finish(0)
        }
    }

    private func create(_ rid: UInt64, spec: VirtualScreenSpec, initial: VirtualMode, serial: UInt32, backing: VirtualBacking) {
        guard display == nil else { return reply(.failed(requestID: rid, reason: .alreadyCreated)) }
        guard SNVirtualDisplay.isAvailable() else { return reply(.failed(requestID: rid, reason: .unavailable)) }
        let limit = SoCCaps.maxBackingDimension(ManagedHardware.soc)
        if let problem = VirtualHostProtocol.validate(spec: spec, initialMode: initial, backing: backing, maxDimension: limit) {
            return reply(.failed(requestID: rid, reason: problem))
        }
        let config = SNVirtualDisplayConfiguration()
        config.name = TextSanitizer.clean(spec.name, maxScalars: VirtualScreenSpec.maxNameScalars)
        config.vendorID = VirtualScreenSpec.vendorID
        config.productID = VirtualScreenSpec.productID
        config.serial = serial == 0 ? 1 : serial
        let mm = spec.sizeInMillimeters
        config.widthMillimeters = mm.width
        config.heightMillimeters = mm.height
        config.maxPixelsWide = UInt32(backing.pixelsWide)
        config.maxPixelsHigh = UInt32(backing.pixelsHigh)
        config.hiDPI = spec.hiDPI
        if let p = spec.primaries, p.isPlausible {
            config.redX = p.redX; config.redY = p.redY
            config.greenX = p.greenX; config.greenY = p.greenY
            config.blueX = p.blueX; config.blueY = p.blueY
            config.whiteX = p.whiteX; config.whiteY = p.whiteY
        }
        let hdr = spec.hdr && SNVirtualDisplay.supportsHDRModes()
        let mode = SNVirtualDisplayMode(width: UInt32(initial.width), height: UInt32(initial.height),
                                        refreshRate: initial.refreshHz, hdr: hdr)
        do {
            let handle = try SNVirtualDisplay.create(configuration: config, initialMode: mode)
            display = handle
            self.backing = backing
            hiDPI = spec.hiDPI
            self.hdr = hdr
            reply(.created(requestID: rid, displayID: handle.displayID))
        } catch {
            reply(.failed(requestID: rid, reason: Self.failure(error)))
        }
    }

    private func setModes(_ rid: UInt64, _ modes: [VirtualMode]) {
        guard let display, let backing else { return reply(.failed(requestID: rid, reason: .notCreated)) }
        if let problem = VirtualHostProtocol.validate(modes: modes, backing: backing) {
            return reply(.failed(requestID: rid, reason: problem))
        }
        let list = modes.map {
            SNVirtualDisplayMode(width: UInt32($0.width), height: UInt32($0.height), refreshRate: $0.refreshHz, hdr: hdr)
        }
        do {
            try SNVirtualDisplay.apply(modes: list, hiDPI: hiDPI, to: display)
            reply(.modesSet(requestID: rid))
        } catch {
            reply(.failed(requestID: rid, reason: Self.failure(error)))
        }
    }

    private static func failure(_ error: Error) -> VirtualHostFailure {
        let e = error as NSError
        guard e.domain == SNVirtualDisplayErrorDomain else { return .refused }
        switch e.code {
        case 1: return .unavailable
        case 3: return .invalidRequest
        default: return .refused
        }
    }

    private func reply(_ r: VirtualHostReply) {
        guard let data = VirtualHostProtocol.encode(r) else { return }
        writer?.send(data)
    }

    private func finish(_ code: Int32) -> Never {
        _ = writer?.flush(timeout: .milliseconds(500))
        exit(code)
    }
}
