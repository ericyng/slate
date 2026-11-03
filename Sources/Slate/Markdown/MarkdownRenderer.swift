import AppKit

enum MarkdownTheme {
    static let bodySize: CGFloat = 15
    static let monoSize: CGFloat = 13

    static func headingScale(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 1.66
        case 2: return 1.33
        case 3: return 1.13
        default: return 1.0
        }
    }

    static func headingSize(_ level: Int, bodySize: CGFloat = MarkdownTheme.bodySize) -> CGFloat {
        (bodySize * headingScale(level)).rounded()
    }

    static func headingWeight(_ level: Int) -> NSFont.Weight {
        level <= 2 ? .bold : .semibold
    }

    static let bodyColor = NSColor.labelColor
    static let secondaryColor = NSColor.secondaryLabelColor
    static let tertiaryColor = NSColor.tertiaryLabelColor
    static let accentColor = NSColor.controlAccentColor
    static let codeBackground = NSColor.labelColor.withAlphaComponent(0.06)
    static let codeColor = NSColor.systemPink
    static let quoteColor = NSColor.secondaryLabelColor

    static func body(size: CGFloat = bodySize) -> NSFont {
        NSFont.systemFont(ofSize: size)
    }

    static func bold(size: CGFloat = bodySize) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .bold)
    }

    static func italic(size: CGFloat = bodySize) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func boldItalic(size: CGFloat = bodySize) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .bold)
        let descriptor = base.fontDescriptor.withSymbolicTraits([.italic])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func mono(size: CGFloat = monoSize) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// Turns a parsed markdown document into AppKit attributes: one pass that styles
/// the source text in place (live editor) and one that renders clean text (read mode).
///
/// `bodySize` is threaded through every entry point so the Appearance setting
/// scales headings, lists and code along with body text.
enum MarkdownRenderer {

    // MARK: - Live editor styling

    /// Attribute runs applied over the *source* text.
    ///
    /// In plain source mode (`focusRange == nil`) every marker is shown, dimmed.
    /// In live preview, pass the selection range: markers and inline delimiters
    /// are concealed on every block except the one holding the caret, which is
    /// shown raw so it stays editable.
    static func editorRuns(for doc: MarkdownDocument,
                           bodySize: CGFloat = MarkdownTheme.bodySize,
                           focusRange: NSRange? = nil) -> [(NSRange, [NSAttributedString.Key: Any])] {
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        let length = doc.text.length

        runs.append((NSRange(location: 0, length: length), [
            .font: MarkdownTheme.body(size: bodySize),
            .foregroundColor: MarkdownTheme.bodyColor,
            .paragraphStyle: paragraphStyle(for: .paragraph, indent: 0, bodySize: bodySize)
        ]))

        for block in doc.blocks {
            guard block.range.location != NSNotFound, NSMaxRange(block.range) <= length else { continue }
            let concealing = focusRange.map { focus in
                focus.location < block.range.location || focus.location > NSMaxRange(block.range)
            } ?? false

            let style = paragraphStyle(for: block.kind, indent: block.indent, bodySize: bodySize)
            var attrs: [NSAttributedString.Key: Any] = [.paragraphStyle: style]

            switch block.kind {
            case .heading(let level):
                attrs[.font] = NSFont.systemFont(ofSize: MarkdownTheme.headingSize(level, bodySize: bodySize),
                                                 weight: MarkdownTheme.headingWeight(level))
            case .code:
                attrs[.font] = MarkdownTheme.mono(size: bodySize * MarkdownTheme.monoSize / MarkdownTheme.bodySize)
                attrs[.backgroundColor] = MarkdownTheme.codeBackground
            case .table:
                attrs[.font] = MarkdownTheme.mono(size: bodySize * MarkdownTheme.monoSize / MarkdownTheme.bodySize)
                attrs[.backgroundColor] = MarkdownTheme.codeBackground
            case .quote:
                attrs[.foregroundColor] = MarkdownTheme.quoteColor
            case .rule:
                attrs[.foregroundColor] = MarkdownTheme.tertiaryColor
            case .blank:
                attrs[.font] = MarkdownTheme.body(size: bodySize)
            default:
                attrs[.font] = MarkdownTheme.body(size: bodySize)
            }

            clamp(block.range, length: length).map { runs.append(($0, attrs)) }

            // Block markers: dimmed in source, concealed once the caret leaves
            // the block in live preview. List and task markers only dim, since
            // the dash and checkboxes carry meaning.
            if let marker = clamp(block.markerRange ?? NSRange(location: 0, length: 0), length: length),
               marker.length > 0 {
                let attrs = (concealing && concealsMarker(block.kind)) ? concealedAttributes : syntaxAttributes
                runs.append((marker, attrs))
            }

            if case .code = block.kind { continue }

            let baseSize = fontSize(for: block.kind, bodySize: bodySize)
            for span in block.inlines {
                guard let range = clamp(span.range, length: length) else { continue }
                switch span.kind {
                case .syntax:
                    runs.append((range, concealing ? concealedAttributes : syntaxAttributes))
                case .bold:
                    runs.append((range, [.font: MarkdownTheme.bold(size: baseSize)]))
                case .italic:
                    runs.append((range, [.font: MarkdownTheme.italic(size: baseSize)]))
                case .boldItalic:
                    runs.append((range, [.font: MarkdownTheme.boldItalic(size: baseSize)]))
                case .strike:
                    runs.append((range, [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                         .strikethroughColor: MarkdownTheme.secondaryColor]))
                case .code:
                    runs.append((range, [.font: MarkdownTheme.mono(size: baseSize - 1.5),
                                         .backgroundColor: MarkdownTheme.codeBackground,
                                         .foregroundColor: MarkdownTheme.codeColor]))
                case .link:
                    runs.append((range, [.foregroundColor: MarkdownTheme.accentColor,
                                         .underlineStyle: NSUnderlineStyle.single.rawValue,
                                         .underlineColor: MarkdownTheme.accentColor.withAlphaComponent(0.4)]))
                case .wikilink:
                    runs.append((range, [.foregroundColor: MarkdownTheme.accentColor,
                                         .underlineStyle: NSUnderlineStyle.single.rawValue,
                                         .underlineColor: MarkdownTheme.accentColor.withAlphaComponent(0.4)]))
                case .tag:
                    runs.append((range, [.foregroundColor: MarkdownTheme.accentColor]))
                }
            }
        }
        return runs
    }

    private static let syntaxAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: MarkdownTheme.tertiaryColor
    ]

    /// A 0.1 pt clear font is effectively zero-width, so the marker keeps its
    /// place in the string (and in the caret's model of the document) without
    /// being drawn.
    private static let concealedAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 0.1),
        .foregroundColor: NSColor.clear,
        .backgroundColor: NSColor.clear
    ]

    /// List and task markers stay visible: they carry the list/checkbox
    /// semantics that a concealed dash would lose.
    private static func concealsMarker(_ kind: BlockKind) -> Bool {
        switch kind {
        case .heading, .quote: return true
        default: return false
        }
    }

    private static func fontSize(for kind: BlockKind, bodySize: CGFloat) -> CGFloat {
        if case .heading(let level) = kind { return MarkdownTheme.headingSize(level, bodySize: bodySize) }
        return bodySize
    }

    private static func clamp(_ range: NSRange, length: Int) -> NSRange? {
        guard range.location >= 0, range.location <= length else { return nil }
        let end = min(NSMaxRange(range), length)
        guard end >= range.location else { return nil }
        let r = NSRange(location: range.location, length: end - range.location)
        return r.length > 0 ? r : nil
    }

    // MARK: - Read mode

    static func rendered(_ doc: MarkdownDocument,
                         bodySize: CGFloat = MarkdownTheme.bodySize) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let monoSize = bodySize * MarkdownTheme.monoSize / MarkdownTheme.bodySize

        for block in doc.blocks {
            switch block.kind {
            case .blank:
                continue

            case .rule:
                out.append(NSAttributedString(string: "────────────\n", attributes: [
                    .font: MarkdownTheme.body(size: max(10, bodySize * 0.73)),
                    .foregroundColor: MarkdownTheme.tertiaryColor,
                    .paragraphStyle: paragraphStyle(for: .rule, indent: 0, bodySize: bodySize)
                ]))

            case .code:
                let code = doc.text.substring(with: block.contentRange)
                let trimmed = code.hasSuffix("\n") ? String(code.dropLast()) : code
                let paragraph = paragraphStyle(for: .code(nil), indent: 0, bodySize: bodySize)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: MarkdownTheme.mono(size: monoSize),
                    .foregroundColor: MarkdownTheme.bodyColor,
                    .backgroundColor: MarkdownTheme.codeBackground,
                    .paragraphStyle: paragraph
                ]
                out.append(NSAttributedString(string: trimmed + "\n", attributes: attrs))

            case .heading(let level):
                let base: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: MarkdownTheme.headingSize(level, bodySize: bodySize),
                                             weight: MarkdownTheme.headingWeight(level)),
                    .foregroundColor: MarkdownTheme.bodyColor,
                    .paragraphStyle: paragraphStyle(for: .heading(level), indent: 0, bodySize: bodySize)
                ]
                out.append(inline(doc: doc, block: block, base: base, bodySize: bodySize))
                out.append(NSAttributedString(string: "\n", attributes: base))

            case .bullet, .numbered, .task:
                var prefix = "•  "
                if case .numbered = block.kind {
                    prefix = doc.text.substring(with: block.markerRange ?? NSRange(location: 0, length: 0))
                }
                if case .task(let done) = block.kind {
                    prefix = done ? "☑  " : "☐  "
                }
                let base: [NSAttributedString.Key: Any] = [
                    .font: MarkdownTheme.body(size: bodySize),
                    .foregroundColor: MarkdownTheme.bodyColor,
                    .paragraphStyle: paragraphStyle(for: .bullet, indent: block.indent, bodySize: bodySize)
                ]
                out.append(NSAttributedString(string: prefix, attributes: [
                    .font: MarkdownTheme.body(size: bodySize),
                    .foregroundColor: block.kind == .task(done: true) || prefix == "☑  " ? MarkdownTheme.tertiaryColor : MarkdownTheme.secondaryColor,
                    .paragraphStyle: paragraphStyle(for: .bullet, indent: block.indent, bodySize: bodySize)
                ]))
                out.append(inline(doc: doc, block: block, base: base, bodySize: bodySize))
                out.append(NSAttributedString(string: "\n", attributes: base))

            case .quote:
                let base: [NSAttributedString.Key: Any] = [
                    .font: MarkdownTheme.body(size: bodySize),
                    .foregroundColor: MarkdownTheme.quoteColor,
                    .paragraphStyle: paragraphStyle(for: .quote, indent: block.indent, bodySize: bodySize)
                ]
                out.append(inline(doc: doc, block: block, base: base, bodySize: bodySize))
                out.append(NSAttributedString(string: "\n", attributes: base))

            case .table:
                let text = doc.text.substring(with: block.range)
                let trimmed = text.hasSuffix("\n") ? String(text.dropLast()) : text
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: MarkdownTheme.mono(size: monoSize),
                    .foregroundColor: MarkdownTheme.bodyColor,
                    .backgroundColor: MarkdownTheme.codeBackground,
                    .paragraphStyle: paragraphStyle(for: .code(nil), indent: 0, bodySize: bodySize)
                ]
                out.append(NSAttributedString(string: trimmed + "\n", attributes: attrs))

            case .paragraph:
                let base: [NSAttributedString.Key: Any] = [
                    .font: MarkdownTheme.body(size: bodySize),
                    .foregroundColor: MarkdownTheme.bodyColor,
                    .paragraphStyle: paragraphStyle(for: .paragraph, indent: block.indent, bodySize: bodySize)
                ]
                out.append(inline(doc: doc, block: block, base: base, bodySize: bodySize))
                out.append(NSAttributedString(string: "\n", attributes: base))
            }
        }

        if out.length == 0 {
            out.append(NSAttributedString(string: "Empty note", attributes: [
                .font: MarkdownTheme.body(size: bodySize),
                .foregroundColor: MarkdownTheme.tertiaryColor
            ]))
        }
        return out
    }

    /// Renders one block's text with syntax markers removed.
    private static func inline(doc: MarkdownDocument,
                               block: MarkdownBlock,
                               base: [NSAttributedString.Key: Any],
                               bodySize: CGFloat) -> NSAttributedString {
        let ns = doc.text
        let content = block.contentRange
        guard content.length > 0, NSMaxRange(content) <= ns.length else {
            return NSAttributedString(string: "", attributes: base)
        }

        let spans = block.inlines
        var breakpoints: Set<Int> = [content.location, NSMaxRange(content)]
        for span in spans {
            if span.range.location >= content.location, NSMaxRange(span.range) <= NSMaxRange(content) {
                breakpoints.insert(span.range.location)
                breakpoints.insert(NSMaxRange(span.range))
            }
        }
        let sorted = breakpoints.sorted()

        let result = NSMutableAttributedString()
        for i in 0..<(sorted.count - 1) {
            let start = sorted[i]
            let end = sorted[i + 1]
            guard end > start else { continue }
            if isSyntax(start, spans: spans) { continue }

            var attrs = base
            for span in spans where span.range.location <= start && NSMaxRange(span.range) > start {
                switch span.kind {
                case .syntax:
                    break
                case .bold:
                    attrs[.font] = NSFont.systemFont(ofSize: fontSize(for: block.kind, bodySize: bodySize), weight: .bold)
                case .italic:
                    attrs[.font] = MarkdownTheme.italic(size: fontSize(for: block.kind, bodySize: bodySize))
                case .boldItalic:
                    attrs[.font] = MarkdownTheme.boldItalic(size: fontSize(for: block.kind, bodySize: bodySize))
                case .strike:
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                case .code:
                    attrs[.font] = MarkdownTheme.mono(size: fontSize(for: block.kind, bodySize: bodySize) - 1.5)
                    attrs[.foregroundColor] = MarkdownTheme.codeColor
                    attrs[.backgroundColor] = MarkdownTheme.codeBackground
                case .link(let url):
                    attrs[.foregroundColor] = MarkdownTheme.accentColor
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    if let u = URL(string: url) { attrs[.link] = u }
                case .wikilink:
                    attrs[.foregroundColor] = MarkdownTheme.accentColor
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                case .tag(let name):
                    attrs[.foregroundColor] = MarkdownTheme.accentColor
                }
            }

            result.append(NSAttributedString(string: ns.substring(with: NSRange(location: start, length: end - start)),
                                             attributes: attrs))
        }
        return result
    }

    private static func isSyntax(_ location: Int, spans: [InlineSpan]) -> Bool {
        for span in spans where span.kind == .syntax {
            if span.range.location <= location && NSMaxRange(span.range) > location { return true }
        }
        return false
    }

    // MARK: - Paragraph styles

    static func paragraphStyle(for kind: BlockKind,
                               indent: Int,
                               bodySize: CGFloat = MarkdownTheme.bodySize) -> NSParagraphStyle {
        let scale = bodySize / MarkdownTheme.bodySize
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3.5 * scale
        style.paragraphSpacing = 3 * scale
        style.lineBreakMode = .byWordWrapping

        switch kind {
        case .heading(let level):
            style.paragraphSpacingBefore = (level == 1 ? 16 : (level == 2 ? 14 : 10)) * scale
            style.paragraphSpacing = (level <= 2 ? 6 : 3) * scale
            style.lineSpacing = 2 * scale
        case .bullet, .numbered, .task:
            let extra = CGFloat(indent) * 12 * scale
            style.headIndent = 22 * scale + extra
            style.firstLineHeadIndent = extra
        case .quote:
            let extra = CGFloat(indent) * 12 * scale
            style.headIndent = 18 * scale + extra
            style.firstLineHeadIndent = 18 * scale + extra
            style.paragraphSpacingBefore = 4 * scale
            style.paragraphSpacing = 6 * scale
        case .code:
            style.headIndent = 12 * scale
            style.tailIndent = -12 * scale
            style.firstLineHeadIndent = 12 * scale
            style.lineSpacing = 2 * scale
            style.paragraphSpacingBefore = 6 * scale
            style.paragraphSpacing = 8 * scale
        case .rule:
            style.paragraphSpacingBefore = 10 * scale
            style.paragraphSpacing = 12 * scale
        default:
            break
        }
        return style
    }
}
