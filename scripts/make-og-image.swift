// Renders the 1200×630 link-preview card for synklok.app (og:image).
// Usage: swift scripts/make-og-image.swift <icon-1024.png> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let icon = NSImage(contentsOfFile: args[1]) else {
    print("usage: make-og-image.swift <icon-1024.png> <out.png>"); exit(1)
}
let w = 1200, h = 630
let zinc950 = NSColor(srgbRed: 0x09/255, green: 0x09/255, blue: 0x0b/255, alpha: 1)
let zinc400 = NSColor(srgbRed: 0xa1/255, green: 0xa1/255, blue: 0xaa/255, alpha: 1)
let green400 = NSColor(srgbRed: 0x4a/255, green: 0xde/255, blue: 0x80/255, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background: zinc-950 with the site's soft green glow, top-left.
ctx.setFillColor(zinc950.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [green400.withAlphaComponent(0.16).cgColor, green400.withAlphaComponent(0).cgColor] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 260, y: 560), startRadius: 0,
                       endCenter: CGPoint(x: 260, y: 560), endRadius: 700, options: [])

// App icon on the left (its PNG includes the macOS margin, so draw it large).
icon.draw(in: NSRect(x: 50, y: 85, width: 460, height: 460))

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: color, .kern: -0.5]
    NSAttributedString(string: s, attributes: attrs).draw(at: NSPoint(x: 540, y: y))
}
text("Synklok", size: 92, weight: .semibold, color: .white, at: 350)
text("Set it once. Sync forever.", size: 46, weight: .medium, color: green400, at: 280)
text("Automatic sample rate sync for the", size: 30, weight: .regular, color: zinc400, at: 200)
text("RME M-1620 Pro D  ·  macOS menu bar app", size: 30, weight: .regular, color: zinc400, at: 160)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
