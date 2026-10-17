import AppKit
import SwiftUI
import SnapticKit

/// Big numbered labels on each screen for 3 s (the "Identify Displays" action). Numbers
/// follow the Displays menu order. Click-through, all Spaces, announced to VoiceOver,
/// and it skips the fades when Reduce Motion is on.
@MainActor final class IdentifyOverlay: NSObject {
    struct Label {
        /// "1", or "1 · 2" for displays mirrored onto one screen.
        let number: String
        let name: String
        let screen: NSScreen
    }

    static let duration: TimeInterval = 3
    private var windows: [NSWindow] = []
    private var dismissWork: DispatchWorkItem?

    override init() { super.init() }

    var isShowing: Bool { !windows.isEmpty }

    func show(_ labels: [Label]) {
        dismiss(animated: false)
        guard !labels.isEmpty else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for label in labels {
            let window = Self.makeWindow(for: label)
            window.alphaValue = reduceMotion ? 1 : 0
            window.orderFrontRegardless()
            windows.append(window)
        }
        if !reduceMotion {
            let shown = windows
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = 0.2
                for window in shown { window.animator().alphaValue = 1 }
            }
        }
        announce(labels)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss(animated: true) }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }

    func dismiss(animated: Bool = false) {
        dismissWork?.cancel()
        dismissWork = nil
        let closing = windows
        windows = []
        guard !closing.isEmpty else { return }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = 0.25
                for window in closing { window.animator().alphaValue = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated { closing.forEach { $0.orderOut(nil) } }
            }
        } else {
            closing.forEach { $0.orderOut(nil) }
        }
    }

    private static func makeWindow(for label: Label) -> NSWindow {
        let size = NSSize(width: 340, height: 250)
        let frame = label.screen.frame
        let rect = NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                          width: size.width, height: size.height)
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.setFrame(rect, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = NSHostingView(rootView: IdentifyLabelView(number: label.number, name: label.name))
        return window
    }

    private func announce(_ labels: [Label]) {
        let text = labels.map { "\($0.number): \($0.name)" }.joined(separator: ", ")
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: L("Identifying displays. \(text)"),
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}

private struct IdentifyLabelView: View {
    let number: String
    let name: String

    var body: some View {
        VStack(spacing: 6) {
            Text(number)
                .font(.system(size: number.count > 2 ? 72 : 120, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Text(name)
                .font(.title2.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(width: 340, height: 250)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color.black.opacity(0.78)))
        .accessibilityElement(children: .combine)
    }
}
