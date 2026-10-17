import AppKit
import ApplicationServices

/// Thin helpers over the Accessibility (AX) C API.
enum AX {
    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (copy(element, attribute) as? NSNumber)?.boolValue
    }

    /// Every entry is type-checked: an app controls what it returns here, and a
    /// non-element value must never reach functions that expect an element.
    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let array = copy(element, attribute) as? [AnyObject] else { return [] }
        return array.compactMap { value in
            CFGetTypeID(value) == AXUIElementGetTypeID() ? (value as! AXUIElement) : nil
        }
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func position(_ element: AXUIElement) -> CGPoint? {
        guard let value = copy(element, kAXPositionAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement) -> CGSize? {
        guard let value = copy(element, kAXSizeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    static func setBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) {
        // NSNumber(value: Bool) is the kCFBooleanTrue / kCFBooleanFalse singleton.
        AXUIElementSetAttributeValue(element, attribute as CFString, NSNumber(value: value))
    }

    static func setElement(_ element: AXUIElement, _ attribute: String, _ value: AXUIElement) {
        AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }

    static func perform(_ element: AXUIElement, _ action: String) {
        AXUIElementPerformAction(element, action as CFString)
    }
}
