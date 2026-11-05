// Renders the Drift app icon to a 1024×1024 PNG.  Usage: swift tools/make_icon.swift out.png
import Cocoa

let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }

// Body (Apple macOS icon grid: 824pt body, 100pt margin)
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
ctx.addPath(bodyPath); ctx.setFillColor(rgb(0.1, 0.1, 0.25)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(0.30, 0.22, 0.52), rgb(0.12, 0.13, 0.33), rgb(0.04, 0.06, 0.15)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 700, y: 100), options: [])
// moon glow
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0.75, 0.88, 1, 0.45), rgb(0.6, 0.8, 1, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 720, y: 760), startRadius: 0,
                       endCenter: CGPoint(x: 720, y: 760), endRadius: 300, options: [])

// window
let win = CGRect(x: 250, y: 220, width: 524, height: 380)
let winPath = CGPath(roundedRect: win, cornerWidth: 46, cornerHeight: 46, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0, 0, 0.1, 0.45))
ctx.addPath(winPath); ctx.setFillColor(rgb(0.86, 0.92, 1, 0.16)); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(winPath); ctx.setStrokeColor(rgb(1, 1, 1, 0.35)); ctx.setLineWidth(4); ctx.strokePath()
for (i, c) in [rgb(1, 0.37, 0.34), rgb(1, 0.74, 0.18), rgb(0.16, 0.79, 0.25)].enumerated() {
    ctx.setFillColor(c.copy(alpha: 0.85)!)
    ctx.fillEllipse(in: CGRect(x: win.minX + 36 + CGFloat(i) * 44, y: win.maxY - 62, width: 26, height: 26))
}
// content lines
ctx.setFillColor(rgb(1, 1, 1, 0.18))
for (i, w) in [300.0, 380.0, 240.0].enumerated() {
    ctx.addPath(CGPath(roundedRect: CGRect(x: win.minX + 40, y: win.maxY - 130 - CGFloat(i) * 52, width: w, height: 22),
                       cornerWidth: 11, cornerHeight: 11, transform: nil))
    ctx.fillPath()
}

// soft snow cap on the window
let cap = CGMutablePath()
cap.move(to: CGPoint(x: win.minX + 20, y: win.maxY - 14))
cap.addCurve(to: CGPoint(x: win.minX + 230, y: win.maxY + 58),
             control1: CGPoint(x: win.minX + 40, y: win.maxY + 40), control2: CGPoint(x: win.minX + 130, y: win.maxY + 64))
cap.addCurve(to: CGPoint(x: win.minX + 400, y: win.maxY + 46),
             control1: CGPoint(x: win.minX + 300, y: win.maxY + 54), control2: CGPoint(x: win.minX + 340, y: win.maxY + 70))
cap.addCurve(to: CGPoint(x: win.maxX - 20, y: win.maxY - 14),
             control1: CGPoint(x: win.minX + 470, y: win.maxY + 30), control2: CGPoint(x: win.maxX - 10, y: win.maxY + 20))
cap.addCurve(to: CGPoint(x: win.minX + 20, y: win.maxY - 14),
             control1: CGPoint(x: win.maxX - 120, y: win.maxY + 4), control2: CGPoint(x: win.minX + 120, y: win.maxY + 4))
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 26, color: rgb(0.85, 0.93, 1, 0.9))
ctx.addPath(cap); ctx.setFillColor(rgb(0.97, 0.98, 1)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(cap); ctx.clip()
let snowG = CGGradient(colorsSpace: cs, colors: [rgb(1, 1, 1), rgb(0.8, 0.87, 0.97)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(snowG, start: CGPoint(x: 0, y: win.maxY + 70), end: CGPoint(x: 0, y: win.maxY - 14), options: [])
ctx.restoreGState()

// falling flakes
var seed: UInt64 = 7
func rand() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
for _ in 0..<46 {
    let x = 130 + rand() * 764, y = 130 + rand() * 780, r = 5 + rand() * 11
    if win.insetBy(dx: -10, dy: -10).contains(CGPoint(x: x, y: y)) { continue }
    if y < win.maxY + 80 && x > win.minX && x < win.maxX { continue }
    ctx.setFillColor(rgb(1, 1, 1, 0.55 + rand() * 0.45))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}
// snow drift along the bottom
let drift = CGMutablePath()
drift.move(to: CGPoint(x: 100, y: 100))
drift.addLine(to: CGPoint(x: 100, y: 190))
drift.addCurve(to: CGPoint(x: 520, y: 170), control1: CGPoint(x: 250, y: 240), control2: CGPoint(x: 380, y: 150))
drift.addCurve(to: CGPoint(x: 924, y: 210), control1: CGPoint(x: 680, y: 195), control2: CGPoint(x: 800, y: 250))
drift.addLine(to: CGPoint(x: 924, y: 100)); drift.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 20, color: rgb(0.85, 0.93, 1, 0.7))
ctx.addPath(drift); ctx.setFillColor(rgb(0.93, 0.96, 1)); ctx.fillPath()
ctx.restoreGState()
ctx.restoreGState()

// subtle rim
ctx.addPath(bodyPath); ctx.setStrokeColor(rgb(1, 1, 1, 0.12)); ctx.setLineWidth(3); ctx.strokePath()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
