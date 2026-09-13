import SwiftUI

/// The 4pt spacing grid. Arch is deliberately under-filled compared to a typical
/// feed app — roughly one card per thumb-scroll — so the larger steps get used
/// more than they would elsewhere.
enum ArchSpacing {
    /// 4 — inside a chip, between a label and its icon.
    static let xxs: CGFloat = 4
    /// 8 — tight stacks.
    static let xs: CGFloat = 8
    /// 12 — chip runs, list row internals.
    static let s: CGFloat = 12
    /// 16 — related blocks.
    static let m: CGFloat = 16
    /// 20 — the horizontal screen margin.
    static let l: CGFloat = 20
    /// 24 — padding inside prompt cards and sheets.
    static let xl: CGFloat = 24
    /// 32 — between cards in the profile scroll.
    static let xxl: CGFloat = 32
    /// 48 — between sections, and before the pass button.
    static let xxxl: CGFloat = 48

    /// Horizontal margin on every screen.
    static let screenMargin: CGFloat = 20
    /// Vertical gap between the alternating photo and prompt cards.
    static let cardGap: CGFloat = 32
    /// Gap before a new section of a screen.
    static let sectionGap: CGFloat = 48

    /// Divider and border weight. A real hairline, not 1pt.
    static let hairline: CGFloat = 0.5
    /// Stroke weight shared by every custom glyph, so the icon set reads as one hand.
    static let glyphStroke: CGFloat = 1.75
    /// The minimum tappable square, per HIG.
    static let minimumTapTarget: CGFloat = 44
}

#Preview("Spacing grid") {
    let steps: [(String, CGFloat)] = [
        ("xxs", ArchSpacing.xxs), ("xs", ArchSpacing.xs), ("s", ArchSpacing.s),
        ("m", ArchSpacing.m), ("l", ArchSpacing.l), ("xl", ArchSpacing.xl),
        ("xxl", ArchSpacing.xxl), ("xxxl", ArchSpacing.xxxl)
    ]
    return VStack(alignment: .leading, spacing: ArchSpacing.s) {
        ForEach(steps, id: \.0) { name, value in
            HStack(spacing: ArchSpacing.s) {
                Text(name)
                    .archText(.caption)
                    .foregroundStyle(ArchColor.mortar)
                    .frame(width: 40, alignment: .leading)
                Rectangle()
                    .fill(ArchColor.lamp)
                    .frame(width: value, height: 12)
                Text("\(Int(value))")
                    .archText(.caption)
                    .foregroundStyle(ArchColor.mortar)
            }
        }
    }
    .padding(ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
