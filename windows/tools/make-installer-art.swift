// Writes installer/welcome.bmp, the tall picture on the Synklok installer's
// welcome and finish pages: zinc-950 panel with the green synklok.app
// metronome. 24-bit BMP (what NSIS expects), drawn at 2× the 164×314 slot so
// it stays sharp on high-DPI screens.
//
// Usage (from windows/):  swift tools/make-installer-art.swift installer/welcome.bmp
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "installer/welcome.bmp"
let w = 328, h = 628

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

var rgba = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setShouldAntialias(true)

// Panel with a faint top-down sheen, like the site's brushed panels.
ctx.setFillColor(rgb(0x09090b))
ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
let sheen = CGGradient(colorsSpace: nil, colors: [rgb(0x18181b), rgb(0x09090b)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: 0, y: CGFloat(h) * 0.45), options: [])

// The metronome mark (24-unit SVG box, y down), even-odd window; upper third.
let s: CGFloat = 7.2
let cx = CGFloat(w) / 2, cy = CGFloat(h) * 0.68
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + (x - 12) * s, y: cy - (y - 12) * s) }
let mark = CGMutablePath()
mark.addLines(between: [p(9, 2), p(15, 2), p(19, 20), p(17, 22), p(7, 22), p(5, 20)])
mark.closeSubpath()
mark.addLines(between: [p(11, 6), p(9, 15), p(15, 15), p(13, 6)])
mark.closeSubpath()
ctx.setShadow(offset: .zero, blur: 28, color: CGColor(srgbRed: 0.29, green: 0.87, blue: 0.5, alpha: 0.45))
ctx.addPath(mark)
ctx.setFillColor(rgb(0x4ade80))
ctx.fillPath(using: .evenOdd)

// BMP: bottom-up rows of BGR, each padded to 4 bytes. CGContext rows are top-down.
let rowSize = (w * 3 + 3) & ~3
var bmp = Data()
func le32(_ v: Int) { var x = UInt32(v).littleEndian; bmp.append(Data(bytes: &x, count: 4)) }
func le16(_ v: Int) { var x = UInt16(v).littleEndian; bmp.append(Data(bytes: &x, count: 2)) }
bmp.append(contentsOf: [0x42, 0x4D]); le32(54 + rowSize * h); le32(0); le32(54)
le32(40); le32(w); le32(h); le16(1); le16(24); le32(0); le32(rowSize * h); le32(2835); le32(2835); le32(0); le32(0)
for y in (0..<h).reversed() {
    var row = [UInt8](repeating: 0, count: rowSize)
    for x in 0..<w {
        let i = (y * w + x) * 4
        row[x * 3] = rgba[i + 2]; row[x * 3 + 1] = rgba[i + 1]; row[x * 3 + 2] = rgba[i]
    }
    bmp.append(contentsOf: row)
}
try! bmp.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
