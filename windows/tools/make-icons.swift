// Writes the Windows .ico files for Synklok.Tray/Assets:
//   synklok.ico        app icon (dark tile + green metronome, like the Mac icon)
//   tray-ok.ico        green metronome   — connected
//   tray-off.ico       grey metronome    — M-1620 not found
//   tray-warn.ico      amber metronome   — rates out of sync / attention
// Each .ico holds 32-bit DIB frames at the sizes Windows asks for.
//
// Usage (from windows/):  swift tools/make-icons.swift Synklok.Tray/Assets
import AppKit

let outDir = CommandLine.arguments.dropFirst().first ?? "Synklok.Tray/Assets"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}
let zinc950 = rgb(0x09090b), zinc800 = rgb(0x27272a)

/// The synklok.app metronome mark (24-unit SVG box, y down), even-odd window.
func mark(in rect: CGRect) -> CGPath {
    let s = min(rect.width / 14, rect.height / 20)          // mark spans x 5…19, y 2…22
    let cx = rect.midX, cy = rect.midY
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cx + (x - 12) * s, y: cy - (y - 12) * s) }
    let path = CGMutablePath()
    path.addLines(between: [p(9, 2), p(15, 2), p(19, 20), p(17, 22), p(7, 22), p(5, 20)])
    path.closeSubpath()
    path.addLines(between: [p(11, 6), p(9, 15), p(15, 15), p(13, 6)])
    path.closeSubpath()
    return path
}

/// Renders one square frame and returns premultiplied RGBA bytes, top row first.
func render(_ size: Int, draw: (CGContext, CGFloat) -> Void) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: size * size * 4)
    let ctx = CGContext(data: &data, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    draw(ctx, CGFloat(size))
    return data
}

func appFrame(_ n: CGFloat, _ ctx: CGContext) {
    let inset = n * 0.06
    let tile = CGRect(x: inset, y: inset, width: n - 2 * inset, height: n - 2 * inset)
    let path = CGPath(roundedRect: tile, cornerWidth: n * 0.2, cornerHeight: n * 0.2, transform: nil)
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [zinc800, zinc950] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: n), end: CGPoint(x: 0, y: n * 0.35),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
    ctx.addPath(mark(in: tile.insetBy(dx: n * 0.2, dy: n * 0.17)))
    ctx.setFillColor(rgb(0x4ade80))
    ctx.fillPath(using: .evenOdd)
}

func trayFrame(_ n: CGFloat, _ ctx: CGContext, _ color: CGColor) {
    // Fill most of the square; tray icons are tiny.
    ctx.addPath(mark(in: CGRect(x: 0, y: 0, width: n, height: n).insetBy(dx: n * 0.04, dy: n * 0.03)))
    ctx.setFillColor(color)
    ctx.fillPath(using: .evenOdd)
}

/// ICO container with 32-bit BGRA DIB frames (BITMAPINFOHEADER + XOR + AND mask).
func writeICO(_ name: String, sizes: [Int], draw: @escaping (CGContext, CGFloat) -> Void) {
    var frames: [(Int, Data)] = []
    for size in sizes {
        let rgba = render(size) { ctx, n in draw(ctx, n) }
        var dib = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { dib.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { dib.append(contentsOf: $0) } }
        let maskRow = ((size + 31) / 32) * 4
        u32(40); u32(UInt32(size)); u32(UInt32(size * 2)); u16(1); u16(32); u32(0)
        u32(UInt32(size * size * 4 + maskRow * size)); u32(0); u32(0); u32(0); u32(0)
        for row in (0..<size).reversed() {                       // DIBs are bottom-up
            for col in 0..<size {
                let i = (row * size + col) * 4
                let a = rgba[i + 3]
                // Un-premultiply for the straight-alpha BGRA ICO expects.
                func un(_ c: UInt8) -> UInt8 { a == 0 ? 0 : UInt8(min(255, Int(c) * 255 / Int(a))) }
                dib.append(contentsOf: [un(rgba[i + 2]), un(rgba[i + 1]), un(rgba[i]), a])
            }
        }
        dib.append(Data(count: maskRow * size))                  // AND mask unused with 32-bit alpha
        frames.append((size, dib))
    }
    var ico = Data()
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { ico.append(contentsOf: $0) } }
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { ico.append(contentsOf: $0) } }
    u16(0); u16(1); u16(UInt16(frames.count))
    var offset = 6 + 16 * frames.count
    for (size, dib) in frames {
        ico.append(UInt8(size >= 256 ? 0 : size)); ico.append(UInt8(size >= 256 ? 0 : size))
        ico.append(0); ico.append(0); u16(1); u16(32); u32(UInt32(dib.count)); u32(UInt32(offset))
        offset += dib.count
    }
    for (_, dib) in frames { ico.append(dib) }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try! ico.write(to: url)
    print("wrote \(url.path) (\(sizes.map(String.init).joined(separator: ","))px)")
}

writeICO("synklok.ico", sizes: [16, 20, 24, 32, 40, 48, 64, 256]) { ctx, n in appFrame(n, ctx) }
let traySizes = [16, 20, 24, 32, 40, 48]
writeICO("tray-ok.ico", sizes: traySizes) { ctx, n in trayFrame(n, ctx, rgb(0x4ade80)) }
writeICO("tray-off.ico", sizes: traySizes) { ctx, n in trayFrame(n, ctx, rgb(0xa1a1aa)) }
writeICO("tray-warn.ico", sizes: traySizes) { ctx, n in trayFrame(n, ctx, rgb(0xfbbf24)) }
