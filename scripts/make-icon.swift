// Renders the 1024×1024 Synklok app icon: the synklok.app metronome mark
// (green-400 on zinc-950) inside the macOS icon shape.
//
// Usage: swift scripts/make-icon.swift <out.png>
// Then scripts/make-icon.sh slices it into the asset catalog.
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"

let zinc950 = NSColor(srgbRed: 0x09/255, green: 0x09/255, blue: 0x0b/255, alpha: 1)
let zinc800 = NSColor(srgbRed: 0x27/255, green: 0x27/255, blue: 0x2a/255, alpha: 1)
let green400 = NSColor(srgbRed: 0x4a/255, green: 0xde/255, blue: 0x80/255, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824 pt rounded square centred in 1024, with a soft drop shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
              color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(tilePath)
ctx.setFillColor(zinc950.cgColor)
ctx.fillPath()
ctx.restoreGState()

// Subtle top-lit gradient and hairline edge, like the site's zinc cards.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [zinc800.cgColor, zinc950.cgColor] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 380), options: [])
ctx.restoreGState()
ctx.addPath(tilePath)
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
ctx.setLineWidth(4)
ctx.strokePath()

// The site logo path, 24-unit SVG box (y down):
//   M9 2h6l4 18-2 2H7l-2-2L9 2z  m2 4l-2 9h6l-2-9h-2z   (even-odd window)
let s: CGFloat = 25, cx: CGFloat = 512, cy: CGFloat = 512
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + (x - 12) * s, y: cy - (y - 12) * s) }
let mark = CGMutablePath()
mark.addLines(between: [p(9, 2), p(15, 2), p(19, 20), p(17, 22), p(7, 22), p(5, 20)])
mark.closeSubpath()
mark.addLines(between: [p(11, 6), p(9, 15), p(15, 15), p(13, 6)])
mark.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: green400.withAlphaComponent(0.45).cgColor)
ctx.addPath(mark)
ctx.setFillColor(green400.cgColor)
ctx.fillPath(using: .evenOdd)
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
