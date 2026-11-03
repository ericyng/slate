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

enum BlockKind: Equatable {
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
        if let r = s.range(of: "^\\d{1,3}[.)]\\s+", options: .regularExpression) {
            s.removeSubrange(r)
        }

        // Inline markers.
        s = s.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*\\*|__|~~|`", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<![A-Za-z0-9])[*_](?=\\S)|(?<=\\S)[*_]", with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }
}

enum MarkdownParser {

    static func parse(_ string: String) -> MarkdownDocument {
        let ns = string as NSString
        var blocks: [MarkdownBlock] = []
        var index = 0
        var inCode = false
        var codeLanguage: String?
        var codeContentStart = 0
        var codeBlockStart = 0

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

        while index < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let rawLine = ns.substring(with: lineRange)
            let hasNewline = rawLine.hasSuffix("\n")
            let line = hasNewline ? String(rawLine.dropLast()) : rawLine
            let contentEnd = lineRange.location + (hasNewline ? lineRange.length - 1 : lineRange.length)

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inCode {
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    flushCode(contentEnd: lineRange.location)
                    inCode = false
                    codeLanguage = nil
                    index = NSMaxRange(lineRange)
                    continue
                }
                index = NSMaxRange(lineRange)
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inCode = true
                codeBlockStart = lineRange.location
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                codeLanguage = lang.isEmpty ? nil : lang
                codeContentStart = NSMaxRange(lineRange)
                index = NSMaxRange(lineRange)
                continue
            }

            let indent = line.prefix { $0 == " " }.count + line.prefix { $0 == "\t" }.count * 2

            if trimmed.hasPrefix("|") {
                blocks.append(MarkdownBlock(kind: .table, range: lineRange,
                                            contentRange: NSRange(location: lineRange.location, length: contentEnd - lineRange.location),
                                            markerRange: nil, indent: 0, inlines: []))
                index = NSMaxRange(lineRange)
                continue
            }

            if trimmed.isEmpty {
                blocks.append(MarkdownBlock(kind: .blank, range: lineRange,
                                            contentRange: NSRange(location: lineRange.location, length: 0),
                                            markerRange: nil, indent: 0, inlines: []))
                index = NSMaxRange(lineRange)
                continue
            }

            // Horizontal rule
            if isRule(trimmed) {
                blocks.append(MarkdownBlock(kind: .rule, range: lineRange,
                                            contentRange: NSRange(location: lineRange.location, length: contentEnd - lineRange.location),
                                            markerRange: nil, indent: 0, inlines: []))
                index = NSMaxRange(lineRange)
                continue
            }

            // ATX heading
            if let heading = headingMatch(line) {
                let markerLen = heading.markerLength
                let contentStart = lineRange.location + markerLen
                let contentRange = NSRange(location: contentStart, length: max(0, contentEnd - contentStart))
                blocks.append(MarkdownBlock(
                    kind: .heading(heading.level),
                    range: lineRange,
                    contentRange: contentRange,
                    markerRange: NSRange(location: lineRange.location, length: markerLen),
                    indent: 0,
                    inlines: inlineSpans(in: ns, range: contentRange)
                ))
                index = NSMaxRange(lineRange)
                continue
            }

            // Task list item
            if let task = taskMatch(line) {
                let contentRange = NSRange(location: lineRange.location + task.contentOffset,
                                           length: max(0, contentEnd - lineRange.location - task.contentOffset))
                blocks.append(MarkdownBlock(
                    kind: .task(done: task.done),
                    range: lineRange,
                    contentRange: contentRange,
                    markerRange: NSRange(location: lineRange.location + task.markerOffset, length: task.contentOffset - task.markerOffset),
                    indent: indent,
                    inlines: inlineSpans(in: ns, range: contentRange)
                ))
                index = NSMaxRange(lineRange)
                continue
            }

            // Bullet
            if let bullet = bulletMatch(line) {
                let contentRange = NSRange(location: lineRange.location + bullet.contentOffset,
                                           length: max(0, contentEnd - lineRange.location - bullet.contentOffset))
                blocks.append(MarkdownBlock(
                    kind: .bullet,
                    range: lineRange,
                    contentRange: contentRange,
                    markerRange: NSRange(location: lineRange.location + bullet.markerOffset, length: bullet.contentOffset - bullet.markerOffset),
                    indent: indent,
                    inlines: inlineSpans(in: ns, range: contentRange)
                ))
                index = NSMaxRange(lineRange)
                continue
            }

            // Numbered
            if let numbered = numberedMatch(line) {
                let contentRange = NSRange(location: lineRange.location + numbered.contentOffset,
                                           length: max(0, contentEnd - lineRange.location - numbered.contentOffset))
                blocks.append(MarkdownBlock(
                    kind: .numbered,
                    range: lineRange,
                    contentRange: contentRange,
                    markerRange: NSRange(location: lineRange.location + numbered.markerOffset, length: numbered.contentOffset - numbered.markerOffset),
                    indent: indent,
                    inlines: inlineSpans(in: ns, range: contentRange)
                ))
                index = NSMaxRange(lineRange)
                continue
            }

            // Quote
            if let quoteLength = quoteMatch(line) {
                let contentRange = NSRange(location: lineRange.location + quoteLength,
                                           length: max(0, contentEnd - lineRange.location - quoteLength))
                blocks.append(MarkdownBlock(
                    kind: .quote,
                    range: lineRange,
                    contentRange: contentRange,
                    markerRange: NSRange(location: lineRange.location, length: quoteLength),
                    indent: indent,
                    inlines: inlineSpans(in: ns, range: contentRange)
                ))
                index = NSMaxRange(lineRange)
                continue
            }

            // Paragraph
            let contentRange = NSRange(location: lineRange.location, length: contentEnd - lineRange.location)
            blocks.append(MarkdownBlock(
                kind: .paragraph,
                range: lineRange,
                contentRange: contentRange,
                markerRange: nil,
                indent: indent,
                inlines: inlineSpans(in: ns, range: contentRange)
            ))
            index = NSMaxRange(lineRange)
        }

        if inCode {
            flushCode(contentEnd: ns.length)
        }

        return MarkdownDocument(text: ns, blocks: blocks)
    }

    // MARK: - Line helpers

    private static func isRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let dashes = trimmed.allSatisfy { $0 == "-" || $0 == " " }
        let stars = trimmed.allSatisfy { $0 == "*" || $0 == " " }
        let unders = trimmed.allSatisfy { $0 == "_" || $0 == " " }
        return (dashes && trimmed.contains("-")) || (stars && trimmed.contains("*")) || (unders && trimmed.contains("_"))
    }

    private static func headingMatch(_ line: String) -> (level: Int, markerLength: Int)? {
        let ns = line as NSString
        var i = 0
        while i < ns.length, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        var hashes = 0
        while i + hashes < ns.length, ns.character(at: i + hashes) == 0x23 { hashes += 1 }
        guard hashes >= 1, hashes <= 6 else { return nil }
        let after = i + hashes
        if after >= ns.length { return (hashes, after) }
        guard ns.character(at: after) == 0x20 else { return nil }
        return (hashes, after + 1)
    }

    private static func quoteMatch(_ line: String) -> Int? {
        let ns = line as NSString
        var i = 0
        while i < ns.length, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        guard i < ns.length, ns.character(at: i) == 0x3E else { return nil }
        var marker = i + 1
        if marker < ns.length, ns.character(at: marker) == 0x20 { marker += 1 }
        return marker
    }

    private static func taskMatch(_ line: String) -> (markerOffset: Int, contentOffset: Int, done: Bool)? {
        let ns = line as NSString
        guard let regex = try? NSRegularExpression(pattern: "^(\\s*)([-*+])\\s+\\[([ xX])\\]\\s+") else { return nil }
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let boxRange = m.range(at: 3)
        let done = ns.substring(with: boxRange).lowercased() == "x"
        return (m.range(at: 1).length, m.range.length, done)
    }

    private static func bulletMatch(_ line: String) -> (markerOffset: Int, contentOffset: Int)? {
        let ns = line as NSString
        guard let regex = try? NSRegularExpression(pattern: "^(\\s*)([-*+])\\s+") else { return nil }
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (m.range(at: 1).length, m.range.length)
    }

    private static func numberedMatch(_ line: String) -> (markerOffset: Int, contentOffset: Int)? {
        let ns = line as NSString
        guard let regex = try? NSRegularExpression(pattern: "^(\\s*)(\\d{1,3}[.)])\\s+") else { return nil }
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (m.range(at: 1).length, m.range.length)
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
