import AppKit

/// Bridges menu commands and toolbar buttons to whichever editor is on screen.
@MainActor
final class EditorCommandCenter {
    static let shared = EditorCommandCenter()
    weak var textView: NSTextView?

    func focus() {
        if let textView, textView.window?.isKeyWindow == true {
            textView.window?.makeFirstResponder(textView)
            return
        }
        if let window = NSApp.keyWindow, let editor = Self.editorTextView(in: window) {
            window.makeFirstResponder(editor)
        }
    }

    /// Shows the standard find bar over the editor (⌘F).
    func showFind() {
        guard let tv = target else { return }
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        tv.performTextFinderAction(item)
    }

    /// ⌘G / ⇧⌘G inside the editor.
    func findAgain(forward: Bool) {
        guard let tv = target else { return }
        let action: NSTextFinder.Action = forward ? .nextMatch : .previousMatch
        let item = NSMenuItem()
        item.tag = action.rawValue
        tv.performTextFinderAction(item)
    }

    /// The markdown editor of the window in front.
    ///
    /// With several vault windows open, the last editor that ran `updateNSView`
    /// is not necessarily the visible one, so the key window always wins.
    private var target: NSTextView? {
        if let responder = NSApp.keyWindow?.firstResponder as? NSTextView,
           !responder.isFieldEditor,
           responder.isEditable {
            return responder
        }
        if let textView, textView.window?.isKeyWindow == true {
            textView.window?.makeFirstResponder(textView)
            return textView
        }
        if let window = NSApp.keyWindow, let editor = Self.editorTextView(in: window) {
            window.makeFirstResponder(editor)
            return editor
        }
        return nil
    }

    /// Depth-first search for the editable text view, skipping the field editor
    /// used by search fields.
    private static func editorTextView(in window: NSWindow) -> NSTextView? {
        func search(_ view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView,
               textView.isEditable,
               !textView.isFieldEditor {
                return textView
            }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        guard let content = window.contentView else { return nil }
        return search(content)
    }

    func wrap(_ marker: String) {
        guard let tv = target else { return }
        let range = tv.selectedRange()
        let ns = tv.string as NSString
        let length = min(marker.count, 3)

        if range.length > 0 {
            let selected = ns.substring(with: range)
            if selected.count >= marker.count * 2,
               selected.hasPrefix(marker), selected.hasSuffix(marker) {
                let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
                tv.insertText(inner, replacementRange: range)
                tv.setSelectedRange(NSRange(location: range.location, length: (inner as NSString).length))
                return
            }
            if range.location >= length, NSMaxRange(range) + length <= ns.length {
                let before = ns.substring(with: NSRange(location: range.location - length, length: length))
                let after = ns.substring(with: NSRange(location: NSMaxRange(range), length: length))
                if before == marker, after == marker {
                    tv.insertText(selected, replacementRange: NSRange(location: range.location - length,
                                                                     length: range.length + length * 2))
                    tv.setSelectedRange(NSRange(location: range.location - length, length: range.length))
                    return
                }
            }
            tv.insertText(marker + selected + marker, replacementRange: range)
            tv.setSelectedRange(NSRange(location: range.location + length, length: range.length))
        } else {
            tv.insertText(marker + marker, replacementRange: range)
            tv.setSelectedRange(NSRange(location: range.location + length, length: 0))
        }
    }

    func setHeading(_ level: Int) {
        guard let tv = target else { return }
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: tv.selectedRange())

        var existingLevel = 0
        var hashes = 0
        while hashes < ns.length - lineRange.location,
              hashes < 7,
              ns.character(at: lineRange.location + hashes) == 0x23 {
            hashes += 1
        }
        if hashes > 0, hashes < 7,
           lineRange.location + hashes < NSMaxRange(lineRange),
           ns.character(at: lineRange.location + hashes) == 0x20 {
            existingLevel = hashes
        }

        let currentLine = ns.substring(with: lineRange)
        let body = currentLine
            .replacingOccurrences(of: String(repeating: "#", count: max(existingLevel, 1)) + " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
        let prefix = level > 0 ? String(repeating: "#", count: level) + " " : ""
        tv.insertText(prefix + body + "\n", replacementRange: lineRange)
    }

    func toggleLinePrefix(_ prefix: String) {
        guard let tv = target else { return }
        let ns = tv.string as NSString
        let selection = tv.selectedRange()
        let lineRange = ns.lineRange(for: selection)

        var lines: [String] = []
        ns.substring(with: lineRange).enumerateLines { line, _ in lines.append(line) }
        if lines.isEmpty { lines = [""] }

        let allHavePrefix = lines.allSatisfy { $0.hasPrefix(prefix) || $0.isEmpty }
        let updated = lines.map { line -> String in
            if allHavePrefix {
                return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
            }
            return prefix + line
        }
        let replacement = updated.joined(separator: "\n")
        tv.insertText(replacement + "\n", replacementRange: lineRange)
        tv.setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length))
    }

    func applyNumberedList() {
        guard let tv = target else { return }
        let ns = tv.string as NSString
        let selection = tv.selectedRange()
        let lineRange = ns.lineRange(for: selection)
        var lines: [String] = []
        ns.substring(with: lineRange).enumerateLines { line, _ in lines.append(line) }
        if lines.isEmpty { lines = [""] }
        let updated = lines.enumerated().map { index, line -> String in
            let stripped = line.hasPrefix("1. ") ? String(line.dropFirst(3)) : line
            return "\(index + 1). " + stripped
        }
        let replacement = updated.joined(separator: "\n") + "\n"
        tv.insertText(replacement, replacementRange: lineRange)
        tv.setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length))
    }

    func insertCodeBlock() {
        guard let tv = target else { return }
        let range = tv.selectedRange()
        let ns = tv.string as NSString
        if range.length > 0 {
            let selected = ns.substring(with: range)
            tv.insertText("```\n" + selected + "\n```", replacementRange: range)
        } else {
            tv.insertText("```\n\n```", replacementRange: range)
            tv.setSelectedRange(NSRange(location: range.location + 4, length: 0))
        }
    }
}
