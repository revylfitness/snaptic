import AppKit
import SnapticKit

// Stub (owner: M). Hand-written by the lead in step 0 from PLAN 0.3 §5.1 (kind S). MenuKit.switchHeader hosts this
// view in M's build: bold title + NSSwitch (.small) + up to two secondary lines; fixed height while the menu is open.

@MainActor final class MenuSwitchHeaderView: NSView {
    private(set) var title: String
    private(set) var isOn: Bool
    private(set) var detail: [String]

    init(title: String, isOn: Bool, detail: [String]) {
        self.title = title
        self.isOn = isOn
        self.detail = detail
        super.init(frame: NSRect(x: 0, y: 0, width: MenuKit.width, height: 26))
    }

    required init?(coder: NSCoder) {
        title = ""
        isOn = false
        detail = []
        super.init(coder: coder)
    }

    func update(isOn: Bool, detail: [String]) {
        self.isOn = isOn
        self.detail = detail
    }
}
