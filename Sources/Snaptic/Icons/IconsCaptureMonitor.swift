import CoreAudio
import CoreMediaIO
import Foundation
import SnapticKit

/// Whether another app uses the camera or the microphone (PLAN 0.4 R3-90). macOS 27's restriction hides
/// MenuBarAgent's camera and microphone dots with the other icons, so Native shows the icons while capture runs
/// (`IconsCaptureGuard`).
///
/// Public properties only, read on demand: nothing opens a stream, nothing prompts, and no listener stays installed.
/// - Camera: any CoreMediaIO device's `DeviceIsRunningSomewhere`.
/// - Microphone: a device with input streams that runs somewhere, confirmed by a process (other than Snaptic) whose
///   input runs on a device. A headset runs for output alone, and `corespeechd` keeps input "running" with no device,
///   so neither counts. The process list costs a few ms, so it's read only when a candidate device runs.
///
/// Measured on macOS 27.2: the camera read takes under 0.01 ms, the device read about 0.07 ms, the process read about
/// 8 ms. Polled every `IconsCaptureGuard.pollInterval` only while `IconsCaptureGuard.polls(…)`.
@MainActor final class IconsCaptureMonitor {
    private let scheduler: IconsScheduler
    private var poll: IconsCancellable?

    /// The last poll's answer; false while not polling.
    private(set) var reported = false
    /// Uptime when capture was last seen running, by a poll or `inUseNow()`.
    private(set) var lastInUse: Double?
    var onChange: ((Bool) -> Void)?

    init(scheduler: IconsScheduler) {
        self.scheduler = scheduler
    }

    /// Reads now. Asked before every Native activation and by the system-item check.
    func inUseNow() -> Bool {
        let inUse = Self.cameraInUse() || Self.microphoneInUse()
        if inUse { lastInUse = ProcessInfo.processInfo.systemUptime }
        return inUse
    }

    /// `IconsCaptureGuard.expectsSystemItemChanges`.
    func expectsSystemItemChanges() -> Bool {
        IconsCaptureGuard.expectsSystemItemChanges(inUse: inUseNow(), lastInUse: lastInUse,
                                                   now: ProcessInfo.processInfo.systemUptime)
    }

    /// `IconsCaptureGuard.polls(…)`. Turning it off forgets the reported state without calling back.
    func setPolling(_ on: Bool) {
        if on, poll == nil {
            // The first read runs on the next turn, not inside the caller's presentation pass.
            schedule(after: 0)
        } else if !on {
            poll?.cancel()
            poll = nil
            reported = false
        }
    }

    /// The collapse gate just read capture as running: report it now, so the status row (and the CLI's line, which
    /// is that row) says why before the first poll. Polling follows, because the refused hide is still wanted.
    func gateFoundInUse() {
        reported = true
    }

    func stop() {
        poll?.cancel()
        poll = nil
        reported = false
        lastInUse = nil
        onChange = nil
    }

    private func schedule(after delay: Double = IconsCaptureGuard.pollInterval) {
        poll = scheduler.after(delay) { [weak self] in
            guard let self, self.poll != nil else { return }
            self.check()
            // `check()` may have turned polling off through the callback.
            if self.poll != nil { self.schedule() }
        }
    }

    private func check() {
        let inUse = inUseNow()
        guard inUse != reported else { return }
        reported = inUse
        EventLog.shared.record(.modules, inUse ? "Icons: camera or microphone in use" : "Icons: capture ended")
        onChange?(inUse)
    }

    // MARK: Camera (CoreMediaIO)

    private static func cameraInUse() -> Bool {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var devicesAddress = cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &devicesAddress, 0, nil, size, &used, &devices) == noErr else {
            return false
        }
        var runningAddress = cmioAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        return devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size).contains { device in
            var value: UInt32 = 0
            var read: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &runningAddress, 0, nil,
                                                   UInt32(MemoryLayout<UInt32>.size), &read, &value)
            return status == noErr && value != 0
        }
    }

    private static func cmioAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector,
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    // MARK: Microphone (CoreAudio)

    private static func microphoneInUse() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let candidate = objects(system, kAudioHardwarePropertyDevices).contains { device in
            !objects(device, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput).isEmpty
                && (uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0) != 0
        }
        guard candidate else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return objects(system, kAudioHardwarePropertyProcessObjectList).contains { process in
            guard (uint32(process, kAudioProcessPropertyIsRunningInput) ?? 0) != 0 else { return false }
            guard let pid = uint32(process, kAudioProcessPropertyPID), Int32(bitPattern: pid) != ownPID else { return false }
            return !objects(process, kAudioProcessPropertyDevices, kAudioObjectPropertyScopeInput).isEmpty
        }
    }

    private static func audioAddress(_ selector: AudioObjectPropertySelector,
                                      _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = audioAddress(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var out = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &out) == noErr else { return [] }
        return Array(out.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = audioAddress(selector, kAudioObjectPropertyScopeGlobal)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
