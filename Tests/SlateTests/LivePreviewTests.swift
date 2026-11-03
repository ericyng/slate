import XCTest
import AppKit
@testable import Slate

/// Live preview keeps the document as plain source but conceals markdown
/// markers everywhere except the block holding the caret.
final class LivePreviewTests: XCTestCase {
    private let text = "# Title\n\nBody with **bold** here."
    private lazy var document = MarkdownParser.parse(text)

    /// The last run that applies to `index` wins, which is how the storage ends
    /// up painted.
    private func attributes(at index: Int, in runs: [(NSRange, [NSAttributedString.Key: Any])]) -> [NSAttributedString.Key: Any] {
        var result: [NSAttributedString.Key: Any] = [:]
        for (range, attrs) in runs where NSLocationInRange(index, range) {
            for (key, value) in attrs { result[key] = value }
        }
        return result
    }

    private var boldStart: Int {
        (text as NSString).range(of: "**bold**").location
    }

    func testSourceModeKeepsEveryMarkerVisible() {
        let runs = MarkdownRenderer.editorRuns(for: document, focusRange: nil)

        let heading = attributes(at: 0, in: runs)
        XCTAssertEqual(heading[.foregroundColor] as? NSColor, MarkdownTheme.tertiaryColor)

        let delimiter = attributes(at: boldStart, in: runs)
        XCTAssertEqual(delimiter[.foregroundColor] as? NSColor, MarkdownTheme.tertiaryColor)
        XCTAssertGreaterThan((delimiter[.font] as? NSFont)?.pointSize ?? 0, 5)
    }

    func testCaretBlockStaysRawAndOtherBlocksConceal() {
        // Caret inside the body block.
        let focus = NSRange(location: (text as NSString).range(of: "Body").location, length: 0)
        let runs = MarkdownRenderer.editorRuns(for: document, focusRange: focus)

        // Heading is not focused: "# " is concealed.
        let heading = attributes(at: 0, in: runs)
        XCTAssertEqual(heading[.foregroundColor] as? NSColor, .clear)
        XCTAssertLessThan((heading[.font] as? NSFont)?.pointSize ?? 99, 1)

        // The body's bold delimiters are in the focused block: still visible.
        let delimiter = attributes(at: boldStart, in: runs)
        XCTAssertEqual(delimiter[.foregroundColor] as? NSColor, MarkdownTheme.tertiaryColor)
        XCTAssertGreaterThan((delimiter[.font] as? NSFont)?.pointSize ?? 0, 5)

        // The bold text itself stays bold.
        let bold = attributes(at: boldStart + 2, in: runs)
        XCTAssertTrue((bold[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    func testMovingCaretRevealsTheNewBlockOnly() {
        let focus = NSRange(location: 0, length: 0)
        let runs = MarkdownRenderer.editorRuns(for: document, focusRange: focus)

        let heading = attributes(at: 0, in: runs)
        XCTAssertEqual(heading[.foregroundColor] as? NSColor, MarkdownTheme.tertiaryColor)

        let delimiter = attributes(at: boldStart, in: runs)
        XCTAssertEqual(delimiter[.foregroundColor] as? NSColor, .clear)
    }

    func testListMarkersStayVisibleEvenWhenConcealed() {
        let list = MarkdownParser.parse("- item one\n- item two")
        let runs = MarkdownRenderer.editorRuns(for: list, focusRange: NSRange(location: 4, length: 0))
        let secondMarker = attributes(at: 11, in: runs)
        // The "- " of the unfocused item is dimmed, not hidden: the dash carries
        // the list semantics.
        XCTAssertEqual(secondMarker[.foregroundColor] as? NSColor, MarkdownTheme.tertiaryColor)
    }
}
