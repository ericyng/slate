import XCTest
import AppKit
@testable import Slate

/// Clicking a checkbox in reading mode has to reach the right source line.
/// That is pure hit-testing, so it can be checked without a running app: lay
/// the rendered page out in a `PreviewTextView` and click the box glyph.
@MainActor
final class PreviewTextViewTests: XCTestCase {

    private let source = "# List\n\n- [ ] first\n- [x] second\n"

    private func makeView() -> (PreviewTextView, NSWindow) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled],
                              backing: .buffered,
                              defer: false)
        let view = PreviewTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        view.isEditable = false
        view.isSelectable = true
        view.textContainerInset = NSSize(width: 10, height: 22)
        view.textContainer?.lineFragmentPadding = 2
        view.textContainer?.widthTracksTextView = true
        window.contentView = view
        view.textStorage?.setAttributedString(MarkdownRenderer.rendered(MarkdownParser.parse(source)))
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        return (view, window)
    }

    /// Clicks the checkbox whose attachment carries `location`.
    private func click(checkboxAt location: Int, in view: PreviewTextView) {
        guard let storage = view.textStorage,
              let layoutManager = view.layoutManager,
              let container = view.textContainer else {
            return XCTFail("text view is not laid out")
        }
        var boxIndex: Int?
        storage.enumerateAttribute(.slateTaskLocation,
                                   in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if (value as? Int) == location {
                boxIndex = range.location
                stop.pointee = true
            }
        }
        guard let boxIndex else { return XCTFail("no checkbox at \(location)") }

        let glyph = layoutManager.glyphIndexForCharacter(at: boxIndex)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                              in: container)
        let point = NSPoint(x: rect.midX + view.textContainerOrigin.x,
                            y: rect.midY + view.textContainerOrigin.y)
        let event = NSEvent.mouseEvent(with: .leftMouseDown,
                                      location: view.convert(point, to: nil),
                                      modifierFlags: [],
                                      timestamp: 0,
                                      windowNumber: view.window?.windowNumber ?? 0,
                                      context: nil,
                                      eventNumber: 0,
                                      clickCount: 1,
                                      pressure: 1)
        guard let event else { return XCTFail("could not build a mouse event") }
        view.mouseDown(with: event)
    }

    func testClickingEachBoxReportsItsSourceLine() {
        let (view, window) = makeView()
        defer { window.contentView = nil }
        let ns = source as NSString

        var toggled: [Int] = []
        view.onToggleTask = { toggled.append($0) }

        click(checkboxAt: ns.range(of: "- [ ]").location, in: view)
        click(checkboxAt: ns.range(of: "- [x]").location, in: view)

        XCTAssertEqual(toggled, [ns.range(of: "- [ ]").location, ns.range(of: "- [x]").location])
    }

    func testClickingProseDoesNotToggleATask() {
        let (view, window) = makeView()
        defer { window.contentView = nil }

        // Middle of the first heading line, well away from any box. Asking the
        // hit test directly avoids starting a selection tracking loop, which a
        // real `mouseDown` would enter and wait on.
        let point = NSPoint(x: 30 + view.textContainerOrigin.x,
                            y: 22 + view.textContainerOrigin.y + 8)
        let event = NSEvent.mouseEvent(with: .leftMouseDown,
                                      location: view.convert(point, to: nil),
                                      modifierFlags: [],
                                      timestamp: 0,
                                      windowNumber: window.windowNumber,
                                      context: nil,
                                      eventNumber: 0,
                                      clickCount: 1,
                                      pressure: 1)!
        XCTAssertNil(view.taskLocation(for: event))
    }
}
