import SwiftUI
import AppKit

/// Editable markdown surface: plain text on disk, styled live in the editor.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    /// Body text size in points; headings, lists and code scale with it.
    var bodySize: CGFloat = MarkdownTheme.bodySize
    var spellCheck: Bool = true
    /// Live preview: hide markers and inline delimiters on every block except
    /// the one holding the caret.
    var concealSyntax: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, bodySize: bodySize)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        configure(textView, spellCheck: spellCheck)
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.installedSize = bodySize
        context.coordinator.installedConceal = concealSyntax
        context.coordinator.concealSyntax = concealSyntax
        EditorCommandCenter.shared.textView = textView
        context.coordinator.restyle()

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.textView = textView
        context.coordinator.bodySize = bodySize
        context.coordinator.concealSyntax = concealSyntax
        EditorCommandCenter.shared.textView = textView

        textView.isContinuousSpellCheckingEnabled = spellCheck

        if textView.string != text {
            textView.string = text
            textView.undoManager?.removeAllActions()
            context.coordinator.restyle()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            context.coordinator.installedSize = bodySize
            context.coordinator.installedConceal = concealSyntax
        } else if context.coordinator.installedSize != bodySize || context.coordinator.installedConceal != concealSyntax {
            // Font size or layout mode changed: repaint the existing text.
            context.coordinator.installedSize = bodySize
            context.coordinator.installedConceal = concealSyntax
            context.coordinator.restyle()
        }
    }

    private func configure(_ textView: NSTextView, spellCheck: Bool) {
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Markdown must be typed literally.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = spellCheck
        textView.isGrammarCheckingEnabled = false

        textView.textContainerInset = NSSize(width: 10, height: 22)
        textView.textContainer?.lineFragmentPadding = 2
        textView.insertionPointColor = .controlAccentColor
        textView.typingAttributes = [
            .font: MarkdownTheme.body(size: bodySize),
            .foregroundColor: MarkdownTheme.bodyColor,
            .paragraphStyle: MarkdownRenderer.paragraphStyle(for: .paragraph, indent: 0, bodySize: bodySize)
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var bodySize: CGFloat
        /// The size the current attributes were painted with, so Settings
        /// changes trigger exactly one repaint.
        var installedSize: CGFloat
        /// Whether the last repaint concealed syntax, so a layout switch forces
        /// one full repaint.
        var installedConceal = false
        var concealSyntax = false
        weak var textView: NSTextView?
        /// Fence markers change how everything after them parses, so a change
        /// in their count forces a full restyle.
        private var lastFenceCount: Int?
        /// Selection range used by the last repaint, to know which block is
        /// currently revealed in live preview.
        private var lastFocus: NSRange?

        init(text: Binding<String>, bodySize: CGFloat) {
            self.text = text
            self.bodySize = bodySize
            self.installedSize = bodySize
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let edited = textView.textStorage?.editedRange ?? NSRange(location: NSNotFound, length: 0)
            restyle(dirtyRange: edited.location == NSNotFound ? nil : edited)
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
        }

        /// In live preview, moving the caret reveals the block it lands in and
        /// conceals the block it left.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard concealSyntax, let textView, !textView.hasMarkedText() else { return }
            let string = textView.string as NSString
            guard string.length > 0 else { return }

            let current = textView.selectedRange()
            let previous = lastFocus
            guard Self.blockSpan(previous, in: string) != Self.blockSpan(current, in: string) else { return }

            let currentBlock = Self.blockRange(around: current, in: string)
            let previousBlock = previous.flatMap { Self.blockRange(around: $0, in: string) }
            let scope: NSRange?
            if let a = currentBlock, let b = previousBlock {
                scope = NSUnionRange(a, b)
            } else {
                scope = nil
            }
            restyle(scopeOverride: scope)
        }

        /// Repaints the edited block instead of the whole document, which keeps
        /// typing smooth in long notes. Passing nil restyles everything.
        func restyle(dirtyRange: NSRange? = nil, scopeOverride: NSRange? = nil) {
            guard let textView, let storage = textView.textStorage, !textView.hasMarkedText() else { return }
            let length = storage.length
            if length == 0 {
                textView.typingAttributes = Self.baseAttributes(bodySize: bodySize)
                lastFocus = nil
                return
            }

            let text = textView.string
            let string = text as NSString
            guard string.length == length else { return }

            let focus = concealSyntax ? textView.selectedRange() : nil
            lastFocus = focus

            let document = MarkdownParseCache.shared.document(for: text)

            // Fence markers change how everything after them parses, so a change
            // in their count forces a full restyle.
            let fenceCount = document.fenceCount
            let structureChanged = lastFenceCount.map { $0 != fenceCount } ?? false
            lastFenceCount = fenceCount

            let scope: NSRange
            if let override = scopeOverride {
                scope = NSIntersectionRange(override, NSRange(location: 0, length: length))
            } else if !structureChanged, let dirty = dirtyRange, let block = Self.blockRange(around: dirty, in: string) {
                scope = block
            } else {
                scope = NSRange(location: 0, length: length)
            }
            guard scope.length > 0 else { return }

            // Only blocks that intersect the scope produce runs.
            let runs = MarkdownRenderer.editorRuns(for: document, bodySize: bodySize,
                                                   focusRange: focus, scope: scope)

            let undo = textView.undoManager
            undo?.disableUndoRegistration()
            storage.beginEditing()
            storage.setAttributes(Self.baseAttributes(bodySize: bodySize), range: scope)
            for (range, attributes) in runs {
                let intersection = NSIntersectionRange(range, scope)
                guard intersection.length > 0 else { continue }
                storage.addAttributes(attributes, range: intersection)
            }
            storage.endEditing()
            undo?.enableUndoRegistration()

            textView.typingAttributes = Self.baseAttributes(bodySize: bodySize)
        }

        private static func baseAttributes(bodySize: CGFloat) -> [NSAttributedString.Key: Any] {
            [
                .font: MarkdownTheme.body(size: bodySize),
                .foregroundColor: MarkdownTheme.bodyColor,
                .paragraphStyle: MarkdownRenderer.paragraphStyle(for: .paragraph, indent: 0, bodySize: bodySize)
            ]
        }

        /// The blank-line-delimited block(s) around an edit, widened by one
        /// block on each side so a merge with a neighbour repaints too.
        static func blockRange(around dirty: NSRange, in string: NSString) -> NSRange? {
            guard string.length > 0 else { return nil }
            let location = min(dirty.location, string.length)
            let end = min(NSMaxRange(dirty), string.length)
            let separator = "\n\n"

            let before = string.range(of: separator, options: .backwards,
                                      range: NSRange(location: 0, length: location))
            var start = before.location == NSNotFound ? 0 : NSMaxRange(before)
            if start > 0 {
                let previous = string.range(of: separator, options: .backwards,
                                            range: NSRange(location: 0, length: max(0, start - separator.count)))
                start = previous.location == NSNotFound ? 0 : NSMaxRange(previous)
            }

            var finish = string.length
            let after = string.range(of: separator, options: [],
                                     range: NSRange(location: end, length: string.length - end))
            if after.location != NSNotFound {
                finish = NSMaxRange(after)
                let next = string.range(of: separator, options: [],
                                        range: NSRange(location: finish, length: string.length - finish))
                finish = next.location == NSNotFound ? string.length : NSMaxRange(next)
            }

            guard finish > start else { return nil }
            return NSRange(location: start, length: finish - start)
        }

        /// Exactly the blank-line-delimited block a caret belongs to, without
        /// the neighbouring-block widening `blockRange` applies. This is what
        /// live preview keys on: a caret move only counts as a block change if
        /// it leaves this range.
        static func blockSpan(_ range: NSRange?, in string: NSString) -> NSRange? {
            guard let range, string.length > 0 else { return nil }
            let location = min(range.location, string.length)
            let end = min(NSMaxRange(range), string.length)
            let separator = "\n\n"

            let before = string.range(of: separator, options: .backwards,
                                      range: NSRange(location: 0, length: location))
            let start = before.location == NSNotFound ? 0 : NSMaxRange(before)

            let after = string.range(of: separator, options: [],
                                     range: NSRange(location: end, length: string.length - end))
            let finish = after.location == NSNotFound ? string.length : after.location

            guard finish >= start else { return nil }
            return NSRange(location: start, length: finish - start)
        }
    }
}

/// Read-only rendered view of the same markdown.
struct MarkdownPreview: NSViewRepresentable {
    let text: String
    var bodySize: CGFloat = MarkdownTheme.bodySize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 22)
        textView.textContainer?.lineFragmentPadding = 2
        textView.linkTextAttributes = [
            .foregroundColor: MarkdownTheme.accentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard scrollView.documentView is NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.scrollView = scrollView
        // Typing fires this on every keystroke; skip the work when nothing changed.
        guard coordinator.renderedText != text || coordinator.renderedSize != bodySize else { return }

        // Rendering the whole document is the expensive part, so a burst of
        // keystrokes collapses into one render. The first paint is immediate so
        // switching notes never shows an empty pane.
        coordinator.pendingText = text
        coordinator.pendingSize = bodySize
        if coordinator.renderedText == nil {
            coordinator.renderNow()
        } else {
            coordinator.scheduleRender()
        }
    }

    final class Coordinator {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var renderedText: String?
        var renderedSize: CGFloat?
        var pendingText: String?
        var pendingSize: CGFloat?
        private var renderTask: Task<Void, Never>?

        func scheduleRender() {
            renderTask?.cancel()
            renderTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 90_000_000)
                guard !Task.isCancelled else { return }
                self?.renderNow()
            }
        }

        @MainActor
        func renderNow() {
            renderTask?.cancel()
            renderTask = nil
            guard let textView, let scrollView, let text = pendingText, let size = pendingSize else { return }
            pendingText = nil
            renderedText = text
            renderedSize = size

            // Keep the reader's place while the document is re-rendered. A raw
            // y-offset drifts as the text above it grows, so preserve the
            // fraction of the scrollable height instead.
            let visible = scrollView.contentView.bounds
            let oldMaxY = max(0, textView.frame.height - visible.height)
            let progress = oldMaxY > 0 ? visible.origin.y / oldMaxY : 0

            let document = MarkdownParseCache.shared.document(for: text)
            textView.textStorage?.setAttributedString(MarkdownRenderer.rendered(document, bodySize: size))
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)

            let newMaxY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
            let target = NSPoint(x: 0, y: min(newMaxY, max(0, progress * newMaxY)))
            scrollView.contentView.scroll(to: target)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
