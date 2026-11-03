import XCTest
@testable import Slate

/// The editor paints only the block around an edit, so the block maths has to
/// be exact: too small and markdown styling goes stale, too large and typing
/// slows down again.
final class ScopedRestyleTests: XCTestCase {
    private func scope(_ text: String, editing target: String, occurrence: Int = 1) -> NSRange? {
        let string = text as NSString
        var searchRange = NSRange(location: 0, length: string.length)
        var found = NSRange(location: NSNotFound, length: 0)
        for _ in 0..<occurrence {
            found = string.range(of: target, options: [], range: searchRange)
            guard found.location != NSNotFound else { return nil }
            searchRange = NSRange(location: NSMaxRange(found), length: string.length - NSMaxRange(found))
        }
        return MarkdownEditor.Coordinator.blockRange(around: found, in: string)
    }

    private func substring(_ text: String, _ range: NSRange?) -> String? {
        guard let range else { return nil }
        return (text as NSString).substring(with: range)
    }

    func testSingleBlockDocumentIsFullyCovered() {
        let text = "only a paragraph"
        let range = scope(text, editing: "paragraph")
        XCTAssertEqual(substring(text, range), text)
    }

    func testScopeIncludesNeighbouringBlocks() {
        let text = "one\n\ntwo\n\nthree\n\nfour"
        let range = scope(text, editing: "two")
        // The edited block plus one block on either side, so a merge with a
        // neighbour still repaints.
        XCTAssertEqual(substring(text, range), "one\n\ntwo\n\nthree\n\n")
    }

    func testScopeStartsAtDocumentStartForFirstBlock() {
        let text = "first\n\nsecond\n\nthird"
        let range = scope(text, editing: "first")
        XCTAssertEqual(substring(text, range), "first\n\nsecond\n\n")
    }

    func testScopeReachesEndForLastBlock() {
        let text = "first\n\nsecond\n\nthird"
        let range = scope(text, editing: "third")
        XCTAssertEqual(substring(text, range), "second\n\nthird")
    }

    func testEmptyEditAtStartReturnsFirstBlocks() {
        let text = "alpha\n\nbeta"
        let range = MarkdownEditor.Coordinator.blockRange(
            around: NSRange(location: 0, length: 0),
            in: text as NSString
        )
        XCTAssertEqual(substring(text, range), "alpha\n\nbeta")
    }

    func testEmptyDocumentHasNoScope() {
        XCTAssertNil(MarkdownEditor.Coordinator.blockRange(
            around: NSRange(location: 0, length: 0),
            in: "" as NSString
        ))
    }

    func testDirtyRangeBeyondEndIsClamped() {
        let text = "alpha\n\nbeta"
        let range = MarkdownEditor.Coordinator.blockRange(
            around: NSRange(location: 999, length: 5),
            in: text as NSString
        )
        XCTAssertEqual(substring(text, range), "alpha\n\nbeta")
    }

    // MARK: - Live preview block spans

    private func span(_ text: String, at location: Int) -> String? {
        let string = text as NSString
        return substring(text, MarkdownEditor.Coordinator.blockSpan(
            NSRange(location: location, length: 0),
            in: string
        ))
    }

    func testBlockSpanIsExactlyTheCaretBlock() {
        let text = "# Title\n\nBody text\n\nLast"
        XCTAssertEqual(span(text, at: 0), "# Title")
        XCTAssertEqual(span(text, at: 11), "Body text")
        XCTAssertEqual(span(text, at: 22), "Last")
    }

    func testCaretMoveWithinTwoBlockDocumentChangesSpan() {
        // Regression: a short note's widened scopes overlapped, so moving the
        // caret between blocks looked like no change and live preview never
        // revealed the block it landed in.
        let text = "# Title\n\nBody text"
        XCTAssertNotEqual(span(text, at: 2), span(text, at: 12))
    }
}
