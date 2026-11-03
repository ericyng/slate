import Foundation

/// A styled region of inline markdown, expressed in source coordinates.
struct InlineSpan {
    enum Kind: Equatable {
        case bold
        case italic
        case boldItalic
        case strike
        case code
        case link(String)
        case wikilink(String)
        case tag(String)
        /// Markdown punctuation that is dimmed in the editor and hidden in read mode.
        case syntax
    }

    var range: NSRange
    var kind: Kind
}

enum BlockKind: Hashable {
    case heading(Int)
    case paragraph
    case bullet
    case numbered
    case task(done: Bool)
    case quote
    case code(String?)
    case rule
    case blank
    case table
}

struct MarkdownBlock {
    var kind: BlockKind
    /// Whole block including trailing newline.
    var range: NSRange
    /// Text content, excluding the block marker (`# `, `- `, `> ` …).
    var contentRange: NSRange
    /// The block marker itself, if any.
    var markerRange: NSRange?
    var indent: Int
    var inlines: [InlineSpan]
}

struct MarkdownDocument {
    var text: NSString
    var blocks: [MarkdownBlock]
    /// Number of code-fence delimiter lines. Everything after a fence parses
    /// differently, so a change in this count invalidates a scoped restyle.
    var fenceCount: Int = 0

    var title: String {
        for block in blocks {
            if case .heading = block.kind {
                let raw = text.substring(with: block.contentRange)
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        for block in blocks {
            switch block.kind {
            case .blank, .rule, .code:
                continue
            default:
                let raw = text.substring(with: block.contentRange)
                let stripped = MarkdownDocument.plainText(raw)
                if !stripped.isEmpty { return String(stripped.prefix(120)) }
            }
        }
        return ""
    }

    static func plainText(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)

        // Leading block markers.
        if s.hasPrefix("#") {
            let hashes = s.prefix { $0 == "#" }.count
            if hashes <= 6, s.count > hashes,
               s[s.index(s.startIndex, offsetBy: hashes)] == " " {
                s = String(s.dropFirst(hashes + 1))
            }
        }
        for prefix in ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "+ [ ] ", "> ", "- ", "* ", "+ "] {
            if s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                break
            }
        }
        if let r = s.range(of: Self.numberedPrefix, options: .regularExpression) {
            s.removeSubrange(r)
        }

        // Inline markers.
        s = Self.replacing(Self.imagePattern, in: s, with: "$1")
        s = Self.replacing(Self.linkPattern, in: s, with: "$1")
        s = Self.replacing(Self.delimiterPattern, in: s, with: "")
        s = Self.replacing(Self.emphasisPattern, in: s, with: "")
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Cached regular expressions

    /// `plainText` runs once per note at scan time and again on every title
    /// derivation, so its patterns are compiled once instead of per call.
    private static let numberedPrefix = "^\\d{1,3}[.)]\\s+"
    private static let imagePattern = "!\\[([^\\]]*)\\]\\([^)]*\\)"
    private static let linkPattern = "\\[([^\\]]*)\\]\\([^)]*\\)"
    private static let delimiterPattern = "\\*\\*|__|~~|`"
    private static let emphasisPattern = "(?<![A-Za-z0-9])[*_](?=\\S)|(?<=\\S)[*_]"

    private static func replacing(_ pattern: String, in string: String, with template: String) -> String {
        guard let regex = RegexCache.shared.regex(pattern) else { return string }
        let range = NSRange(location: 0, length: (string as NSString).length)
        return regex.stringByReplacingMatches(in: string, range: range, withTemplate: template)
    }
}

/// Small thread-safe cache of compiled patterns.
final class RegexCache {
    static let shared = RegexCache()
    private let lock = NSLock()
    private var cache: [String: NSRegularExpression] = [:]

    func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[pattern] { return hit }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        cache[pattern] = regex
        return regex
    }
}

enum MarkdownParser {

    static func parse(_ string: String) -> MarkdownDocument {
        let ns = string as NSString
        let length = ns.length
        var blocks: [MarkdownBlock] = []
        blocks.reserveCapacity(length / 40)

        var inCode = false
        var codeLanguage: String?
        var codeContentStart = 0
        var codeBlockStart = 0
        var fenceCount = 0

        func flushCode(contentEnd: Int) {
            let range = NSRange(location: codeBlockStart, length: max(0, contentEnd - codeBlockStart))
            blocks.append(MarkdownBlock(
                kind: .code(codeLanguage),
                range: range,
                contentRange: NSRange(location: codeContentStart, length: max(0, contentEnd - codeContentStart)),
                markerRange: NSRange(location: codeBlockStart, length: max(0, codeContentStart - codeBlockStart)),
                indent: 0,
                inlines: []
            ))
        }

        var lineStart = 0
        while lineStart < length {
            // Line bounds, scanned with characters instead of lineRange +
            // substring: this loop runs once per line on every keystroke.
            var contentEnd = lineStart
            while contentEnd < length, char(ns, contentEnd) != 0x0A { contentEnd += 1 }
            let hasNewline = contentEnd < length
            let lineEnd = hasNewline ? contentEnd + 1 : contentEnd
            let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)

            // Indent.
            var first = lineStart
            while first < contentEnd, char(ns, first) == 0x20 || char(ns, first) == 0x09 { first += 1 }
            let indent = first - lineStart
            let isEmpty = first == contentEnd

            if inCode {
                if isFenceLine(ns, from: first, to: contentEnd) {
                    flushCode(contentEnd: lineStart)
                    inCode = false
                    codeLanguage = nil
                    fenceCount += 1
                }
                lineStart = lineEnd
                continue
            }

            if isFenceLine(ns, from: first, to: contentEnd) {
                inCode = true
                fenceCount += 1
                codeBlockStart = lineStart
                let langStart = min(fenceLength(ns, from: first, to: contentEnd) + first, contentEnd)
                var langEnd = contentEnd
                while langEnd > langStart, char(ns, langEnd - 1) == 0x20 || char(ns, langEnd - 1) == 0x09 { langEnd -= 1 }
                let lang = langEnd > langStart ? ns.substring(with: NSRange(location: langStart, length: langEnd - langStart)) : ""
                codeLanguage = lang.isEmpty ? nil : lang
                codeContentStart = lineEnd
                lineStart = lineEnd
                continue
            }

            if isEmpty {
                blocks.append(MarkdownBlock(kind: .blank, range: lineRange,
                                            contentRange: NSRange(location: lineStart, length: 0),
                                            markerRange: nil, indent: 0, inlines: []))
                lineStart = lineEnd
                continue
            }

            let contentRange = NSRange(location: lineStart, length: contentEnd - lineStart)
            let head = char(ns, first)

            // Table row.
            if head == 0x7C { // |
                blocks.append(MarkdownBlock(kind: .table, range: lineRange,
                                            contentRange: contentRange,
                                            markerRange: nil, indent: 0, inlines: []))
                lineStart = lineEnd
                continue
            }

            // Horizontal rule.
            if isRule(ns, from: first, to: contentEnd) {
                blocks.append(MarkdownBlock(kind: .rule, range: lineRange,
                                            contentRange: contentRange,
                                            markerRange: nil, indent: 0, inlines: []))
                lineStart = lineEnd
                continue
            }

            // ATX heading.
            if head == 0x23, let heading = headingMatch(ns, from: first, to: contentEnd) {
                let contentStart = lineStart + heading.markerLength
                let headingContent = NSRange(location: contentStart, length: max(0, contentEnd - contentStart))
                blocks.append(MarkdownBlock(
                    kind: .heading(heading.level),
                    range: lineRange,
                    contentRange: headingContent,
                    markerRange: NSRange(location: lineStart, length: heading.markerLength),
                    indent: 0,
                    inlines: inlineSpans(in: ns, range: headingContent)
                ))
                lineStart = lineEnd
                continue
            }

            // Bullet, task and numbered items share one unordered scan.
            if let bulletContent = unorderedMatch(ns, from: first, to: contentEnd) {
                if let task = taskMatch(ns, after: bulletContent, to: contentEnd) {
                    let taskContent = NSRange(location: task.contentStart, length: max(0, contentEnd - task.contentStart))
                    blocks.append(MarkdownBlock(
                        kind: .task(done: task.done),
                        range: lineRange,
                        contentRange: taskContent,
                        markerRange: NSRange(location: first, length: task.contentStart - first),
                        indent: indent,
                        inlines: inlineSpans(in: ns, range: taskContent)
                    ))
                    lineStart = lineEnd
                    continue
                }
                let itemContent = NSRange(location: bulletContent, length: max(0, contentEnd - bulletContent))
                blocks.append(MarkdownBlock(
                    kind: .bullet,
                    range: lineRange,
                    contentRange: itemContent,
                    markerRange: NSRange(location: first, length: bulletContent - first),
                    indent: indent,
                    inlines: inlineSpans(in: ns, range: itemContent)
                ))
                lineStart = lineEnd
                continue
            }

            if head >= 0x30, head <= 0x39, let numberedContent = numberedMatch(ns, from: first, to: contentEnd) {
                let itemContent = NSRange(location: numberedContent, length: max(0, contentEnd - numberedContent))
                blocks.append(MarkdownBlock(
                    kind: .numbered,
                    range: lineRange,
                    contentRange: itemContent,
                    markerRange: NSRange(location: first, length: numberedContent - first),
                    indent: indent,
                    inlines: inlineSpans(in: ns, range: itemContent)
                ))
                lineStart = lineEnd
                continue
            }

            // Quote.
            if head == 0x3E { // >
                var marker = first + 1
                if marker < contentEnd, char(ns, marker) == 0x20 { marker += 1 }
                let markerLength = marker - lineStart
                let quoteContent = NSRange(location: marker, length: max(0, contentEnd - marker))
                blocks.append(MarkdownBlock(
                    kind: .quote,
                    range: lineRange,
                    contentRange: quoteContent,
                    markerRange: NSRange(location: lineStart, length: markerLength),
                    indent: indent,
                    inlines: inlineSpans(in: ns, range: quoteContent)
                ))
                lineStart = lineEnd
                continue
            }

            // Paragraph.
            blocks.append(MarkdownBlock(
                kind: .paragraph,
                range: lineRange,
                contentRange: contentRange,
                markerRange: nil,
                indent: indent,
                inlines: inlineSpans(in: ns, range: contentRange)
            ))
            lineStart = lineEnd
        }

        if inCode {
            flushCode(contentEnd: length)
        }

        return MarkdownDocument(text: ns, blocks: blocks, fenceCount: fenceCount)
    }

    // MARK: - Line helpers

    /// `-`, `*` or `_` at least three times, with nothing else but spaces.
    private static func isRule(_ ns: NSString, from: Int, to: Int) -> Bool {
        guard to - from >= 3 else { return false }
        let c = char(ns, from)
        guard c == 0x2D || c == 0x2A || c == 0x5F else { return false }
        var count = 0
        var i = from
        while i < to {
            let k = char(ns, i)
            if k == c { count += 1 } else if k != 0x20 && k != 0x09 { return false }
            i += 1
        }
        return count >= 3
    }

    private static func fenceLength(_ ns: NSString, from: Int, to: Int) -> Int {
        let c = char(ns, from)
        guard c == 0x60 || c == 0x7E else { return 0 }
        var i = from
        while i < to, char(ns, i) == c { i += 1 }
        return i - from
    }

    private static func isFenceLine(_ ns: NSString, from: Int, to: Int) -> Bool {
        fenceLength(ns, from: from, to: to) >= 3
    }

    private static func headingMatch(_ ns: NSString, from: Int, to: Int) -> (level: Int, markerLength: Int)? {
        var i = from
        while i < to, char(ns, i) == 0x23 { i += 1 }
        let hashes = i - from
        guard hashes >= 1, hashes <= 6 else { return nil }
        if i >= to { return (hashes, hashes) }
        guard char(ns, i) == 0x20 else { return nil }
        return (hashes, hashes + 1)
    }

    /// `- item`, `* item`, `+ item`. Returns the absolute index where the
    /// content starts (after the marker and its trailing spaces).
    private static func unorderedMatch(_ ns: NSString, from: Int, to: Int) -> Int? {
        let c = char(ns, from)
        guard c == 0x2D || c == 0x2A || c == 0x2B else { return nil }
        var i = from + 1
        guard i < to, isWhitespace(char(ns, i)) else { return nil }
        while i < to, isWhitespace(char(ns, i)) { i += 1 }
        return i
    }

    /// `- [ ] text` / `- [x] text`. Given the absolute content index just past
    /// the bullet, returns where the task text starts and whether it is done.
    private static func taskMatch(_ ns: NSString, after: Int, to: Int) -> (contentStart: Int, done: Bool)? {
        guard after + 2 < to else { return nil }
        guard char(ns, after) == 0x5B else { return nil }          // [
        let state = char(ns, after + 1)
        let done = state == 0x78 || state == 0x58                 // x or X
        guard state == 0x20 || done else { return nil }
        guard char(ns, after + 2) == 0x5D else { return nil }      // ]
        var i = after + 3
        guard i < to, isWhitespace(char(ns, i)) else { return nil }
        while i < to, isWhitespace(char(ns, i)) { i += 1 }
        return (i, done)
    }

    /// `1. text` or `1) text`, up to three digits. Returns the absolute index
    /// where the content starts.
    private static func numberedMatch(_ ns: NSString, from: Int, to: Int) -> Int? {
        var i = from
        var digits = 0
        while i < to, char(ns, i) >= 0x30, char(ns, i) <= 0x39 {
            i += 1
            digits += 1
            if digits > 3 { return nil }
        }
        guard digits >= 1, i < to else { return nil }
        let sep = char(ns, i)
        guard sep == 0x2E || sep == 0x29 else { return nil }       // . or )
        i += 1
        guard i < to, isWhitespace(char(ns, i)) else { return nil }
        while i < to, isWhitespace(char(ns, i)) { i += 1 }
        return i
    }

    // MARK: - Inline scanning

    static func inlineSpans(in ns: NSString, range: NSRange) -> [InlineSpan] {
        var spans: [InlineSpan] = []
        scanInline(ns, range: range, into: &spans)
        return spans
    }

    private static func char(_ ns: NSString, _ i: Int) -> unichar {
        guard i >= 0 && i < ns.length else { return 0 }
        return ns.character(at: i)
    }

    private static func scanInline(_ ns: NSString, range: NSRange, into spans: inout [InlineSpan]) {
        var i = range.location
        let end = NSMaxRange(range)
        while i < end {
            let c = char(ns, i)

            // Escapes
            if c == 0x5C { // backslash
                i += 2
                continue
            }

            // Inline code
            if c == 0x60 { // `
                if let close = find(ns, "`", from: i + 1, to: end) {
                    spans.append(InlineSpan(range: NSRange(location: i, length: 1), kind: .syntax))
                    if close > i + 1 {
                        spans.append(InlineSpan(range: NSRange(location: i + 1, length: close - i - 1), kind: .code))
                    }
                    spans.append(InlineSpan(range: NSRange(location: close, length: 1), kind: .syntax))
                    i = close + 1
                    continue
                }
            }

            // Wikilinks [[target]]
            if c == 0x5B, char(ns, i + 1) == 0x5B {
                var j = i + 2
                while j + 1 < end {
                    if char(ns, j) == 0x5D && char(ns, j + 1) == 0x5D { break }
                    j += 1
                }
                if j + 1 < end, char(ns, j) == 0x5D, char(ns, j + 1) == 0x5D {
                    let target = ns.substring(with: NSRange(location: i + 2, length: j - i - 2)).trimmingCharacters(in: .whitespaces)
                    spans.append(InlineSpan(range: NSRange(location: i, length: 2), kind: .syntax))
                    if j > i + 2 {
                        spans.append(InlineSpan(range: NSRange(location: i + 2, length: j - i - 2), kind: .wikilink(target)))
                    }
                    spans.append(InlineSpan(range: NSRange(location: j, length: 2), kind: .syntax))
                    i = j + 2
                    continue
                }
            }

            // Links [text](url)
            if c == 0x5B { // [
                if let link = parseLink(ns, at: i, end: end) {
                    spans.append(InlineSpan(range: NSRange(location: i, length: 1), kind: .syntax))
                    if link.textRange.length > 0 {
                        spans.append(InlineSpan(range: link.textRange, kind: .link(link.url)))
                        var nested: [InlineSpan] = []
                        scanInline(ns, range: link.textRange, into: &nested)
                        spans.append(contentsOf: nested)
                    }
                    spans.append(InlineSpan(range: NSRange(location: link.textRange.location + link.textRange.length, length: 1), kind: .syntax))
                    spans.append(InlineSpan(range: NSRange(location: link.urlStart, length: link.urlEnd - link.urlStart), kind: .syntax))
                    i = link.urlEnd
                    continue
                }
            }

            // Bold / italic
            if c == 0x2A || c == 0x5F { // * or _
                let dbl = char(ns, i + 1) == c
                if dbl {
                    if let close = findSequence(ns, c, count: 2, from: i + 2, to: end) {
                        let inner = NSRange(location: i + 2, length: close - i - 2)
                        spans.append(InlineSpan(range: NSRange(location: i, length: 2), kind: .syntax))
                        if inner.length > 0 {
                            spans.append(InlineSpan(range: inner, kind: .bold))
                            var nested: [InlineSpan] = []
                            scanInline(ns, range: inner, into: &nested)
                            spans.append(contentsOf: nested)
                        }
                        spans.append(InlineSpan(range: NSRange(location: close, length: 2), kind: .syntax))
                        i = close + 2
                        continue
                    }
                } else {
                    let nextIsSpace = isWhitespace(char(ns, i + 1))
                    if !nextIsSpace, let close = findSingle(ns, c, from: i + 1, to: end), close > i + 1 {
                        let prevIsSpace = isWhitespace(char(ns, close - 1))
                        if !prevIsSpace {
                            let inner = NSRange(location: i + 1, length: close - i - 1)
                            spans.append(InlineSpan(range: NSRange(location: i, length: 1), kind: .syntax))
                            if inner.length > 0 {
                                spans.append(InlineSpan(range: inner, kind: .italic))
                                var nested: [InlineSpan] = []
                                scanInline(ns, range: inner, into: &nested)
                                spans.append(contentsOf: nested)
                            }
                            spans.append(InlineSpan(range: NSRange(location: close, length: 1), kind: .syntax))
                            i = close + 1
                            continue
                        }
                    }
                }
            }

            // Tags #word (not headings)
            if c == 0x23 { // #
                let prev = i == range.location ? 0x20 : char(ns, i - 1)
                if prev == 0x20 || prev == 0x09 || prev == 0x0A || prev == 0x0D || i == range.location {
                    var j = i + 1
                    while j < end {
                        let cc = char(ns, j)
                        if (cc >= 0x30 && cc <= 0x39) || (cc >= 0x41 && cc <= 0x5A) || (cc >= 0x61 && cc <= 0x7A) || cc == 0x5F || cc == 0x2D {
                            j += 1
                        } else { break }
                    }
                    if j > i + 1 {
                        let name = ns.substring(with: NSRange(location: i + 1, length: j - i - 1))
                        spans.append(InlineSpan(range: NSRange(location: i, length: j - i), kind: .tag(name)))
                        i = j
                        continue
                    }
                }
            }

            // Strikethrough
            if c == 0x7E, char(ns, i + 1) == 0x7E { // ~
                if let close = findSequence(ns, 0x7E, count: 2, from: i + 2, to: end) {
                    let inner = NSRange(location: i + 2, length: close - i - 2)
                    spans.append(InlineSpan(range: NSRange(location: i, length: 2), kind: .syntax))
                    if inner.length > 0 {
                        spans.append(InlineSpan(range: inner, kind: .strike))
                        var nested: [InlineSpan] = []
                        scanInline(ns, range: inner, into: &nested)
                        spans.append(contentsOf: nested)
                    }
                    spans.append(InlineSpan(range: NSRange(location: close, length: 2), kind: .syntax))
                    i = close + 2
                    continue
                }
            }

            i += 1
        }
    }

    private static func isWhitespace(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
    }

    private static func find(_ ns: NSString, _ s: String, from: Int, to: Int) -> Int? {
        let target = s.utf16.first!
        var i = from
        while i < to {
            if char(ns, i) == target { return i }
            i += 1
        }
        return nil
    }

    private static func findSequence(_ ns: NSString, _ target: unichar, count: Int, from: Int, to: Int) -> Int? {
        var i = from
        while i + count <= to {
            var ok = true
            for k in 0..<count where char(ns, i + k) != target { ok = false; break }
            if ok { return i }
            i += 1
        }
        return nil
    }

    private static func findSingle(_ ns: NSString, _ target: unichar, from: Int, to: Int) -> Int? {
        var i = from
        while i < to {
            if char(ns, i) == target {
                if char(ns, i + 1) == target { i += 2; continue }
                return i
            }
            i += 1
        }
        return nil
    }

    private static func parseLink(_ ns: NSString, at start: Int, end: Int) -> (textRange: NSRange, urlStart: Int, urlEnd: Int, url: String)? {
        var j = start + 1
        var depth = 1
        while j < end {
            let c = char(ns, j)
            if c == 0x5B { depth += 1 }
            if c == 0x5D {
                depth -= 1
                if depth == 0 { break }
            }
            j += 1
        }
        guard j < end, char(ns, j) == 0x5D, j + 1 < end, char(ns, j + 1) == 0x28 else { return nil }
        var k = j + 2
        while k < end, char(ns, k) != 0x29 { k += 1 }
        guard k < end else { return nil }
        let url = ns.substring(with: NSRange(location: j + 2, length: k - j - 2))
        return (NSRange(location: start + 1, length: j - start - 1), j + 1, k + 1, url)
    }
}
