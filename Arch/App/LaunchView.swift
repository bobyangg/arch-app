import SwiftUI

/// The launch screen.
///
/// The mark draws itself once — the piers rise, then the deck lands across them,
/// which is the order a bridge is actually built in. Then the word arrives and the
/// app opens. It happens once per launch and never repeats.
///
/// Under Reduce Motion the mark is simply there, held briefly, with nothing drawn.
struct LaunchView: View {
    let onFinish: () -> Void

    @State private var drawn: CGFloat = 0
    @State private var wordmarkOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ArchColor.night
                .ignoresSafeArea()

            ArchWordmark(markWidth: 104, drawn: drawn, wordOpacity: wordmarkOpacity)
        }
        .task { await open() }
    }

    private func open() async {
        if reduceMotion {
            drawn = 1
            wordmarkOpacity = 1
            try? await Task.sleep(for: .milliseconds(600))
            onFinish()
            return
        }

        withAnimation(ArchMotion.launchDraw) { drawn = 1 }
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(ArchMotion.standard) { wordmarkOpacity = 1 }
        try? await Task.sleep(for: .milliseconds(750))
        withAnimation(ArchMotion.standard) { onFinish() }
    }
}

#Preview("Launch, dark") {
    LaunchView(onFinish: {})
        .preferredColorScheme(.dark)
}

#Preview("Launch, light") {
    LaunchView(onFinish: {})
        .preferredColorScheme(.light)
}
