import AppKit
import CoreAudio
import SnapticKit

// Audio output / microphone in use (owner: J; PLAN 0.3 §2.8): events only. Property listeners on the default output
// and input devices' DeviceIsRunningSomewhere, plus the default-device changes; HAL calls and listeners run on a
// private serial queue (they can block > 50 ms) and publish on main. Each listener is stored as a typed
// AudioObjectPropertyListenerBlock so Remove gets the same block. Reading a device property opens no stream: no input
// is ever captured and nothing prompts for the microphone. "Running" means the device's IO engine runs (apps may keep
// it running while silent; HW check).

@MainActor final class AudioMonitor: CriterionSource {
    static var kinds: Set<AwakeCriterionKind> { [.audio] }

    weak var context: AwakeContext?
    private let changes = ChangeFanout()
    private var active = false
    private var hal: AudioHAL?

    /// nil = unknown (inactive, or no such device).
    private(set) var outputActive: Bool?
    private(set) var microphoneActive: Bool?

    init() {}

    // MARK: AwakeServiceLifecycle

    func activate(_ context: AwakeContext, lifetime: Lifetime) {
        guard !active else { return }
        active = true
        self.context = context
        let box = CallbackTarget(self)
        let hal = AudioHAL { output, input in
            DispatchQueue.main.async { MainActor.assumeIsolated { box.target?.update(output: output, input: input) } }
        }
        self.hal = hal
        hal.start()
    }

    func deactivate() {
        guard active else { return }
        active = false
        hal?.stop()
        hal = nil
        outputActive = nil
        microphoneActive = nil
        context = nil
    }

    // MARK: CriterionSource

    func contribute(to facts: inout CriterionFacts) {
        guard active else { return }
        facts.audioOutput = outputActive
        facts.microphone = microphoneActive
    }

    func observe(_ lifetime: Lifetime, _ handler: @escaping @MainActor () -> Void) { changes.add(lifetime, handler) }

    private func update(output: Bool?, input: Bool?) {
        guard active, output != outputActive || input != microphoneActive else { return }
        outputActive = output
        microphoneActive = input
        changes.fire()
    }
}

/// The HAL side. Every member is touched only on `queue` (hence @unchecked Sendable); `publish` is called there too.
private final class AudioHAL: @unchecked Sendable {
    private let queue = DispatchQueue(label: "snaptic.awake.audio", qos: .utility)
    private let publish: @Sendable (Bool?, Bool?) -> Void
    private var running = false
    private var outputDevice = AudioObjectID(kAudioObjectUnknown)
    private var inputDevice = AudioObjectID(kAudioObjectUnknown)
    private var defaultOutputBlock: AudioObjectPropertyListenerBlock?
    private var defaultInputBlock: AudioObjectPropertyListenerBlock?
    private var outputRunningBlock: AudioObjectPropertyListenerBlock?
    private var inputRunningBlock: AudioObjectPropertyListenerBlock?

    init(publish: @escaping @Sendable (Bool?, Bool?) -> Void) {
        self.publish = publish
    }

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            var outAddr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            let outBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.defaultDeviceChanged() }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outAddr, queue, outBlock) == noErr {
                defaultOutputBlock = outBlock
            }
            var inAddr = Self.address(kAudioHardwarePropertyDefaultInputDevice)
            let inBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.defaultDeviceChanged() }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &inAddr, queue, inBlock) == noErr {
                defaultInputBlock = inBlock
            }
            defaultDeviceChanged()
        }
    }

    /// Asynchronous: the listeners are removed on the queue; nothing is published after this returns because the
    /// main side has already dropped this object.
    func stop() {
        queue.async { [self] in
            guard running else { return }
            running = false
            if let block = defaultOutputBlock {
                var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, block)
            }
            if let block = defaultInputBlock {
                var addr = Self.address(kAudioHardwarePropertyDefaultInputDevice)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, queue, block)
            }
            defaultOutputBlock = nil
            defaultInputBlock = nil
            unwatch(&outputDevice, &outputRunningBlock)
            unwatch(&inputDevice, &inputRunningBlock)
        }
    }

    // MARK: On the queue

    private func defaultDeviceChanged() {
        guard running else { return }
        let output = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        let input = Self.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        if output != outputDevice {
            unwatch(&outputDevice, &outputRunningBlock)
            watch(output, isOutput: true)
        }
        if input != inputDevice {
            unwatch(&inputDevice, &inputRunningBlock)
            watch(input, isOutput: false)
        }
        report()
    }

    private func watch(_ device: AudioObjectID, isOutput: Bool) {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        var addr = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.report() }
        guard AudioObjectAddPropertyListenerBlock(device, &addr, queue, block) == noErr else { return }
        if isOutput {
            outputDevice = device
            outputRunningBlock = block
        } else {
            inputDevice = device
            inputRunningBlock = block
        }
    }

    private func unwatch(_ device: inout AudioObjectID, _ block: inout AudioObjectPropertyListenerBlock?) {
        if device != AudioObjectID(kAudioObjectUnknown), let b = block {
            var addr = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectRemovePropertyListenerBlock(device, &addr, queue, b)
        }
        device = AudioObjectID(kAudioObjectUnknown)
        block = nil
    }

    private func report() {
        guard running else { return }
        publish(Self.isRunning(outputDevice), Self.isRunning(inputDevice))
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
        var addr = address(selector)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return status == noErr ? device : AudioObjectID(kAudioObjectUnknown)
    }

    private static func isRunning(_ device: AudioObjectID) -> Bool? {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        var addr = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }
}
