import SwiftUI

// MARK: - Brand: "Lady Grinning Soul"
// Aladdin Sane–era glamour. Green silk in a mid-century modern hotel lobby:
// lacquered black shine, malachite silk, antique-gold highlights, ivory marble,
// granite floor, feathers and diffused light.

enum Brand {
    // Lacquered black shine (tinted green, never pure black)
    static let lacquer      = Color(hex: "#080B09")
    static let lacquerRaise = Color(hex: "#0D1310")
    static let panel        = Color(hex: "#111A15")

    // Green silk sheets — malachite jewel tones
    static let emeraldDeep  = Color(hex: "#0A4433")
    static let emerald      = Color(hex: "#116B4E")
    static let emeraldSilk  = Color(hex: "#1E9068")

    // Antique gold highlights
    static let gold         = Color(hex: "#C9A55C")
    static let goldBright   = Color(hex: "#E9D19A")

    // Marble columns (warm ivory) & granite floor (cool grey-green)
    static let ivory        = Color(hex: "#ECE6D4")
    static let granite      = Color(hex: "#84908A")

    // Aladdin Sane lightning — a rare flame accent, used almost nowhere
    static let flame        = Color(hex: "#C6413B")

    static let corner: CGFloat = 6   // hotel-lobby squared elegance, not app-round
}

// MARK: - Typography (all iOS system-available faces — no bundling)

enum BrandFont {
    /// Didone display — feathers, marble, fashion editorial.
    static func display(_ size: CGFloat) -> Font { .custom("Didot", size: size) }
    /// Dramatic high-contrast numerals for the ledger.
    static func numeral(_ size: CGFloat) -> Font { .custom("Didot", size: size) }
    /// Gold hotel-signage labels — small caps, wide tracking.
    static func signage(_ size: CGFloat) -> Font { .custom("Bodoni 72 Smallcaps", size: size) }
    /// Refined body / UI.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Avenir Next", size: size).weight(weight)
    }
}

// MARK: - Signature elements

/// A thin gold rule that fades at both ends, like inlaid brass in marble.
struct GoldHairline: View {
    var opacity: Double = 1
    var body: some View {
        LinearGradient(
            colors: [.clear, Brand.gold.opacity(0.65 * opacity), Brand.goldBright.opacity(0.9 * opacity),
                     Brand.gold.opacity(0.65 * opacity), .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
    }
}

/// Soft diffused light — a hazy glow, never a neon bloom.
struct DiffusedGlow: View {
    var color: Color = Brand.emeraldSilk
    var body: some View {
        RadialGradient(colors: [color.opacity(0.30), .clear],
                       center: .center, startRadius: 2, endRadius: 220)
        .blur(radius: 24)
        .blendMode(.screen)
    }
}

/// A single drawn plume — the feather motif. Subtle, gold, low opacity.
struct Feather: View {
    var tint: Color = Brand.gold
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let spine = Path { p in
                p.move(to: CGPoint(x: w * 0.5, y: h))
                p.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0),
                               control: CGPoint(x: w * 0.72, y: h * 0.5))
            }
            ctx.stroke(spine, with: .color(tint.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            // barbs
            let count = 26
            for i in 1...count {
                let t = CGFloat(i) / CGFloat(count + 1)
                let sx = w * 0.5 + (w * 0.22) * sin(t * .pi)
                let sy = h * (1 - t)
                let len = (w * 0.30) * sin(t * .pi) * (1 - t * 0.15)
                for dir in [-1.0, 1.0] {
                    let barb = Path { p in
                        p.move(to: CGPoint(x: sx, y: sy))
                        p.addQuadCurve(
                            to: CGPoint(x: sx + CGFloat(dir) * len, y: sy - len * 0.35),
                            control: CGPoint(x: sx + CGFloat(dir) * len * 0.5, y: sy - len * 0.05))
                    }
                    ctx.stroke(barb, with: .color(tint.opacity(0.16)),
                               style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                }
            }
        }
    }
}

extension View {
    /// Lacquered panel with a hairline edge — the surfaces of the lobby.
    func lacquerPanel() -> some View {
        self
            .background(
                LinearGradient(colors: [Brand.panel, Brand.lacquerRaise],
                               startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: Brand.corner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Brand.corner, style: .continuous)
                    .stroke(Brand.gold.opacity(0.14), lineWidth: 0.75)
            )
    }
}
