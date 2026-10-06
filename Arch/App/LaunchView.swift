import SwiftUI

/// The launch screen.
///
/// The bridge draws itself once -- the piers rise, the span is turned between
/// them, the deck goes across the lot -- and then the app opens. It happens once
/// per launch and never repeats. It is also what plays between signing in and
/// the roster: the first roster is loading behind it, and a bridge going up is a
/// better thing to watch than a spinner.
///
/// There used to be a second sequence, picked at random, in which the piers rose
/// into place from below and the deck dropped onto them with a bounce. It went:
/// a deck falling onto its supports is the one thing a bridge must never look
/// like it does, and a launch that sometimes did something different was a
/// launch that sometimes looked wrong. One sequence, every time.
///
/// Under Reduce Motion the lock-up is simply there, held briefly, with nothing
/// drawn.
struct LaunchView: View {
    let onFinish: () -> Void

    // The mark drawing itself, and the word arriving.
    @State private var drawn: CGFloat = 0
    @State private var wordOpacity: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let markWidth: CGFloat = 104

    var body: some View {
        ZStack {
            ArchColor.night
                .ignoresSafeArea()

            ArchWordmark(markWidth: markWidth, drawn: drawn, wordOpacity: wordOpacity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Arch")
        .accessibilityIdentifier("launch")
        .task { await open() }
    }

    // MARK: Playing it

    private func open() async {
        if reduceMotion {
            drawn = 1
            wordOpacity = 1
            try? await Task.sleep(for: .milliseconds(600))
            onFinish()
            return
        }

        withAnimation(ArchMotion.launchDraw) { drawn = 1 }
        try? await Task.sleep(for: .milliseconds(650))

        withAnimation(ArchMotion.standard) { wordOpacity = 1 }
        try? await Task.sleep(for: .milliseconds(750))
        withAnimation(ArchMotion.standard) { onFinish() }
    }
}

#Preview("Launch") {
    LaunchView(onFinish: {})
        .preferredColorScheme(.dark)
}
