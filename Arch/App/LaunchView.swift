import SwiftUI

/// The launch screen.
///
/// The mark draws itself once — the span rises, then the deck lands across it,
/// which is the order an arch bridge is actually built in. Then the wordmark
/// arrives and the app opens. It happens once per launch and never repeats.
///
/// Under Reduce Motion the mark is simply there, held briefly, with nothing drawn.
struct LaunchView: View {
    let onFinish: () -> Void

    @State private var drawn: CGFloat = 0
    @State private var wordmarkOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let stroke: CGFloat = 4

    var body: some View {
        ZStack {
            ArchColor.night
                .ignoresSafeArea()

            VStack(spacing: ArchSpacing.l) {
                ArchMark(lineWidth: stroke, trim: drawn)
                    .stroke(
                        ArchColor.lamp,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 96, height: 87)

                Text("Arch")
                    .archText(.display)
                    .foregroundStyle(ArchColor.limestone)
                    .opacity(wordmarkOpacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Arch")
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

#Preview("Launch") {
    LaunchView(onFinish: {})
        .preferredColorScheme(.dark)
}
