import SwiftUI

/// The first thing a stranger sees.
///
/// It exists because opening an app straight onto "enter your phone number" asks
/// for something before explaining what the thing is. One screen, the premise, one
/// button. No progress rule — nothing has been asked yet, so there is no progress
/// to report.
struct OnboardingWelcome: View {
    /// Called once Apple has said who somebody is. Whether they are new is the
    /// server's answer, not this screen's.
    let onSignIn: (AppleIdentity) -> Void
    /// Design-only: the real button needs an entitlement and a signed build, so
    /// previews and the design build take this path instead.
    var demoSignIn: (() -> Void)?

    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            ArchMark(lineWidth: 4)
                .stroke(
                    ArchColor.lamp,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 84, height: 76)

            Text("Arch")
                .archText(.display)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.m)

            Spacer()

            Text(MockData.onboardingHeadline)
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)

            Text(MockData.onboardingBody)
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.s)

            Spacer()

            VStack(spacing: ArchSpacing.xs) {
                if let demoSignIn {
                    ArchButton(title: "Continue with Apple", action: demoSignIn)
                } else {
                    AppleSignInButton { outcome in
                        switch outcome {
                        case .newAccount(let identity), .existingAccount(let identity):
                            problem = nil
                            onSignIn(identity)
                        case .cancelled:
                            // Changing your mind is not an error and does not earn
                            // a line of red text.
                            problem = nil
                        case .failed(let message):
                            problem = message
                        case .removed:
                            problem = nil
                        }
                    }
                }

                Text(problem ?? "Arch does not post anything, and never sees your Apple password. Your email stays hidden if you want it to.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, ArchSpacing.xxs)
            }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.vertical, ArchSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview("Welcome") {
    OnboardingWelcome(onSignIn: { _ in }, demoSignIn: {})
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}
