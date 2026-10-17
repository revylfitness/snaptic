import CoreGraphics
import Foundation
import SnapticKit
import SnapticShims

// CoreGraphics display configuration (owner: B). One Begin/Complete per batch, with an
// explicit scope; MonitorPanel steps (rotation, HDR, underscan) have no scope. Nonisolated:
// the app's transaction queue and the guard both apply changes through here.

/// How long a configuration lasts (trialScope is .forSession, PLAN §4.3).
enum ConfigScope: Equatable, Sendable {
    case forAppOnly, forSession, permanently

    init(_ final: FinalScope) { self = final == .permanently ? .permanently : .forSession }

    var option: CGConfigureOption {
        switch self {
        case .forAppOnly: return .forAppOnly
        case .forSession: return .forSession
        case .permanently: return .permanently
        }
    }
}

/// Private functions a batch may need (resolved by the caller: PrivateDisplayAPI in the
/// app, PrivateSymbolResolver in the guard).
struct CGConfigFunctions {
    typealias EnableFn = @convention(c) (OpaquePointer?, UInt32, Bool) -> Int32
    typealias CGSModeFn = @convention(c) (OpaquePointer?, UInt32, Int32) -> Int32
    var configureEnabled: EnableFn?
    var configureCGSMode: CGSModeFn?

    init(configureEnabled: EnableFn? = nil, configureCGSMode: CGSModeFn? = nil) {
        self.configureEnabled = configureEnabled
        self.configureCGSMode = configureCGSMode
    }

    /// Resolved without kill switches (guard and launch recovery: restore paths only).
    static func resolvedForRestore() -> CGConfigFunctions {
        var f = CGConfigFunctions()
        if let p = PrivateSymbolResolver.resolve(function: "CGSConfigureDisplayEnabled",
                                                 framework: PrivateSymbol.coreGraphicsPath) {
            f.configureEnabled = unsafeBitCast(p, to: EnableFn.self)
        }
        return f
    }
}

struct CGConfigResult: Equatable {
    var applied = 0
    var skipped = 0
    var failures: [String] = []
    var ok: Bool { failures.isEmpty }
}

enum CGConfig {
    /// Applies the CG part of `changes` (mode, origin, mirror, enabled, main) in one
    /// Begin/Complete. Modes are re-resolved against a fresh list; a mode that no longer
    /// resolves fails the whole batch (nothing is applied).
    static func apply(_ changes: [DisplayChange], scope: ConfigScope, functions: CGConfigFunctions,
                      hiddenModes: [UInt32: [DisplayModeDescriptor]] = [:]) -> CGConfigResult {
        var result = CGConfigResult()
        let cg = changes.filter { !$0.isMonitorPanel }
        guard !cg.isEmpty else { return result }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else {
            result.failures.append("begin")
            return result
        }
        var failed = false
        for change in cg {
            var err: CGError = .success
            switch change {
            case .mode(let id, let ref):
                if let mode = DisplayModes.cgMode(for: ref, display: id) {
                    err = CGConfigureDisplayWithDisplayMode(cfg, id, mode, nil)
                } else if let hidden = hiddenModes[id], let match = DisplayModeDescriptor.resolve(ref, in: hidden),
                          let number = match.cgsModeNumber, let fn = functions.configureCGSMode {
                    err = CGError(rawValue: fn(cfg, id, number)) ?? .failure
                } else {
                    result.failures.append("mode \(id): no longer offered")
                    failed = true
                }
            case .origin(let id, let x, let y):
                err = CGConfigureDisplayOrigin(cfg, id, x, y)
            case .mirror(let id, let source):
                err = CGConfigureDisplayMirrorOfDisplay(cfg, id, source ?? kCGNullDirectDisplay)
            case .enabled(let id, let on):
                if let fn = functions.configureEnabled {
                    err = CGError(rawValue: fn(cfg, id, on)) ?? .failure
                } else {
                    result.failures.append("enable \(id): unavailable")
                    failed = true
                }
            case .main(let id):
                // The main display is the one at (0, 0); CG moves the others with it.
                err = CGConfigureDisplayOrigin(cfg, id, 0, 0)
            case .rotation, .underscan, .hdr:
                continue
            }
            if err != .success {
                result.failures.append("\(change.property.rawValue) \(change.displayID): \(err.rawValue)")
                failed = true
            }
            if failed { break }
        }
        if failed {
            CGCancelDisplayConfiguration(cfg)
            return result
        }
        let err = CGCompleteDisplayConfiguration(cfg, scope.option)
        if err == .success {
            result.applied = cg.count
        } else {
            result.failures.append("complete: \(err.rawValue)")
        }
        return result
    }

    /// Applies one MonitorPanel change. Rotation is asynchronous: callers poll `CGDisplayRotation`.
    @discardableResult
    static func applyMonitorPanel(_ change: DisplayChange) -> Bool {
        switch change {
        case .rotation(let id, let degrees):
            return SNMonitorPanel.setOrientation(Int32(Invariants.normalizedRotation(degrees)), display: id)
        case .hdr(let id, let on):
            return SNMonitorPanel.setPrefersHDR(on, display: id)
        case .underscan(let id, let value):
            return SNMonitorPanel.setUnderscan(Float(min(max(value, 0), 1)), display: id)
        default:
            return false
        }
    }

    /// Whether MonitorPanel can revert/apply this kind of change in this process.
    static func monitorPanelCanApply(_ change: DisplayChange) -> Bool {
        switch change {
        case .rotation: return SNMonitorPanel.isVerified("setOrientation:")
        case .hdr: return SNMonitorPanel.isVerified("setPreferHDRModes:")
        case .underscan: return SNMonitorPanel.isVerified("setUnderscan:")
        default: return true
        }
    }

    /// Splits CG changes by the scope Keep re-applies them with (R5.2): one `.permanently`
    /// batch (modes, origins, main) and one `.forSession` batch (mirrors, disable).
    static func keepBatches(_ changes: [DisplayChange]) -> (permanent: [DisplayChange], session: [DisplayChange]) {
        (changes.filter { $0.keepScope == .permanently }, changes.filter { $0.keepScope == .forSession })
    }
}
