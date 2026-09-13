import SwiftUI
import UIKit

/// Every colour in Arch.
///
/// Views reference these tokens and nothing else — the hex initialisers below are
/// deliberately `fileprivate`, so a raw hex value cannot be written anywhere
/// outside this file without the compiler objecting. That discipline is what lets
/// the app carry two appearances without a single view knowing which one it is in:
/// every token below resolves per trait collection, so light mode is this file and
/// nothing else.
///
/// The palette is the brand board's four colours — Terracotta, Muted Amber,
/// Candlelight, Rich Charcoal — and the two worlds they describe. Light is paper in
/// morning sun; dark is the same room at night, warm rather than blue. Depth comes
/// from surface lightness (`night` -> `stone` -> `stoneRaised`), never from drop
/// shadows, in both.
enum ArchColor {

    // MARK: Surfaces

    /// App background. Candlelight by day; a charcoal a step below the brand's own,
    /// so a card can sit above it without a border.
    static let night = Color(light: 0xFAF6F0, dark: 0x191715)

    /// Cards, sheets, incoming message bubbles. White by day — the brand board's
    /// specimen card — and Rich Charcoal exactly by night.
    static let stone = Color(light: 0xFFFFFF, dark: 0x232120)

    /// Elevated surfaces, pressed states, tab bar, outgoing bubbles.
    static let stoneRaised = Color(light: 0xF2ECE2, dark: 0x2E2B29)

    // MARK: Ink

    /// Primary text. Rich Charcoal on paper, warm off-white at night — never pure
    /// black, never pure white.
    static let limestone = Color(light: 0x232120, dark: 0xF5EFE6)

    /// Secondary text, inactive icons, dividers. Warm grey in both worlds, held
    /// above 5:1 against its own background so a caption is never a guess.
    static let mortar = Color(light: 0x6F675F, dark: 0x9A8F86)

    // MARK: Accents

    /// Terracotta. The only colour that invites action: the primary button, the
    /// active tab, the slider, the mark itself.
    ///
    /// The brand's #D95D39 sits at 3.5:1 on paper and 4.2:1 on charcoal — fine for
    /// a shape, thin for a label sitting on one. So the token deepens it by day and
    /// lifts it by night, which is the same move a photograph makes when the light
    /// changes, and leaves the brand value for the places nothing sits on top of.
    static let lamp = Color(light: 0xC9512F, dark: 0xE5714D)

    /// Muted Amber. The second accent, and it has exactly one job: the Premium
    /// keystone in the tab bar.
    ///
    /// It marks the thing you can buy, which is why it stops at the tab. The
    /// paywall itself still spends `lamp` once, on its button, because subscribing
    /// is an action and actions are terracotta — an amber sell and an amber button
    /// would be the accent arguing with itself.
    static let ember = Color(light: 0xA9661A, dark: 0xF0A243)

    /// Oxidised copper. Appears only when two people have connected. If verdigris
    /// shows up as decoration anywhere, it is wrong.
    ///
    /// Warmed towards sage from the old blue-green so it belongs beside terracotta
    /// rather than arguing with it.
    static let verdigris = Color(light: 0x3F7359, dark: 0x7FA98F)

    // MARK: Ink on an accent

    /// What text and glyphs become when they sit **on** `lamp`.
    ///
    /// It inverts between the two worlds, and that is on purpose: a deepened
    /// terracotta by day carries pale ink at 4.5:1, a lifted one by night carries
    /// dark ink at 5.4:1. Chasing one constant ink across both would fail one of
    /// them. This is the only token that flips its own polarity.
    static let onLamp = Color(light: 0xFAF6F0, dark: 0x1F1C1A)

    // MARK: Derived

    /// Hairline dividers and the tab bar's top edge.
    static let hairline = mortar.opacity(0.16)

    /// Border of the quiet (pass / secondary) button.
    static let quietBorder = mortar.opacity(0.28)

    /// Pressed-state wash over any surface.
    static let pressed = mortar.opacity(0.10)

    /// Scrim behind full-screen modals.
    static let scrim = Color(light: 0x232120, dark: 0x0E0D0C).opacity(0.62)

    /// Outline of the segment the reader is currently on.
    static let lampQuiet = lamp.opacity(0.45)
}

private extension Color {
    /// Not available outside ArchColor.swift — that is the point.
    ///
    /// Resolved per trait collection rather than per launch, so the app follows a
    /// change of appearance while it is open, without a restart and without any
    /// view observing anything.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Quarry tones

extension ArchColor {

    /// A stand-in for a photograph. Photos in this build are drawn, not fetched,
    /// so they need material that reads as a lit surface without ever competing
    /// with `lamp` or `ember`.
    ///
    /// Each tone carries a second value a few percent along from the first. That is
    /// the whole gradient: enough to read as a lit surface, not enough to read as
    /// decoration. If it ever looks like a gradient, flatten it to `top` alone.
    ///
    /// By day these are washes of clay and linen on paper; by night the same
    /// materials in a dark room. Same six names, so a person's tone index keeps
    /// picking the same material whichever way the app is set.
    struct Material: Hashable {
        let name: String
        let top: Color
        let bottom: Color
    }

    static let materials: [Material] = [
        Material(name: "slate",
                 top: Color(light: 0xE4E0DA, dark: 0x2F3138),
                 bottom: Color(light: 0xDAD5CE, dark: 0x282A30)),
        Material(name: "clay",
                 top: Color(light: 0xEDDDCE, dark: 0x3E332A),
                 bottom: Color(light: 0xE4D2C0, dark: 0x362C24)),
        Material(name: "moss",
                 top: Color(light: 0xDFE3D8, dark: 0x2C3630),
                 bottom: Color(light: 0xD4DACC, dark: 0x262F2A)),
        Material(name: "ash",
                 top: Color(light: 0xE6E2DC, dark: 0x383A3E),
                 bottom: Color(light: 0xDCD7D0, dark: 0x303236)),
        Material(name: "ember",
                 top: Color(light: 0xF2DFCD, dark: 0x46332A),
                 bottom: Color(light: 0xE9D2BB, dark: 0x3D2C24)),
        Material(name: "linen",
                 top: Color(light: 0xEFE9DE, dark: 0x4A4640),
                 bottom: Color(light: 0xE6DED1, dark: 0x413E38))
    ]

    static func material(_ index: Int) -> Material {
        materials[((index % materials.count) + materials.count) % materials.count]
    }
}

#Preview("Palette") {
    let swatches: [(String, Color, String)] = [
        ("night", ArchColor.night, "App background"),
        ("stone", ArchColor.stone, "Cards, sheets, incoming bubbles"),
        ("stoneRaised", ArchColor.stoneRaised, "Elevated, tab bar, outgoing bubbles"),
        ("limestone", ArchColor.limestone, "Primary text"),
        ("mortar", ArchColor.mortar, "Secondary text, dividers"),
        ("lamp", ArchColor.lamp, "Action, active tab"),
        ("ember", ArchColor.ember, "Premium, and nothing else"),
        ("verdigris", ArchColor.verdigris, "Connection only")
    ]
    return HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            VStack(spacing: 0) {
                ForEach(swatches, id: \.0) { name, color, use in
                    HStack(spacing: ArchSpacing.s) {
                        RoundedRectangle(cornerRadius: ArchRadius.detail)
                            .fill(color)
                            .overlay(
                                RoundedRectangle(cornerRadius: ArchRadius.detail)
                                    .strokeBorder(ArchColor.hairline, lineWidth: 1)
                            )
                            .frame(width: 44, height: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name).archText(.footnote).foregroundStyle(ArchColor.limestone)
                            Text(use).archText(.caption).foregroundStyle(ArchColor.mortar)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, ArchSpacing.s)
                    .padding(.vertical, ArchSpacing.xs)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, ArchSpacing.m)
            .background(ArchColor.night)
            .environment(\.colorScheme, scheme)
        }
    }
}
