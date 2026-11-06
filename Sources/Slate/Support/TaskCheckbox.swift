import AppKit

/// Reading-mode task checkboxes.
///
/// The rendered page has no source text for a task marker, so each checkbox
/// carries the source offset of the line it came from. Clicking the box asks
/// the store to flip `- [ ]` / `- [x]` at that line, which is the same edit the
/// user would make in the editor — the file stays the single source of truth.
extension NSAttributedString.Key {
    /// Source offset of the task line the attachment came from.
    static let slateTaskLocation = NSAttributedString.Key("SlateTaskLocation")
}

/// Draws the box itself. A cell rather than a bitmap so the box follows the
/// system accent colour and redraws when the appearance changes.
final class TaskCheckboxCell: NSTextAttachmentCell {
    private let done: Bool
    private let boxSize: CGFloat

    init(done: Bool, size: CGFloat) {
        self.done = done
        self.boxSize = size
        super.init()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func cellSize() -> NSSize {
        NSSize(width: boxSize + 6, height: boxSize + 4)
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: -2)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let rect = NSRect(
            x: cellFrame.midX - boxSize / 2,
            y: cellFrame.midY - boxSize / 2,
            width: boxSize,
            height: boxSize
        )
        let radius = boxSize * 0.28
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        if done {
            NSColor.controlAccentColor.setFill()
            path.fill()
            let tick = NSBezierPath()
            tick.lineWidth = max(1.6, boxSize * 0.14)
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            tick.move(to: NSPoint(x: rect.minX + boxSize * 0.26, y: rect.midY + boxSize * 0.02))
            tick.line(to: NSPoint(x: rect.minX + boxSize * 0.44, y: rect.midY - boxSize * 0.18))
            tick.line(to: NSPoint(x: rect.minX + boxSize * 0.76, y: rect.midY + boxSize * 0.22))
            NSColor.white.setStroke()
            tick.stroke()
        } else {
            NSColor.tertiaryLabelColor.setStroke()
            path.lineWidth = max(1.2, boxSize * 0.1)
            path.stroke()
        }
    }
}

enum TaskCheckbox {
    /// A checkbox plus the trailing gap that replaces the `- [ ] ` marker.
    static func attachment(done: Bool, sourceLocation: Int, bodySize: CGFloat) -> NSAttributedString {
        let size = (bodySize * 0.86).rounded()
        let cell = TaskCheckboxCell(done: done, size: size)
        let attachment = NSTextAttachment()
        attachment.attachmentCell = cell

        let string = NSMutableAttributedString(attachment: attachment)
        string.addAttribute(.slateTaskLocation,
                            value: sourceLocation,
                            range: NSRange(location: 0, length: string.length))
        string.append(NSAttributedString(string: "   "))
        return string
    }
}
