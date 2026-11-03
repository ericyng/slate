import Foundation

/// One-entry cache of the last parsed document.
///
/// Split view parses the same text twice per keystroke — once to style the
/// source pane, once to render the preview pane. The parse is pure and the
/// text is identical, so the second caller reuses the first result.
final class MarkdownParseCache {
    static let shared = MarkdownParseCache()

    private let lock = NSLock()
    private var cachedText: String?
    private var cachedDocument: MarkdownDocument?

    func document(for text: String) -> MarkdownDocument {
        lock.lock()
        if let cachedText, let cachedDocument, cachedText == text {
            lock.unlock()
            return cachedDocument
        }
        lock.unlock()

        let document = MarkdownParser.parse(text)

        lock.lock()
        cachedText = text
        cachedDocument = document
        lock.unlock()
        return document
    }

    /// Drops the cached parse, e.g. when a vault closes.
    func clear() {
        lock.lock()
        cachedText = nil
        cachedDocument = nil
        lock.unlock()
    }
}
