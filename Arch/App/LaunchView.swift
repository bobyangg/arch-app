import SwiftUI

/// How the bridge gets built on the way in.
///
/// Three sequences, one drawn at random for each cold start, so opening the app
/// is not the same forty frames every morning. All three end on the same
/// lock-up -- the mark over the word -- and all three take about the same time,
/// so whichever one comes up, the app opens when it always opens.
enum LaunchVariant: CaseIterable {
    /// The mark draws itself: the piers rise, then the deck lands across them.
    case drawn
    /// The five stones of the arch are laid, springers first and the keystone
    /// last, which is the order a mason works in. Then the arch gives way to
    /// the mark.
    case laid
    /// The mark arrives in pieces: the piers rise into place from below, and the
    /// deck comes down and settles on them.
    case raised

    static func random() -> LaunchVariant {
        allCases.randomElement() ?? .drawn
    }
}

/// The launch screen.
///
/// The bridge builds itself once -- one of three ways, see `LaunchVariant` -- and
/// then the app opens. It happens once per launch and never repeats. It is also
/// what plays between signing in and the roster: the first roster is loading
/// behind it, and a bridge going up is a better thing to watch than a spinner.
///
/// Under Reduce Motion the lock-up is simply there, held briefly, with nothing
/// drawn, whichever variant was picked.
struct LaunchView: View {
    let onFinish: () -> Void

    @State private var variant: LaunchVariant

    // The mark drawing itself, and the word arriving. Shared by all three.
    @State private var drawn: CGFloat = 0
    @State private var wordOpacity: Double = 0

    // Laid: how many stones are down, and how far the arch has given way to
    // the mark.
    @State private var stonesLaid = 0
    @State private var stonesOpacity: Double = 1
    @State private var markOpacity: Double = 0

    // Raised: where the pieces are, as offsets from their final place.
    @State private var pierRise: CGFloat = 1
    @State private var deckDrop: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let markWidth: CGFloat = 104
    /// The stone arch is drawn a little wider than the mark it becomes, so the
    /// two read as the same size when one gives way to the other.
    private var archWidth: CGFloat { markWidth * 1.3 }
    private var stroke: CGFloat { max(2, markWidth * 0.13) }
    private var band: ArchBand { ArchBand(count: 5, thickness: 18) }

    /// `nil` picks one at random, which is what the app does. Previews and tests
    /// name one so they get the one they asked for.
    init(variant: LaunchVariant? = nil, onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        _variant = State(initialValue: variant ?? .random())
    }

    var body: some View {
        ZStack {
            ArchColor.night
                .ignoresSafeArea()

            switch variant {
            case .drawn:
                ArchWordmark(markWidth: markWidth, drawn: drawn, wordOpacity: wordOpacity)
            case .laid:
                laid
            case .raised:
                raised
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Arch")
        .accessibilityIdentifier("launch.\(variant)")
        .task { await open() }
    }

    // MARK: The three

    /// Stones over the word, and the mark waiting underneath to take over.
    private var laid: some View {
        VStack(spacing: markWidth * 0.16) {
            ZStack {
                stones
                    .opacity(stonesOpacity)
                ArchMark(lineWidth: stroke)
                    .stroke(
                        ArchColor.lamp,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: markWidth, height: markWidth * ArchMark.aspect)
                    .opacity(markOpacity)
            }
            .frame(width: archWidth, height: band.height(forWidth: archWidth))

            word
        }
    }

    /// Springers first, then the next pair in, then the keystone: 0 and 4, 1 and
    /// 3, then 2. Each stone comes down a little way into its seat.
    private var stones: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    let isDown = Self.layingOrder(of: index) < stonesLaid
                    band.segment(index, in: geometry.size)
                        .fill(ArchColor.lamp)
                        .opacity(isDown ? 1 : 0)
                        .offset(y: isDown ? 0 : -12)
                }
            }
        }
    }

    /// The round in which stone `index` is laid: the two springers in the first,
    /// the keystone in the last.
    private static func layingOrder(of index: Int) -> Int {
        min(index, 4 - index)
    }

    /// The piers below their place and the deck above it, until each arrives.
    private var raised: some View {
        VStack(spacing: markWidth * 0.16) {
            ZStack {
                piece(.leftPier)
                    .offset(y: pierRise * markWidth * 0.30)
                    .opacity(1 - Double(pierRise))
                piece(.rightPier)
                    .offset(y: pierRise * markWidth * 0.30)
                    .opacity(1 - Double(pierRise))
                piece(.deck)
                    .offset(y: -deckDrop * markWidth * 0.34)
                    .opacity(1 - Double(deckDrop))
            }
            .frame(width: markWidth, height: markWidth * ArchMark.aspect)

            word
        }
    }

    private func piece(_ parts: ArchMarkParts) -> some View {
        ArchMark(lineWidth: stroke, parts: parts)
            .stroke(
                ArchColor.lamp,
                style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
            )
    }

    /// The same word `ArchWordmark` sets, metered the same way.
    private var word: some View {
        Text("arch")
            .font(ArchTypography.font(.frauncesDisplaySemiBold, size: markWidth * 0.42))
            .foregroundStyle(ArchColor.limestone)
            .opacity(wordOpacity)
    }

    // MARK: Playing it

    private func open() async {
        if reduceMotion {
            settle()
            try? await Task.sleep(for: .milliseconds(600))
            onFinish()
            return
        }

        switch variant {
        case .drawn:
            withAnimation(ArchMotion.launchDraw) { drawn = 1 }
            try? await Task.sleep(for: .milliseconds(650))

        case .laid:
            // Three rounds of stones, a beat apart, then the arch gives way.
            for round in 1...3 {
                withAnimation(ArchMotion.stoneLands) { stonesLaid = round }
                try? await Task.sleep(for: .milliseconds(220))
            }
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(ArchMotion.standard) {
                stonesOpacity = 0
                markOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(80))

        case .raised:
            withAnimation(ArchMotion.pierRises) { pierRise = 0 }
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(ArchMotion.deckLands) { deckDrop = 0 }
            try? await Task.sleep(for: .milliseconds(380))
        }

        withAnimation(ArchMotion.standard) { wordOpacity = 1 }
        try? await Task.sleep(for: .milliseconds(750))
        withAnimation(ArchMotion.standard) { onFinish() }
    }

    /// Everything in its final place, without the journey.
    private func settle() {
        drawn = 1
        wordOpacity = 1
        stonesLaid = 3
        stonesOpacity = 0
        markOpacity = 1
        pierRise = 0
        deckDrop = 0
    }
}

#Preview("Drawn") {
    LaunchView(variant: .drawn, onFinish: {})
        .preferredColorScheme(.dark)
}

#Preview("Laid") {
    LaunchView(variant: .laid, onFinish: {})
        .preferredColorScheme(.dark)
}

#Preview("Raised") {
    LaunchView(variant: .raised, onFinish: {})
        .preferredColorScheme(.light)
}
