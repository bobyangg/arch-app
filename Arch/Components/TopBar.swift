import SwiftUI

/// The lock-up at the top of each tab, and nothing else.
///
/// On the page rather than on a bar: the mark in `lamp` and the word in
/// `limestone`, as the brand board locks them up, on the same `night` as the
/// screen, with no surface and no line. Pushed screens do not carry it: a thread
/// or a profile has somebody else's name at the top, and the brand has no
/// business above that.
///
/// Horizontal, unlike `ArchWordmark`: 52pt is not tall enough to stack the mark
/// over the word, and the appearance specimen already locks it up this way.
struct TopBar: View {
    /// A step above the minimum tap target: tall enough that the lock-up has air
    /// above and below it, not so tall that it reads as a masthead.
    static let height: CGFloat = 52

    private let markWidth: CGFloat = 24
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
                .font(ArchTypography.font(.frauncesDisplaySemiBold, size: 22))
                .foregroundStyle(ArchColor.limestone)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Arch")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A scroll with the lock-up above it, which goes away as you read down and
/// comes back the moment you scroll up.
///
/// The bar collapses rather than sliding off: its height goes to nothing and
/// the scroll takes the room, so reading gains a line rather than looking at a
/// gap where the brand was. Any upward scroll returns it — not only reaching the
/// top — because "I want the top of the page" and "I want to see where I am" are
/// the same gesture on a phone and the app should not make people finish it.
///
/// `pinned` is for the one tab whose own header stays put (You): the lock-up
/// collapses above it while it holds.
struct TopBarScroll<Pinned: View, Content: View>: View {
    @ViewBuilder let pinned: () -> Pinned
    @ViewBuilder let content: () -> Content

    @State private var isHidden = false
    @State private var lastOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far a scroll has to travel, in one direction, before the bar reacts.
    /// Below this a thumb resting on the screen would flicker it. An instance
    /// property, because a generic type cannot hold a static stored one.
    private let threshold: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
                .frame(height: isHidden ? 0 : TopBar.height, alignment: .bottom)
                .clipped()
                .opacity(isHidden ? 0 : 1)

            pinned()

            ScrollView {
                content()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: proxy.frame(in: .named("archScroll")).minY
                            )
                        }
                    )
            }
            .coordinateSpace(name: "archScroll")
            .scrollIndicators(.hidden)
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                track(offset)
            }
        }
        .animation(ArchMotion.honouring(reduceMotion, ArchMotion.glass), value: isHidden)
    }

    private func track(_ offset: CGFloat) {
        defer { lastOffset = offset }
        // At the top, or pulled past it, the bar is always there.
        if offset >= -TopBar.height {
            isHidden = false
            return
        }
        let delta = offset - lastOffset
        if delta < -threshold {
            isHidden = true
        } else if delta > threshold {
            isHidden = false
        }
    }
}

extension TopBarScroll where Pinned == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content) {
        self.init(pinned: { EmptyView() }, content: content)
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview("Top bar over a scroll") {
    TopBarScroll {
        VStack(spacing: ArchSpacing.cardGap) {
            ForEach(0..<8) { index in
                PhotoPlaceholder(toneIndex: index)
                    .aspectRatio(PhotoCard.aspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: ArchRadius.photo, style: .continuous))
            }
        }
        .padding(ArchSpacing.screenMargin)
    }
    .background(ArchColor.night)
}
