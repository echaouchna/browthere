import AppKit
import SwiftUI

/// The website's palette: night indigo surfaces, a glowing pink for the main action,
/// violet for links and chips, mint for "it worked". The app is always dark, like the site.
enum Theme {
    static let ink = NSColor(hex: 0x100E17)
    static let surface = NSColor(hex: 0x1B1826)
    static let raised = NSColor(hex: 0x262233)
    static let line = NSColor(hex: 0x322C43)
    static let text = NSColor(hex: 0xECE8F4)
    static let muted = NSColor(hex: 0x9D96AD)
    static let faint = NSColor(hex: 0x6F6880)
    static let pink = NSColor(hex: 0xEC72D4)
    static let violet = NSColor(hex: 0xA58CF7)
    static let mint = NSColor(hex: 0x8FDC8F)
    static let amber = NSColor(hex: 0xF2C46D)

    static var appearance: NSAppearance? { NSAppearance(named: .darkAqua) }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    static let brandInk = Color(nsColor: Theme.ink)
    static let brandSurface = Color(nsColor: Theme.surface)
    static let brandRaised = Color(nsColor: Theme.raised)
    static let brandLine = Color(nsColor: Theme.line)
    static let brandMuted = Color(nsColor: Theme.muted)
    static let brandFaint = Color(nsColor: Theme.faint)
    static let brandPink = Color(nsColor: Theme.pink)
    static let brandViolet = Color(nsColor: Theme.violet)
    static let brandMint = Color(nsColor: Theme.mint)
    static let brandAmber = Color(nsColor: Theme.amber)
}

extension View {
    /// Grouped settings form on the night-indigo background instead of the system gray.
    func themedForm() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.brandInk)
    }
}

/// The website's switch: pink when on, with a white knob. Drawn by hand so it stays on-brand
/// whatever accent color is picked in System Settings, and in inactive windows.
struct BrandSwitchStyle: ToggleStyle {
    var mini = false

    func makeBody(configuration: Configuration) -> some View {
        // LabeledContent keeps the form's layout: a two-Text label shows as title + description.
        LabeledContent {
            BrandSwitch(isOn: configuration.$isOn, mini: mini)
        } label: {
            configuration.label
        }
    }
}

private struct BrandSwitch: View {
    @Binding var isOn: Bool
    var mini: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let w: CGFloat = mini ? 30 : 38, h: CGFloat = mini ? 18 : 22, inset: CGFloat = 2
        Capsule()
            .fill(isOn ? Color.brandPink : Color.brandLine)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white)
                    .padding(inset)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
            .frame(width: w, height: h)
            .shadow(color: isOn ? Color.brandPink.opacity(0.45) : .clear, radius: 6)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.snappy(duration: 0.18)) { isOn.toggle() } }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAction { isOn.toggle() }
    }
}

/// The website's primary button: a glowing pink pill with dark text.
struct BrandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(nsColor: NSColor(hex: 0x1A0B17)))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.brandPink.opacity(configuration.isPressed ? 0.8 : 1)))
            .shadow(color: Color.brandPink.opacity(isEnabled ? 0.45 : 0), radius: 8, y: 2)
            .opacity(isEnabled ? 1 : 0.45)
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static var brand: BrandButtonStyle { BrandButtonStyle() }
}

/// The fork from the app icon (scripts/make-icon.swift draws the same shape), for the menu bar
/// and in-app headers. Coordinates are in the icon's 1024-unit canvas.
enum BrandGlyph {
    /// Stands in for an SF Symbol name wherever a view takes one (see IconTile).
    static let symbol = "browthere.fork"

    static func image(size: CGFloat, color: NSColor = .black, lineWidth: CGFloat = 70, template: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // The glyph spans about x 210…814 and y 188…819 with its stroke; frame it with a margin.
            let box = CGRect(x: 157, y: 148, width: 710, height: 710)
            let k = rect.width / box.width
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - box.minX) * k, y: (y - box.minY) * k) }

            let origin = pt(512, 250), fork = pt(512, 470)
            let left = pt(280, 700), right = pt(744, 700), lc2 = pt(370, 590), rc2 = pt(654, 590)
            let p = CGMutablePath()
            p.move(to: origin); p.addLine(to: pt(512, 780))
            p.move(to: fork); p.addCurve(to: left, control1: pt(512, 540), control2: lc2)
            p.move(to: fork); p.addCurve(to: right, control1: pt(512, 540), control2: rc2)
            func chevron(at tip: CGPoint, from: CGPoint) {
                let a = atan2(tip.y - from.y, tip.x - from.x), len = 96 * k, spread: CGFloat = 0.72
                p.move(to: CGPoint(x: tip.x - cos(a - spread) * len, y: tip.y - sin(a - spread) * len))
                p.addLine(to: tip)
                p.addLine(to: CGPoint(x: tip.x - cos(a + spread) * len, y: tip.y - sin(a + spread) * len))
            }
            chevron(at: pt(512, 780), from: fork)
            chevron(at: left, from: lc2)
            chevron(at: right, from: rc2)

            ctx.setStrokeColor(color.cgColor)
            ctx.setFillColor(color.cgColor)
            ctx.setLineWidth(lineWidth * k)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(p)
            ctx.strokePath()
            let r = 62 * k
            ctx.fillEllipse(in: CGRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2))
            return true
        }
        img.isTemplate = template
        return img
    }
}
