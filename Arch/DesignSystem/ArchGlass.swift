import SwiftUI

/// Glass: what every bar, every open slot and every selection is made of now.
///
/// Depth in Arch still comes from surface lightness. What changed is the edge. A
/// bar used to carry a hairline along it; now it is a plain block of `stoneRaised`
/// with no line at all — the step in lightness is the edge. Sheets are glass, so
/// the screen they came from shows through. Cards that used to be outlined are
/// filled instead, and a selection is a wash of colour with a soft glow rather
/// than a one-point ring.
///
/// Two rules keep this from turning into a lens flare. **Glass is for chrome and
/// for state, never for content**: a prompt card is paper, because the writing on
/// it is the point, and a photograph is a photograph. And **the glow is the only
/// shadow in the app**, it is always the tint of the thing it marks, and it never
/// appears at rest — it says "chosen", not "elevated".
enum ArchGlass {
    /// How much of `stone` sits over the blur in a frosted card.
    static let tint: Double = 0.58

    /// How much of `stone` sits over the blur in a sheet.
    static let sheetTint: Double = 0.72

    /// The frosted pill that sits behind the active tab.
    static let pillRadius: CGFloat = 14
    static let pillWash: Double = 0.07

    /// The wash and the glow of a selected card.
    static let selectionWash: Double = 0.10
    static let selectionGlow: Double = 0.26
    static let selectionRadius: CGFloat = 14
}

extension View {

    /// A bar: a solid block of `stoneRaised`, extended under the safe area on
    /// the edge it sits against, with no line at its edge. The step up from the
    /// page is what separates it; a hairline on top of that was saying it twice.
    func archBar(_ edge: Edge) -> some View {
        background(ArchColor.stoneRaised, ignoresSafeAreaEdges: Edge.Set(edge))
    }

    /// A sheet made of the same glass as the bars: what is behind it shows
    /// through the top of it, softly, so it arrives as part of the screen it
    /// came from rather than as a new one.
    func archSheetBackground() -> some View {
        presentationBackground {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(ArchColor.stone.opacity(ArchGlass.sheetTint))
            }
        }
    }

    /// A frosted card. For chrome-like cards — an open slot, a specimen — and
    /// not for anything with writing on it.
    func archGlassCard(radius: CGFloat = ArchRadius.card) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(ArchColor.stone.opacity(ArchGlass.tint))
                )
        }
    }

    /// Selection, in place of a ring: a wash of the tint over the card and a soft
    /// glow of it around the card, both animated in and out.
    ///
    /// `lamp` where choosing is the start of an action — a photo or an answer to
    /// write about. `limestone` where it is only a choice among peers, like a
    /// plan or a question, so the accent is not spent on a list.
    func archSelected(
        _ isSelected: Bool,
        radius: CGFloat,
        tint: Color = ArchColor.lamp
    ) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint.opacity(isSelected ? ArchGlass.selectionWash : 0))
                    .allowsHitTesting(false)
            )
            .shadow(
                color: tint.opacity(isSelected ? ArchGlass.selectionGlow : 0),
                radius: ArchGlass.selectionRadius
            )
            .animation(ArchMotion.glass, value: isSelected)
    }
}

#Preview("Glass") {
    ZStack {
        // Something busy to see the blur against.
        VStack(spacing: 0) {
            ForEach(0..<6) { index in
                PhotoPlaceholder(toneIndex: index)
            }
        }
        .ignoresSafeArea()

        VStack(spacing: 0) {
            TopBar()
            Spacer()
            VStack(spacing: ArchSpacing.m) {
                Text("Chosen")
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
                    .padding(ArchSpacing.m)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous).fill(ArchColor.stone))
                    .archSelected(true, radius: ArchRadius.card)
                Text("A frosted card")
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
                    .padding(ArchSpacing.m)
                    .frame(maxWidth: .infinity)
                    .archGlassCard()
            }
            .padding(ArchSpacing.screenMargin)
            Spacer()
            TabBar(selection: .constant(.daily), unreadCount: 2)
        }
    }
}
