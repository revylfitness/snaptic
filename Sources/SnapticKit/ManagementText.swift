import Foundation

// User words of the display-management controllers (owner: D): Keyboard Shortcuts action titles, "Keep this
// change?" labels, toasts, command-line answers, Display Information section names and the names Snaptic gives
// new virtual displays. 0.3 vocabulary only (PLAN 0.3 §4.2 copy rules and Apple terms: Sharper text, Virtual
// display, Saved layouts, Picture in Picture); an action's title matches the menu item for the same action.
// Names already stored in the configuration (a virtual display the person created or renamed) are never rewritten.

package enum ManagementText {
    // MARK: Action titles (Keyboard Shortcuts sheet; a switch is "… On or Off", like every other Displays action)

    package static var sharperTextOnOff: String { L("Sharper Text On or Off") }
    package static var matchTextSize: String { L("Match Text Size…") }
    package static var halfOfNativeResolution: String { L("Half of Native Resolution") }
    package static var notchAreaOnOff: String { L("Notch Area On or Off") }
    package static var useAsMainDisplay: String { L("Use as Main Display") }
    package static var highDynamicRangeOnOff: String { L("High Dynamic Range On or Off") }
    package static func virtualDisplayOnOff(_ number: Int) -> String { L("Virtual Display \(number) On or Off") }
    package static var hiDPIOnOff: String { L("HiDPI On or Off") }
    package static var mirroringOnOff: String { L("Mirroring On or Off") }
    package static var builtInDisplayOnOff: String { L("Built-in Display On or Off") }

    // MARK: "Keep this change?" labels (sentence case, like the other transaction labels)

    package static var turnOnSharperText: String { L("Turn on sharper text") }
    package static var turnOffSharperText: String { L("Turn off sharper text") }
    package static var changeSharperTextSize: String { L("Change sharper text size") }
    package static var restoreSharperText: String { L("Restore sharper text") }
    package static var placeVirtualDisplay: String { L("Place virtual display") }
    package static var mirrorVirtualDisplay: String { L("Mirror virtual display") }

    // MARK: Display Information sections (the feature's own name)

    package static var sharperTextSection: String { DisplaysUIText.title(.smartHiDPI) }
    package static var virtualDisplaysSection: String { DisplaysUIText.title(.virtualScreens) }
    package static var savedLayoutsSection: String { DisplaysUIText.title(.layouts) }
    package static var panelPropertiesSection: String { L("Rotation, underscan, and High Dynamic Range") }

    // MARK: Names of new virtual displays

    /// The virtual display behind sharper text, as macOS lists it in System Settings › Displays.
    package static func sharperTextDisplayName(_ physicalName: String) -> String { L("\(physicalName) (Sharper Text)") }
    /// A new virtual display without a name (also the name of a stored one that has none).
    package static var newVirtualDisplayName: String { L("Virtual Display") }

    // MARK: Toasts

    package static var sharperTextNeedsDisplay: String { L("Sharper text needs a connected display that isn’t mirrored.") }
    package static var noSharpSize: String { L("No sharp size fits this display.") }
    package static var sizeNeedsReconnect: String { L("This size needs the display to reconnect.") }
    package static func turnSharperTextBackOn(_ name: String) -> String { L("Turn sharper text back on for “\(name)”?") }
    package static var recordingDisplayCreated: String {
        L("Recording display created. To show it, add a Picture in Picture for it.")
    }
    package static func tooManyVirtualDisplays(_ limit: Int) -> String { L("You can create up to \(limit) virtual displays.") }
    package static func mirrorVirtualDisplayPrompt(_ name: String, onto target: String) -> String {
        L("Mirror “\(name)” onto “\(target)”?")
    }
    package static func streamVirtualDisplayPrompt(_ name: String, onto target: String, flipped: Bool) -> String {
        flipped ? L("Stream “\(name)” flipped onto “\(target)”?") : L("Stream “\(name)” onto “\(target)”?")
    }
    package static var layoutsNeedSerialNumbers: String {
        L("Saved layouts with displays that have no serial number can’t apply automatically.")
    }

    // MARK: Command-line answers

    package static var sharperTextOnlyOff: String { L("Sharper text can only be turned off from the command line") }
    package static var sharperTextAlreadyOff: String { L("Sharper text is already off") }
    package static var virtualDisplaysOff: String { L("Virtual displays are off") }
    package static var noSuchVirtualDisplay: String { L("No such virtual display") }
    package static var savedLayoutsOff: String { L("Saved layouts are off") }

    // MARK: Checks

    /// 0.2 and developer words the strings above never use (PLAN 0.3 §4.2; "HiDPI" stays only in "HiDPI On or Off",
    /// the resolution action PLAN §4.3 keeps, which `all` leaves out).
    package static let retiredWords = ["HiDPI", "Smart", "Virtual Screen", "virtual screen", "PIP", "OSD", "DDC", "XDR",
                                       "UI Size", "Native-Halved", "Headless", "monitor", "Layouts are"]

    /// Every string above, with sample arguments (for the vocabulary test).
    package static var all: [String] {
        [sharperTextOnOff, matchTextSize, halfOfNativeResolution, notchAreaOnOff, useAsMainDisplay,
         highDynamicRangeOnOff, virtualDisplayOnOff(3), mirroringOnOff, builtInDisplayOnOff,
         turnOnSharperText, turnOffSharperText, changeSharperTextSize, restoreSharperText, placeVirtualDisplay,
         mirrorVirtualDisplay,
         sharperTextSection, virtualDisplaysSection, savedLayoutsSection, panelPropertiesSection,
         sharperTextDisplayName("DELL U2720Q"), newVirtualDisplayName,
         sharperTextNeedsDisplay, noSharpSize, sizeNeedsReconnect, turnSharperTextBackOn("DELL U2720Q"),
         recordingDisplayCreated, tooManyVirtualDisplays(8), mirrorVirtualDisplayPrompt("Teleprompter", onto: "LG"),
         streamVirtualDisplayPrompt("Teleprompter", onto: "LG", flipped: true),
         streamVirtualDisplayPrompt("Teleprompter", onto: "LG", flipped: false), layoutsNeedSerialNumbers,
         sharperTextOnlyOff, sharperTextAlreadyOff, virtualDisplaysOff, noSuchVirtualDisplay, savedLayoutsOff]
    }
}
