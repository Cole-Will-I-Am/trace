import SwiftUI

// Trace design system. The whole game is a glowing finger-trail through dark corridors, so
// the brand is: a near-black themed void, low-contrast walls that recede, and ONE luminous
// accent that the trail (and the goal) burn with — a different accent per level theme, so
// the 21 levels each have their own light. Danger colours (spikes/closed gates) are shared
// and reserved, never used for chrome, so "red = it will hurt you" stays legible everywhere.

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// One level's colour identity. `accent`→`accentHi` is the trail gradient (cosmetic, feels
/// great); `glow` is the bloom the trail/goal cast; `wall`/`corridor`/`bg` build the maze.
struct Theme {
    let bg: Color
    let corridor: Color
    let wall: Color
    let accent: Color
    let accentHi: Color
    let glow: Color

    // shared, reserved meanings (consistent across every theme)
    static let danger     = Color(hex: 0xFF4D4D)   // spikes, closed gates, wall-bonk
    static let dangerDeep = Color(hex: 0x7A1B1B)
    static let checkpoint = Color(hex: 0x9BE8C2)   // soft mint — "safe again"
    static let gateOpen   = Color(hex: 0x6FE3FF)
    static let moving     = Color(hex: 0xFF9A3D)   // patrolling hazard orb
    static let goalRing    = Color(hex: 0xFFE9A8)

    static let ink        = Color(hex: 0x0B0E12)   // app chrome background (meta screens)
    static let inkRaised  = Color(hex: 0x161B22)
    static let onInk      = Color(hex: 0xEDF2F7)
    static let onInkDim   = Color(hex: 0x97A2B0)
    static let hairline   = Color(hex: 0xEDF2F7, alpha: 0.10)

    static func of(_ id: ThemeID) -> Theme { palettes[id] ?? palettes[.stoneMaze]! }

    private static let palettes: [ThemeID: Theme] = [
        .tutorialGrove:    Theme(bg: 0x0A140D, corridor: 0x12241A, wall: 0x274536, accent: 0x6FE39A, accentHi: 0xCFF8DE, glow: 0x57E08C),
        .gardenPath:       Theme(bg: 0x0D140A, corridor: 0x1A2412, wall: 0x39512A, accent: 0xA6E368, accentHi: 0xE6F8C8, glow: 0x9BE057),
        .stoneMaze:        Theme(bg: 0x0E1013, corridor: 0x1A1E24, wall: 0x3A424E, accent: 0x9FB2C9, accentHi: 0xE3ECF6, glow: 0x8FA6C2),
        .sandDunes:        Theme(bg: 0x16100A, corridor: 0x261C10, wall: 0x55401F, accent: 0xF3C265, accentHi: 0xFCEBC2, glow: 0xF0B84E),
        .crystalCavern:    Theme(bg: 0x07151A, corridor: 0x0E2A33, wall: 0x1C5161, accent: 0x4FE0E8, accentHi: 0xCFFAFC, glow: 0x39D8E2),
        .frostHollow:      Theme(bg: 0x0A1320, corridor: 0x132538, wall: 0x274867, accent: 0x73B8FF, accentHi: 0xD4EBFF, glow: 0x5AA8FF),
        .emberForge:       Theme(bg: 0x190B07, corridor: 0x2C140C, wall: 0x60291A, accent: 0xFF8A4D, accentHi: 0xFFD7B5, glow: 0xFF7733),
        .tidePools:        Theme(bg: 0x06161A, corridor: 0x0C2A2E, wall: 0x195158, accent: 0x4FE3C4, accentHi: 0xCBFBEE, glow: 0x38DCB8),
        .neonCircuit:      Theme(bg: 0x110718, corridor: 0x21102E, wall: 0x4A1F66, accent: 0xE65BFF, accentHi: 0xF7CCFF, glow: 0xDD3DFF),
        .clockworkHalls:   Theme(bg: 0x16120A, corridor: 0x261F10, wall: 0x564321, accent: 0xE7BE5A, accentHi: 0xFBEBBF, glow: 0xE2B23F),
        .shadowVault:      Theme(bg: 0x0A0814, corridor: 0x161025, wall: 0x322152, accent: 0x9D7BFF, accentHi: 0xDDD0FF, glow: 0x8A63FF),
        .mirrorLabyrinth:  Theme(bg: 0x0D0E14, corridor: 0x191B26, wall: 0x393E55, accent: 0xC7CBFF, accentHi: 0xEDEEFF, glow: 0xB0B6FF),
        .thornThicket:     Theme(bg: 0x0B130C, corridor: 0x152017, wall: 0x2C432F, accent: 0x86D17A, accentHi: 0xD6F3CE, glow: 0x6FC861),
        .stormSpire:       Theme(bg: 0x0A0D1A, corridor: 0x141A2E, wall: 0x283457, accent: 0x6E8BFF, accentHi: 0xD2DBFF, glow: 0x5775FF),
        .moltenCore:       Theme(bg: 0x1A0905, corridor: 0x2E120A, wall: 0x652515, accent: 0xFF6A3D, accentHi: 0xFFC9AE, glow: 0xFF4F1F),
        .glacierDepths:    Theme(bg: 0x0B1620, corridor: 0x152A38, wall: 0x2A5168, accent: 0x9BD9F2, accentHi: 0xE2F6FF, glow: 0x82CFEE),
        .voidNexus:        Theme(bg: 0x07060E, corridor: 0x110F1E, wall: 0x281F44, accent: 0xB07BFF, accentHi: 0xE6D6FF, glow: 0x9C5BFF),
        .ancientMechanism: Theme(bg: 0x0A1212, corridor: 0x142322, wall: 0x274643, accent: 0x57D6C2, accentHi: 0xCFF7EF, glow: 0x3FCBB4),
        .phantomMaze:      Theme(bg: 0x0A0F12, corridor: 0x141D22, wall: 0x2A3B43, accent: 0x8FE9F0, accentHi: 0xDDFAFC, glow: 0x73E0E9),
        .infernoGauntlet:  Theme(bg: 0x1A0705, corridor: 0x2E0F09, wall: 0x67211A, accent: 0xFF5530, accentHi: 0xFFC1AE, glow: 0xFF3A14),
        .finalKnot:        Theme(bg: 0x14100A, corridor: 0x231C10, wall: 0x4E3D1E, accent: 0xFFD66B, accentHi: 0xFFF1C7, glow: 0xFFC93F),
    ]

    private init(bg: UInt32, corridor: UInt32, wall: UInt32, accent: UInt32, accentHi: UInt32, glow: UInt32) {
        self.bg = Color(hex: bg); self.corridor = Color(hex: corridor); self.wall = Color(hex: wall)
        self.accent = Color(hex: accent); self.accentHi = Color(hex: accentHi); self.glow = Color(hex: glow)
    }
}

enum Typeface {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static let h1   = display(30, .bold)
    static let h2   = display(20, .semibold)
    static let body = display(16, .regular)
    static let cap  = display(13, .medium)
    static let timer = mono(34, .bold)
}

enum Metrics {
    static let cardRadius: CGFloat = 18
    static let tile: CGFloat = 12
}

#if canImport(UIKit)
import UIKit

/// Haptics (blueprint §8). Sharp on a wall bonk, soft tick on checkpoint, success on goal.
enum Haptics {
    private static func impact(_ s: UIImpactFeedbackGenerator.FeedbackStyle, _ i: CGFloat = 1) {
        let g = UIImpactFeedbackGenerator(style: s); g.impactOccurred(intensity: i)
    }
    static func wall()       { impact(.rigid, 0.7) }
    static func step()       { impact(.soft, 0.35) }
    static func checkpoint() { impact(.light, 0.8) }
    static func backtrack()  { impact(.soft, 0.5) }
    static func trap()       { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func goal()       { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func tap()        { impact(.light, 0.6) }
}
#else
enum Haptics {
    static func wall() {}; static func step() {}; static func checkpoint() {}
    static func backtrack() {}; static func trap() {}; static func goal() {}; static func tap() {}
}
#endif
