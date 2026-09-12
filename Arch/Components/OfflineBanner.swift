import SwiftUI

/// No connection, said once, at the top of everything.
///
/// It sits above the tabs rather than inside a screen because losing a connection
/// is not something that happens to the roster or to messages — it happens to the
/// app, and repeating it per screen would be four ways of saying one thing.
///
/// **It pushes the app down rather than floating over it.** A bar that overlays
/// content covers whatever you were reading at the moment you least want to lose
/// your place, and this is information, not an interruption.
///
/// No red and no icon. Arch has no red, and being offline is a fact about a train
/// tunnel rather than a fault anybody committed. The second line is the useful
/// half: it says what still works.
struct OfflineBanner: View {
    var body: some View {
        VStack(spacing: ArchSpacing.xxs) {
            Text("No connection")
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)

            Text("You can read what is already here. Anything you write waits until Arch is back.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.vertical, ArchSpacing.s)
        .background(ArchColor.stoneRaised)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No connection. You can read what is already here.")
    }
}

#Preview("Offline") {
    VStack(spacing: 0) {
        OfflineBanner()
        Spacer()
    }
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
