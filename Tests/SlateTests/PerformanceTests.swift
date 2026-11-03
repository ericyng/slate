import XCTest
@testable import Slate

/// Timing harness for the hot path: one keystroke reparses the note and styles
/// the edited block. Prints milliseconds per call so the numbers are visible in
/// the test log; it asserts only loose upper bounds to catch a collapse.
final class PerformanceTests: XCTestCase {

    /// A note roughly the size of a long real document: ~1,900 lines of mixed
    /// blocks with plenty of inline markers.
    static func longNote(sections: Int = 120) -> String {
        var out = ""
        for i in 1...sections {
            out += """
            ## Section \(i) — a heading with **bold** and *italic*

            Some prose about the \(i)th thing, with a [link](https://example.com/\(i)) and `code` inline.
            It continues for a while so the line is long enough to wrap in the editor.

            - first bullet with **emphasis**
            - second bullet with a \\#tag
            - [ ] a task that is not done
            - [x] a task that is done

            ```swift
            let value = \(i)
            print("section \\(value)")
            ```

            > A quote line about the \(i)th section.

            1. numbered one
            2. numbered two

            """
        }
        return out
    }

    private func ms(_ iterations: Int, _ body: () -> Void) -> Double {
        // Warm up so first-call caches do not skew the number.
        body()
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations { body() }
        return (CFAbsoluteTimeGetCurrent() - start) / Double(iterations) * 1000
    }

    func testMeasureParse() {
        let text = Self.longNote()
        XCTAssertGreaterThan(text.count, 40_000)
        let time = ms(20) { _ = MarkdownParser.parse(text) }
        print(String(format: "BENCH parse %.2f ms/document", time))
        XCTAssertLessThan(time, 60)
    }

    func testMeasureEditorRunsFullDocument() {
        let doc = MarkdownParser.parse(Self.longNote())
        let focus = NSRange(location: 900, length: 0)
        let time = ms(20) {
            _ = MarkdownRenderer.editorRuns(for: doc, bodySize: 15, focusRange: focus)
        }
        print(String(format: "BENCH editorRuns full %.2f ms", time))
        XCTAssertLessThan(time, 60)
    }

    func testMeasureEditorRunsScopedBlock() {
        let doc = MarkdownParser.parse(Self.longNote())
        let focus = NSRange(location: 900, length: 0)
        let scope = NSRange(location: 800, length: 200)
        let time = ms(20) {
            _ = MarkdownRenderer.editorRuns(for: doc, bodySize: 15, focusRange: focus, scope: scope)
        }
        print(String(format: "BENCH editorRuns scoped %.2f ms", time))
        XCTAssertLessThan(time, 40)
    }

    /// The actual keystroke path: parse the whole note, style one block.
    func testMeasureKeystroke() {
        let text = Self.longNote()
        _ = MarkdownParseCache.shared.document(for: text)
        let scope = NSRange(location: 800, length: 200)
        let time = ms(20) {
            let doc = MarkdownParser.parse(text)
            _ = MarkdownRenderer.editorRuns(for: doc, bodySize: 15,
                                            focusRange: NSRange(location: 900, length: 0),
                                            scope: scope)
        }
        print(String(format: "BENCH keystroke (parse + scoped style) %.2f ms", time))
        XCTAssertLessThan(time, 60)
    }
}
