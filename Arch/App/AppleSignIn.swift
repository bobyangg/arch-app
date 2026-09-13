import AuthenticationServices
import SwiftUI

/// Who Apple says you are.
///
/// **`userID` is the account key**, and the thing a ban hangs on. It is stable for
/// this app and this Apple ID forever, and it is not the Apple ID itself — you
/// cannot work backwards from it to a person.
///
/// **`name` and `email` arrive only on the very first authorization.** Delete the
/// app, reinstall, sign in again, and Apple sends the id and nothing else. If the
/// server does not persist them the first time, they are gone — which is the single
/// most common way this integration is got wrong.
///
/// The email is usually a private relay address. That is fine, and better than
/// fine: Arch never shows it to anybody, and a relay means a leak of the user table
/// does not hand anybody a real inbox.
struct AppleIdentity: Hashable {
    let userID: String
    let name: String?
    let email: String?
    /// Apple's signed token. The client is not trusted to say who it is — the
    /// server verifies this against Apple's public keys before believing any of the
    /// fields above.
    let identityToken: Data?
}

/// What happened when somebody tried to sign in.
enum SignInOutcome {
    /// No account for this Apple id. Straight into building a profile.
    case newAccount(AppleIdentity)
    /// There is already an account. Straight into the app — no onboarding, because
    /// signing back in is not signing up.
    case existingAccount(AppleIdentity)
    /// The account exists and is no longer usable.
    case removed(Removal)
    /// They changed their mind. Not an error and not worth a message.
    case cancelled
    case failed(String)
}

/// The Apple button, which is the one piece of borrowed chrome in the app.
///
/// Apple's Human Interface Guidelines fix its shape, its wording and its colours,
/// and the Review Guidelines mean you do not get to restyle it. Everything else in
/// Arch was drawn from scratch to avoid looking like somebody else's app; this is
/// the exception, and the price of not sending an SMS to every person who opens the
/// app.
///
/// It is held to 52pt and the app's control radius so it at least sits on the grid.
struct AppleSignInButton: View {
    let onOutcome: (SignInOutcome) -> Void

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            // Asked for every time; sent by Apple only the first time.
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            onOutcome(Self.outcome(from: result))
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous))
        .accessibilityLabel("Continue with Apple")
    }

    /// Maps Apple's result into something the app can act on.
    ///
    /// Whether the account is new is not knowable here — only the server knows
    /// whether it has seen this `userID` before — so this always reports
    /// `.newAccount` and the caller corrects it once the server answers.
    static func outcome(from result: Result<ASAuthorization, Error>) -> SignInOutcome {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential
                    as? ASAuthorizationAppleIDCredential else {
                return .failed("Apple sent something Arch did not understand.")
            }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            return .newAccount(
                AppleIdentity(
                    userID: credential.user,
                    name: name.isEmpty ? nil : name,
                    email: credential.email,
                    identityToken: credential.identityToken
                )
            )

        case .failure(let error):
            if let error = error as? ASAuthorizationError, error.code == .canceled {
                return .cancelled
            }
            // Never the underlying message. Apple's errors are for a log, not for
            // somebody standing at the front door of an app they have not joined.
            return .failed("Arch could not reach Apple just now.")
        }
    }
}

#Preview("The button on night") {
    VStack(spacing: ArchSpacing.s) {
        AppleSignInButton { _ in }
        ArchButton(title: "For comparison", kind: .quiet) {}
    }
    .padding(ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
