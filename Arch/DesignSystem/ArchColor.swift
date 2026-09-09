import SwiftUI

/// Every colour in Arch.
///
/// Views reference these tokens and nothing else — the hex initialiser below is
/// deliberately `fileprivate`, so a raw hex value cannot be written anywhere
/// outside this file without the compiler objecting.
///
/// Depth in Arch comes from surface lightness (`night` -> `stone` -> `stoneRaised`),
/// never from drop shadows.
enum ArchColor {

    // MARK: Surfaces

    /// #0F1319 — app background. Blue-leaning slate, deliberately not a tinted near-black.
    static let night = Color(hex: 0x0F1319)

    /// #171C24 — cards, sheets, incoming message bubbles.
    static let stone = Color(hex: 0x171C24)

    /// #212832 — elevated surfaces, pressed states, tab bar, outgoing bubbles.
    static let stoneRaised = Color(hex: 0x212832)

    // MARK: Ink

    /// #EDE7DD — primary text. Warm off-white, never pure white.
    static let limestone = Color(hex: 0xEDE7DD)

    /// #8D949E — secondary text, inactive icons, dividers.
    static let mortar = Color(hex: 0x8D949E)

    // MARK: Accents

    /// #F0A44B — sodium lamplight. The only colour that invites action:
    /// the like affordance, the active tab, the primary button, premium.
    static let lamp = Color(hex: 0xF0A44B)

    /// #4E8C7D — oxidised copper. Appears only when two people have connected.
    /// If verdigris shows up as decoration anywhere, it is wrong.
    ///
    /// Contrast against `night` is 4.8:1 — passing but thin — so verdigris is used
    /// for graphics and type at 24pt and above. Body copy stays `limestone`.
    static let verdigris = Color(hex: 0x4E8C7D)

    // MARK: Derived

    /// Hairline dividers and the tab bar's top edge.
    static let hairline = mortar.opacity(0.12)

    /// Border of the quiet (pass / secondary) button.
    static let quietBorder = mortar.opacity(0.20)

    /// Pressed-state wash over any surface.
    static let pressed = limestone.opacity(0.06)

    /// Scrim behind full-screen modals.
    static let scrim = night.opacity(0.72)

    /// Outline of the segment the reader is currently on.
    static let lampQuiet = lamp.opacity(0.45)
}

private extension Color {
    /// Not available outside ArchColor.swift — that is the point.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

#Preview("Palette") {
    let swatches: [(String, Color, String)] = [
        ("night", ArchColor.night, "App background"),
        ("stone", ArchColor.stone, "Cards, sheets, incoming bubbles"),
        ("stoneRaised", ArchColor.stoneRaised, "Elevated, tab bar, outgoing bubbles"),
        ("limestone", ArchColor.limestone, "Primary text"),
        ("mortar", ArchColor.mortar, "Secondary text, dividers"),
        ("lamp", ArchColor.lamp, "Action, active tab, premium"),
        ("verdigris", ArchColor.verdigris, "Connection only")
    ]
    return VStack(spacing: 0) {
        ForEach(swatches, id: \.0) { name, color, use in
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: ArchRadius.detail).fill(color).frame(width: 56, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundStyle(ArchColor.limestone)
                    Text(use).font(.footnote).foregroundStyle(ArchColor.mortar)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}

// MARK: - Quarry tones

extension ArchColor {

    /// A stand-in for a photograph. Photos in this build are drawn, not fetched,
    /// so they need material that reads as stone lit from above without ever
    /// competing with `lamp` or `verdigris`.
    ///
    /// Each tone carries a second value four to six percent darker. That is the
    /// whole gradient: enough to read as a lit surface, not enough to read as
    /// decoration. If it ever looks like a gradient, flatten it to `top` alone.
    struct Material: Hashable {
        let name: String
        let top: Color
        let bottom: Color
    }

    static let materials: [Material] = [
        Material(name: "slate", top: Color(hex: 0x29313C), bottom: Color(hex: 0x232A34)),
        Material(name: "clay",  top: Color(hex: 0x3B322A), bottom: Color(hex: 0x332B24)),
        Material(name: "moss",  top: Color(hex: 0x2B3733), bottom: Color(hex: 0x25302C)),
        Material(name: "ash",   top: Color(hex: 0x333941), bottom: Color(hex: 0x2C3138)),
        Material(name: "ember", top: Color(hex: 0x443329), bottom: Color(hex: 0x3B2C23)),
        Material(name: "linen", top: Color(hex: 0x4A4640), bottom: Color(hex: 0x413E38))
    ]

    static func material(_ index: Int) -> Material {
        materials[((index % materials.count) + materials.count) % materials.count]
    }
}
