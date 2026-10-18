import Foundation
import XCTest
@testable import SnapticKit

/// Every (?) help link in Settings (`SettingsHelpAnchors.anchors`) lands on a heading of README.md (review5 ux N4).
/// README.md is read from the checkout; its headings become GitHub anchors (`HelpAnchorSlug`).
///
/// `pendingReadmeAnchors` lists the headings the step-5 README rewrite adds (lead): an anchor in that list may be
/// missing until then, and the test skips with the list instead of failing. Any other missing anchor fails, and so
/// does a pending anchor the README already has (take it off the list).
final class HelpAnchorsReadmeTests: XCTestCase {
    /// Step 5 (lead): README headings the (?) links already point to. Heading text → anchor:
    /// "## Menu Bar" → menu-bar, "## Awake" → awake, "### Brightness" → brightness, "### Hardware controls" →
    /// hardware-controls, "### Color" → color, "### Keyboard" → keyboard, "### Display information" →
    /// display-information, "## General" → general (if General's (?) moves off "modules", review5 ux N4).
    static let pendingReadmeAnchors: Set<String> = [
        "menu-bar", "awake", "brightness", "hardware-controls", "color", "keyboard", "display-information", "general",
    ]

    private func readme() throws -> String {
        // Tests/SnapticKitTests/<this file> → the package root.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("README.md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("README.md not found at \(url.path) (the test needs a source checkout)")
        }
        return text
    }

    func testEveryHelpAnchorIsAReadmeHeading() throws {
        let headings = Set(HelpAnchorSlug.anchors(markdown: try readme()))
        XCTAssertFalse(headings.isEmpty, "README.md has no headings")
        let used = Set(SettingsHelpAnchors.anchors.values)
        let missing = used.subtracting(headings)
        let unexpected = missing.subtracting(Self.pendingReadmeAnchors).sorted()
        XCTAssertEqual(unexpected, [], "(?) anchors with no README heading (add the heading, or fix the anchor): "
                       + unexpected.joined(separator: ", "))
        let landed = Self.pendingReadmeAnchors.intersection(headings).sorted()
        XCTAssertEqual(landed, [], "README now has these headings: take them off pendingReadmeAnchors: "
                       + landed.joined(separator: ", "))
        let waiting = missing.intersection(Self.pendingReadmeAnchors).sorted()
        if !waiting.isEmpty {
            throw XCTSkip("README step 5 pending: (?) anchors without a heading yet: " + waiting.joined(separator: ", "))
        }
    }

    // MARK: The slug rules (pinned, so a README check can trust them)

    func testSlugFollowsGitHub() {
        XCTAssertEqual(HelpAnchorSlug.slug("Window Switcher"), "window-switcher")
        XCTAssertEqual(HelpAnchorSlug.slug("Install and build"), "install-and-build")
        XCTAssertEqual(HelpAnchorSlug.slug("Hardware controls (DDC)"), "hardware-controls-ddc")
        XCTAssertEqual(HelpAnchorSlug.slug("`snaptic awake` & holds"), "snaptic-awake--holds")
        XCTAssertEqual(HelpAnchorSlug.slug("[Awake](docs/awake.md) on_battery"), "awake-on_battery")
        XCTAssertEqual(HelpAnchorSlug.slug("Display information  "), "display-information")
        XCTAssertEqual(HelpAnchorSlug.slug("Größe"), "größe")
    }

    func testAnchorsSkipCodeBlocksAndNumberDuplicates() {
        let md = """
        # Snaptic
        Text with # not a heading
        ## Awake ##
        ```sh
        # a shell comment
        ```
        ### Awake
        #NoSpace
        ~~~
        ## Fenced
        ~~~
            # indented code
        """
        XCTAssertEqual(HelpAnchorSlug.anchors(markdown: md), ["snaptic", "awake", "awake-1"])
    }

    func testCurrentAnchorsAreWellFormed() {
        for (route, anchor) in SettingsHelpAnchors.anchors {
            XCTAssertEqual(HelpAnchorSlug.slug(anchor), anchor, "\(route): \(anchor) is not in slug form")
        }
    }
}

/// GitHub's heading anchors, as far as README.md needs them: ATX headings (`#` to `######` plus a space, up to three
/// spaces of indent) outside fenced code blocks; the text without inline code ticks, link targets or closing `#`s;
/// lowercased; everything but letters, digits, `-`, `_` and spaces dropped; spaces → `-`; a repeated slug gets
/// `-1`, `-2`, ….
enum HelpAnchorSlug {
    static func slug(_ heading: String) -> String {
        var text = heading
        // [label](target) → label
        while let open = text.range(of: "]("), let close = text[open.upperBound...].firstIndex(of: ")"),
              let start = text[..<open.lowerBound].lastIndex(of: "[") {
            let label = text[text.index(after: start)..<open.lowerBound]
            text.replaceSubrange(start...close, with: label)
        }
        text = text.trimmingCharacters(in: .whitespaces).lowercased()
        var out = ""
        for c in text {
            if c.isLetter || c.isNumber || c == "-" || c == "_" { out.append(c) } else if c == " " { out.append("-") }
        }
        return out
    }

    static func anchors(markdown: String) -> [String] {
        var result: [String] = []
        var seen: [String: Int] = [:]
        var fence: String?
        for raw in markdown.components(separatedBy: "\n") {
            let indent = raw.prefix { $0 == " " }.count
            let line = raw.dropFirst(indent)
            if indent <= 3, let marker = ["```", "~~~"].first(where: { line.hasPrefix($0) }) {
                if fence == nil { fence = marker } else if fence == marker { fence = nil }
                continue
            }
            guard fence == nil, indent <= 3 else { continue }
            let hashes = line.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes) else { continue }
            let rest = line.dropFirst(hashes)
            guard rest.first == " " else { continue }
            var text = rest.trimmingCharacters(in: .whitespaces)
            // Closing hashes ("## Awake ##").
            while text.hasSuffix("#") { text.removeLast() }
            let base = slug(text)
            let n = seen[base, default: 0]
            seen[base] = n + 1
            result.append(n == 0 ? base : "\(base)-\(n)")
        }
        return result
    }
}
