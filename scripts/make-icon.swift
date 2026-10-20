// Renders the BrowThere app icon. Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let k = s / 1024

    // Apple grid: 824pt body inside a 1024 canvas, continuous-corner squircle.
    let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * k, yRadius: 185 * k).cgPath

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 28 * k, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient: deep indigo → violet → warm pink
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let cs = CGColorSpace(name: CGColorSpace.displayP3)!
    let bg = CGGradient(colorsSpace: cs, colors: [
        CGColor(colorSpace: cs, components: [0.15, 0.13, 0.52, 1])!,
        CGColor(colorSpace: cs, components: [0.42, 0.22, 0.86, 1])!,
        CGColor(colorSpace: cs, components: [0.96, 0.42, 0.62, 1])!,
    ] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])

    // Soft glow behind the glyph
    let glow = CGGradient(colorsSpace: cs, colors: [
        CGColor(colorSpace: cs, components: [1, 1, 1, 0.28])!,
        CGColor(colorSpace: cs, components: [1, 1, 1, 0])!,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512 * k, y: 600 * k), startRadius: 0,
                           endCenter: CGPoint(x: 512 * k, y: 600 * k), endRadius: 420 * k, options: [])

    // Top glass highlight
    let hl = CGGradient(colorsSpace: cs, colors: [
        CGColor(colorSpace: cs, components: [1, 1, 1, 0.22])!,
        CGColor(colorSpace: cs, components: [1, 1, 1, 0])!,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY + 60 * k), options: [])
    ctx.restoreGState()

    // Glyph: one stem that forks into three arrows, drawn as one layer so the shadow doesn't overlap itself.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k,
                  color: NSColor(calibratedRed: 0.12, green: 0.04, blue: 0.38, alpha: 0.5).cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.setLineWidth(54 * k)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
    let origin = pt(512, 250), fork = pt(512, 470)
    let p = CGMutablePath()
    p.move(to: origin)
    p.addLine(to: fork)
    p.move(to: fork)
    p.addLine(to: pt(512, 780))
    let left = pt(280, 700), right = pt(744, 700)
    let lc2 = pt(370, 590), rc2 = pt(654, 590)
    p.move(to: fork)
    p.addCurve(to: left, control1: pt(512, 540), control2: lc2)
    p.move(to: fork)
    p.addCurve(to: right, control1: pt(512, 540), control2: rc2)

    // Chevron heads, aligned with each branch's final tangent.
    func chevron(at tip: CGPoint, from: CGPoint) {
        let a = atan2(tip.y - from.y, tip.x - from.x)
        let len = 96 * k, spread: CGFloat = 0.72
        p.move(to: CGPoint(x: tip.x - cos(a - spread) * len, y: tip.y - sin(a - spread) * len))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x - cos(a + spread) * len, y: tip.y - sin(a + spread) * len))
    }
    chevron(at: pt(512, 780), from: fork)
    chevron(at: left, from: lc2)
    chevron(at: right, from: rc2)
    ctx.addPath(p)
    ctx.strokePath()

    ctx.fillEllipse(in: CGRect(x: origin.x - 62 * k, y: origin.y - 62 * k, width: 124 * k, height: 124 * k))
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Hairline rim
    ctx.addPath(shape)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    ctx.setLineWidth(3 * k)
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
