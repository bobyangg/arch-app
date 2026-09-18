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
/// The bar sits *over* the scroll rather than above it, and slides up out of the
/// way; the scroll itself never changes shape. The first version collapsed the
/// bar's height and let the scroll take the room, which read well and never once
/// worked on a phone: the scroll it was measuring moved *because* the bar hid,
/// the measurement moved with it, and the bar was back before a frame was drawn.
/// Now the only thing that moves when the bar goes is the bar.
///
/// The content is padded by the bar's height so that at the top of the page
/// nothing is under it; once you are past that, what is under the bar is the
/// page you were reading, and hiding the bar shows it -- which is the same line
/// gained as before, arrived at without the layout arguing with itself.
///
/// Any upward scroll returns it -- not only reaching the top -- because "I want
/// the top of the page" and "I want to see where I am" are the same gesture on a
/// phone and the app should not make people finish it.
///
/// `pinned` is for the one tab whose own header stays put (You): it rides under
/// the lock-up and takes its place when the lock-up slides away.
struct TopBarScroll<Pinned: View, Content: View>: View {
    @ViewBuilder let pinned: () -> Pinned
    @ViewBuilder let content: () -> Content

    @State private var isHidden = false
    @State private var lastOffset: CGFloat = 0
    /// The bar plus whatever is pinned under it, measured rather than assumed,
    /// because the You header is the height of its own type.
    @State private var chromeHeight: CGFloat = TopBar.height
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far a scroll has to travel, in one direction, before the bar reacts.
    /// Below this a thumb resting on the screen would flicker it. An instance
    /// property, because a generic type cannot hold a static stored one.
    private let threshold: CGFloat = 4

    var body: some View {
        ScrollView {
            content()
                .padding(.top, chromeHeight)
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
        .overlay(alignment: .top) { chrome }
        .onPreferenceChange(ChromeHeightKey.self) { height in
            chromeHeight = height
        }
    }

    /// The lock-up and the pinned header, on the page's own colour so the scroll
    /// passing underneath does not show through them. `night` rather than a
    /// surface: this is not a bar, it is the top of the page holding still.
    private var chrome: some View {
        VStack(spacing: 0) {
            TopBar()
                .opacity(isHidden ? 0 : 1)
                .accessibilityHidden(isHidden)
            pinned()
        }
        .frame(maxWidth: .infinity)
        .background(ArchColor.night, ignoresSafeAreaEdges: .top)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ChromeHeightKey.self, value: proxy.size.height)
            }
        )
        .offset(y: isHidden ? -TopBar.height : 0)
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

private struct ChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = TopBar.height
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
