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
/// The palette is sand and sea: a warm ground with a cool accent, and the two
/// worlds they describe. Light is paper on a beach in the afternoon; dark is the
/// same shore at night, warm-black rather than blue-black. Depth comes from
/// surface lightness (`night` -> `stone` -> `stoneRaised`), never from drop
/// shadows, in both.
///
/// The warm-ground-cool-accent arrangement is the point, and it is the opposite
/// of the terracotta-on-candlelight palette this replaced. Almost everything the
/// app draws sits next to a photograph of a person, and a warm accent competes
/// with skin tones a few pixels away; a deep teal does not. The paper stays warm,
/// so the app does not go clinical, and faces remain the warmest thing on screen.
enum ArchColor {

    // MARK: Surfaces

    /// App background. Warm sand by day; at night a near-black with green in it,
    /// a step below the card surface so a card can sit above it without a border.
    static let night = Color(light: 0xF6F1E8, dark: 0x141A18)

    /// Cards, sheets, incoming message bubbles. A white warmed just off the page
    /// by day, and the shore's own dark by night.
    static let stone = Color(light: 0xFFFDF9, dark: 0x1E2624)

    /// Elevated surfaces, pressed states, tab bar, outgoing bubbles.
    static let stoneRaised = Color(light: 0xECE3D4, dark: 0x28322F)

    // MARK: Ink

    /// Primary text. A near-black with a little green in it on paper, and a
    /// paper-white at night — never pure black, never pure white.
    static let limestone = Color(light: 0x1E2621, dark: 0xEEF2EC)

    /// Secondary text, inactive icons, dividers. Warm grey in both worlds, held
    /// above 5:1 against its own background so a caption is never a guess.
    static let mortar = Color(light: 0x6A665E, dark: 0x98A29A)

    // MARK: Accents

    /// Deep teal. The only colour that invites action: the primary button, every
    /// active tab, the slider, and the mark itself.
    ///
    /// Dark by day (8.0:1 on sand) and lifted at night, the same move a photograph
    /// makes when the light changes. Being this dark is what lets the mark wear it:
    /// a mid-saturation accent on a brand mark reads as a control that does not
    /// respond, which is why the mark used to be drawn in ink instead.
    static let lamp = Color(light: 0x13615E, dark: 0x5FAFA6)

    /// Clay. The second accent, and it has exactly one job: the recommended plan
    /// on the paywall.
    ///
    /// It used to light the Premium tab instead, which made one tab in a bar of
    /// four a different colour — a real distinction (the thing you can buy, against
    /// the things you do) that read as a broken tab. So it moved to the only place
    /// the distinction is useful: the plan Arch suggests. The button beside it stays
    /// `lamp`, because subscribing is an action, and a clay sell with a clay button
    /// would be the accent arguing with itself.
    static let ember = Color(light: 0xA2622F, dark: 0xD3904F)

    /// Marram green. Appears only when two people have connected. If it shows up
    /// as decoration anywhere, it is wrong.
    ///
    /// Held a clear step to the green side of `lamp` in hue and lighter in tone,
    /// because two colours that mean different things must differ in more than
    /// hue — a teal accent and a teal-green connection colour would be one colour
    /// to most people, and to all colour-blind readers.
    static let verdigris = Color(light: 0x52795F, dark: 0x86AD90)

    // MARK: Ink on an accent

    /// What text and glyphs become when they sit **on** `lamp`.
    ///
    /// It inverts between the two worlds, and that is on purpose: the deep teal of
    /// day carries pale ink at 8:1, the lifted teal of night carries dark ink at
    /// 7:1. Chasing one constant ink across both would fail one of them. This is
    /// the only token that flips its own polarity.
    static let onLamp = Color(light: 0xF4FBF8, dark: 0x10201E)

    // MARK: Derived

    /// The rule between two rows of a list. Only there: bars have no edge line
    /// any more, and cards are not outlined. Faint enough to be felt as a gap
    /// rather than seen as a line.
    static let hairline = mortar.opacity(0.10)

    /// The fill of the quiet (pass / secondary) button and the add-an-interest
    /// chip. A wash where there used to be an outline.
    static let quietFill = mortar.opacity(0.12)

    /// The crop frame's edge — the one outline left, because it is a mask and
    /// the reader needs to see exactly where it cuts.
    static let quietBorder = mortar.opacity(0.28)

    /// Pressed-state wash over any surface.
    static let pressed = mortar.opacity(0.10)

    /// Scrim behind full-screen modals.
    static let scrim = Color(light: 0x1E2621, dark: 0x080E0D).opacity(0.62)

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
