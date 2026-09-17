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

    /// A failure that happened after Apple handed over, so the flow rather than
    /// this screen is the one that knows about it -- the register call, or the
    /// network being gone. Shown in the same place and the same register as one
    /// from the button itself.
    var externalProblem: String?
    /// Called once an emailed code has been accepted and a session exists. Apple
    /// hands over a name and a relay address; email hands over neither, so
    /// onboarding asks for the name on the very next screen either way.
    var onEmailSignIn: ((String) -> Void)?

    @State private var problem: String?
    @State private var isUsingEmail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            ArchWordmark(markWidth: 84)

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

                // **The email door is closed for v1**, not removed. Everything
                // behind it still exists and compiles -- `EmailSignInSheet`, the
                // OTP calls, the sheet below -- because the only thing missing is
                // an SMTP provider, and putting the button back is one line.
                //
                // Shut rather than left open because Supabase will not send a code
                // without custom SMTP, so the button led to a screen that asked for
                // a code nobody would ever receive.

                Text(problem ?? externalProblem ?? "Arch does not post anything, and never sees your Apple password. Your email stays hidden if you want it to.")
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
        .sheet(isPresented: $isUsingEmail) {
            EmailSignInSheet(
                onSignedIn: { address in
                    isUsingEmail = false
                    onEmailSignIn?(address)
                },
                // Same rule as the Apple button above: which path appears is
                // decided by whether there is a backend to sign in to, not by a
                // flag somebody has to remember to flip.
                demoMode: !ArchConfig.isConfigured
            )
        }
    }
}

#Preview("Welcome") {
    OnboardingWelcome(onSignIn: { _ in }, demoSignIn: {})
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}
