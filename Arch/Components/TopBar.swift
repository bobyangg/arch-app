import SwiftUI

/// The bar across the top of each tab: the lock-up at the left, and nothing else.
///
/// It is the tab bar's twin — the same surface, the same hairline — so a root
/// screen sits between two pieces of chrome that read as one frame. Pushed screens
/// do not carry it: a thread or a profile has somebody else's name at the top, and
/// the brand has no business above that.
///
/// Horizontal, unlike `ArchWordmark`: 44pt is not tall enough to stack the mark
/// over the word, and the appearance specimen already locks it up this way.
struct TopBar: View {
    /// A step above the minimum tap target: tall enough that the lock-up has air
    /// above and below it, not so tall that it reads as a masthead.
    static let height: CGFloat = 52

    private let markWidth: CGFloat = 30
    private var stroke: CGFloat { markWidth * 0.13 }

    var body: some View {
        HStack(spacing: ArchSpacing.xs) {
            ArchMark(lineWidth: stroke)
                .stroke(
                    ArchColor.lamp,
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
                )
                .frame(width: markWidth, height: markWidth * ArchMark.aspect)

            Text("arch")
                .font(ArchTypography.font(.frauncesDisplaySemiBold, size: 25))
                .foregroundStyle(ArchColor.limestone)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .frame(height: Self.height)
        .background(ArchColor.stoneRaised.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ArchColor.hairline)
                .frame(height: ArchSpacing.hairline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Arch")
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Top bar") {
    VStack(spacing: 0) {
        TopBar()
        Spacer()
        TabBar(selection: .constant(.daily), unreadCount: 2)
    }
    .background(ArchColor.night)
}
