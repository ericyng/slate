import XCTest
@testable import Slate

final class MarkdownTests: XCTestCase {

    private func kinds(_ text: String) -> [BlockKind] {
        MarkdownParser.parse(text).blocks.map { $0.kind }
    }

    func testHeadingLevels() {
        let doc = MarkdownParser.parse("# One\n\n### Three\nnot a heading\n")
        XCTAssertEqual(doc.blocks.count, 4)
        XCTAssertEqual(doc.blocks[0].kind, .heading(1))
        XCTAssertEqual(doc.text.substring(with: doc.blocks[0].contentRange), "One")
        XCTAssertEqual(doc.blocks[1].kind, .blank)
        XCTAssertEqual(doc.blocks[2].kind, .heading(3))
        XCTAssertEqual(doc.text.substring(with: doc.blocks[2].contentRange), "Three")
        XCTAssertEqual(doc.blocks[3].kind, .paragraph)
    }

    func testTitleFallsBackToFirstLine() {
        XCTAssertEqual(MarkdownParser.parse("# Hello\n\nBody").title, "Hello")
        XCTAssertEqual(MarkdownParser.parse("Plain first line\nSecond").title, "Plain first line")
        XCTAssertEqual(MarkdownParser.parse("").title, "")
    }

    func testCodeFence() {
        let text = "intro\n\n```swift\nlet a = 1\nlet b = 2\n```\n\nafter\n"
        let doc = MarkdownParser.parse(text)
        XCTAssertEqual(doc.blocks.map(\.kind), [.paragraph, .blank, .code("swift"), .blank, .paragraph])
        XCTAssertEqual(doc.text.substring(with: doc.blocks[2].contentRange), "let a = 1\nlet b = 2\n")
        // Inline markdown inside a fence must not be styled.
        XCTAssertTrue(doc.blocks[2].inlines.isEmpty)
    }

    func testUnterminatedFenceRunsToEnd() {
        let doc = MarkdownParser.parse("```\nno close\n")
        XCTAssertEqual(doc.blocks.count, 1)
        if case .code = doc.blocks[0].kind {} else { XCTFail("expected code block") }
    }

    func testListsAndTasks() {
        let text = "- bullet one\n  * nested\n1. first\n- [x] done\n- [ ] todo\n> quote\n---\n"
        XCTAssertEqual(kinds(text), [.bullet, .bullet, .numbered, .task(done: true), .task(done: false), .quote, .rule])
    }

    func testInlineSpans() {
        let text = "A **bold** and *italic* with `code` and ~~gone~~ plus [link](https://x.dev).\n"
        let doc = MarkdownParser.parse(text)
        let block = doc.blocks[0]
        let spans = block.inlines

        func has(_ kind: InlineSpan.Kind) -> Bool { spans.contains { $0.kind == kind } }
        XCTAssertTrue(has(.bold))
        XCTAssertTrue(has(.italic))
        XCTAssertTrue(has(.code))
        XCTAssertTrue(has(.strike))
        XCTAssertTrue(has(.link("https://x.dev")))

        let boldSpan = spans.first { $0.kind == .bold }!
        XCTAssertEqual(doc.text.substring(with: boldSpan.range), "bold")
        let italicSpan = spans.first { $0.kind == .italic }!
        XCTAssertEqual(doc.text.substring(with: italicSpan.range), "italic")
        let linkSpan = spans.first { if case .link = $0.kind { return true } else { return false } }!
        XCTAssertEqual(doc.text.substring(with: linkSpan.range), "link")
    }

    func testUnmatchedMarkersStayPlain() {
        let doc = MarkdownParser.parse("2 * 3 = 6 and a lone ** star\n")
        XCTAssertFalse(doc.blocks[0].inlines.contains { $0.kind == .bold })
        XCTAssertFalse(doc.blocks[0].inlines.contains { $0.kind == .italic })
    }

    func testRenderedDropsSyntax() {
        let text = "# Title\n\nSome **bold** text with a [link](https://x.dev) and `code`.\n\n- a bullet\n- [x] a task\n"
        let rendered = MarkdownRenderer.rendered(MarkdownParser.parse(text)).string
        XCTAssertFalse(rendered.contains("**"))
        XCTAssertFalse(rendered.contains("https://x.dev"))
        XCTAssertTrue(rendered.contains("Title"))
        XCTAssertTrue(rendered.contains("bold"))
        XCTAssertTrue(rendered.contains("•  a bullet"))
        XCTAssertTrue(rendered.contains("☑"))
    }

    func testEditorRunsCoverWholeDocument() {
        let doc = MarkdownParser.parse("# T\n\nbody **x**\n")
        let runs = MarkdownRenderer.editorRuns(for: doc)
        XCTAssertFalse(runs.isEmpty)
        // Every run must be inside the text.
        for (range, _) in runs {
            XCTAssertGreaterThanOrEqual(range.location, 0)
            XCTAssertLessThanOrEqual(NSMaxRange(range), doc.text.length)
        }
    }

    func testPlainText() {
        XCTAssertEqual(MarkdownDocument.plainText("## Heading"), "Heading")
        XCTAssertEqual(MarkdownDocument.plainText("- [x] Did it"), "Did it")
        XCTAssertEqual(MarkdownDocument.plainText("1. first **item**"), "first item")
        XCTAssertEqual(MarkdownDocument.plainText("See [the docs](https://a.b) now"), "See the docs now")
        XCTAssertEqual(MarkdownDocument.plainText("> quoted *text*"), "quoted text")
    }

    func testDerivedMetadata() {
        let url = URL(fileURLWithPath: "/tmp/Note.md")
        XCTAssertEqual(VaultStore.deriveTitle("# Real Title\n\nbody", url: url), "Real Title")
        XCTAssertEqual(VaultStore.deriveTitle("first line wins", url: url), "first line wins")
        XCTAssertEqual(VaultStore.deriveTitle("", url: url), "Note")
        XCTAssertEqual(VaultStore.deriveSnippet("# Title\n\n## Section\n\nActual text"), "Actual text")
        XCTAssertEqual(VaultStore.deriveSnippet("# Title\n\n- [x] Done thing"), "Done thing")
    }

    func testFilenameSanitising() {
        XCTAssertEqual(VaultStore.sanitizeFilename("a/b:c*d"), "a b c d")
        XCTAssertEqual(VaultStore.sanitizeFilename("  spaced  "), "spaced")
    }
}
