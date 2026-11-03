// Draws the app icon (matching the in-app glyph) to a 1024pt PNG.
// Usage: swift Tools/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                           pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx

let inset: CGFloat = size * 0.08
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = rect.width * 0.225
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// Drop shadow
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = size * 0.03
shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
shadow.set()
NSColor(calibratedRed: 0.95, green: 0.6, blue: 0.22, alpha: 1).setFill()
path.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// Gradient body
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.99, green: 0.82, blue: 0.42, alpha: 1),
    NSColor(calibratedRed: 0.93, green: 0.52, blue: 0.17, alpha: 1)
])!
gradient.draw(in: path, angle: -60)

// Inner highlight
NSGraphicsContext.current?.saveGraphicsState()
path.addClip()
let topGlow = NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height * 0.5)
NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
    .draw(in: topGlow, angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()

// Hairline
NSColor.white.withAlphaComponent(0.22).setStroke()
path.lineWidth = size * 0.006
path.stroke()

// Three text lines
let lineHeights: [CGFloat] = [0.085, 0.075, 0.075]
let widths: [CGFloat] = [0.42, 0.52, 0.34]
let spacing: CGFloat = 0.20
var y = rect.midY + size * 0.115
for i in 0..<3 {
    let h = size * lineHeights[i]
    let w = size * widths[i]
    let r = NSRect(x: rect.midX - w / 2, y: y, width: w, height: h)
    let bar = NSBezierPath(roundedRect: r, xRadius: h / 2, yRadius: h / 2)
    NSColor.white.withAlphaComponent(i == 0 ? 0.97 : 0.78).setFill()
    bar.fill()
    y -= size * spacing / 2.6
}

NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
