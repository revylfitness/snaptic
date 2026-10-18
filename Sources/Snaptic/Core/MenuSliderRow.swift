import AppKit
import Combine
import SnapticKit

// Stub (owner: M). Hand-written by the lead in step 0 from PLAN 0.3 §5.1 (kind S): a disabled row with the contract
// signatures; M builds the AppKit slider view in step 1.

@MainActor final class MenuSliderRow: NSMenuItem {
    private let onChange: @MainActor (Double, DragPhase) -> Void
    private var sink: AnyCancellable?
    private(set) var value: Double?

    /// Leaves a disabled row with no view and no handler; never traps.
    required init(coder: NSCoder) {
        onChange = { _, _ in }
        super.init(coder: coder)
        isEnabled = false
    }

    init(title: String, symbol: String, value: Double?, range: ClosedRange<Double>, format: ValueFormat,
         discrete: Bool = false, control: ControlID? = nil,
         onChange: @escaping @MainActor (Double, DragPhase) -> Void) {
        self.onChange = onChange
        self.value = value
        super.init(title: title, action: nil, keyEquivalent: "")
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        isEnabled = false
    }

    /// Live updates while open; ignored during a drag.
    func bind(to publisher: AnyPublisher<Double?, Never>) {
        sink = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in MainActor.assumeIsolated { self?.setValue(v) } }
    }

    /// nil → slider disabled, value "—".
    func setValue(_ v: Double?) { value = v }
}
