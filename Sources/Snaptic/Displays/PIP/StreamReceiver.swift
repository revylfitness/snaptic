import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

/// The SCStream output and delegate for one session: a separate nonisolated class
/// (PLAN §14.3 rule 5, A.6). It never references a controller: frames go into the
/// mailbox (through the filter pipeline when one is active), and events reach the
/// main thread through closures that hold only weak boxes.
final class StreamReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let mailbox: FrameMailbox
    /// The sample-handler queue (serial). Filters run here too.
    let queue: DispatchQueue

    private let lock = NSLock()
    private var pipeline: FilterPipeline?
    private var dropping = false
    private var onFrame: (@Sendable () -> Void)?
    private var onStop: (@Sendable (_ userDeclined: Bool) -> Void)?
    private var incompleteCount: UInt64 = 0

    init(mailbox: FrameMailbox) {
        self.mailbox = mailbox
        queue = DispatchQueue(label: "app.snaptic.pip.capture", qos: .userInteractive)
        super.init()
    }

    func setHandlers(onFrame: @escaping @Sendable () -> Void, onStop: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        self.onFrame = onFrame
        self.onStop = onStop
        lock.unlock()
    }

    func setPipeline(_ pipeline: FilterPipeline?) {
        lock.lock()
        self.pipeline = pipeline
        lock.unlock()
    }

    /// While dropping, frames are discarded on arrival (paused, hidden, occluded).
    func setDropping(_ value: Bool) {
        lock.lock()
        dropping = value
        lock.unlock()
        if value { mailbox.clear() }
    }

    /// Stops forwarding anything; the stream may still deliver a few frames.
    func detach() {
        lock.lock()
        onFrame = nil
        onStop = nil
        pipeline = nil
        dropping = true
        lock.unlock()
        mailbox.close()
    }

    var incompleteFrames: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return incompleteCount
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }
        lock.lock()
        let drop = dropping
        let pipeline = self.pipeline
        let signal = onFrame
        lock.unlock()
        guard !drop, let signal else { return }

        guard let attachments = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]])?.first,
              let statusRaw = attachments[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw) else { return }
        guard status == .complete else {
            if status != .idle {
                lock.lock()
                incompleteCount &+= 1
                lock.unlock()
            }
            return
        }
        guard let input = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let contentRect = Self.contentRect(attachments, buffer: input)

        var output: CVPixelBuffer = input
        if let pipeline, let filtered = pipeline.process(input) { output = filtered }
        if mailbox.put(output, contentRect: contentRect) { signal() }
    }

    /// The content's unit rect inside the buffer (window captures may not fill it).
    private static func contentRect(_ attachments: [SCStreamFrameInfo: Any], buffer: CVPixelBuffer) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        guard let dict = attachments[SCStreamFrameInfo.contentRect] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return full }
        let scale = (attachments[SCStreamFrameInfo.scaleFactor] as? CGFloat) ?? 1
        let contentScale = (attachments[SCStreamFrameInfo.contentScale] as? CGFloat) ?? 1
        let w = CGFloat(CVPixelBufferGetWidth(buffer)), h = CGFloat(CVPixelBufferGetHeight(buffer))
        guard w > 0, h > 0, scale > 0, contentScale > 0, rect.width > 0, rect.height > 0 else { return full }
        let k = scale * contentScale
        let unit = CGRect(x: rect.minX * scale / w, y: rect.minY * scale / h,
                          width: rect.width * k / w, height: rect.height * k / h)
        let clipped = unit.intersection(full)
        guard !clipped.isNull, clipped.width > 0.01, clipped.height > 0.01 else { return full }
        return clipped
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let ns = error as NSError
        let declined = ns.domain == SCStreamErrorDomain && ns.code == SCStreamError.Code.userDeclined.rawValue
        lock.lock()
        let handler = onStop
        lock.unlock()
        handler?(declined)
    }
}
