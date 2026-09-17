import SwiftUI

/// Signing in with an email address.
///
/// **A code, not a password.** Arch has never had one — the Apple path has no
/// password to fall back on either — and adding one here would mean a password
/// field, a reset flow, a strength rule and somewhere to store it, all to identify
/// somebody an emailed code identifies just as well.
///
/// **One door.** An address that has not been here before becomes an account; one
/// that has signs in. There is no sign-up screen and no sign-in screen, so there is
/// no wrong one to pick. That also means this screen never says whether an address
/// already has an account: answering that is an enumeration oracle anybody could
/// point at anybody.
///
/// Two states in one sheet, which is the same shape the rest of Arch uses for a
/// two-step decision. No red anywhere: a mistyped code is a typo, not a hazard.
struct EmailSignInSheet: View {
    /// Called once the code has been accepted and a session exists, with the
    /// address that was verified — onboarding needs it for the account row, and
    /// unlike Apple there is no identity object carrying it.
    let onSignedIn: (String) -> Void
    /// Design-only. With no backend there is nothing to email and nothing to
    /// check, so the sheet walks its own shape and hands back at the end.
    var demoMode: Bool = false

    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var sent = false
    @State private var working = false
    @State private var problem: String?

    /// Deliberately loose. A regex that tries to be clever about addresses is
    /// famously wrong about real ones, and the code either arrives or it does not
    /// — which is a better check than any pattern.
    private var addressLooksReal: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return at != trimmed.startIndex && domain.contains(".") && !domain.hasSuffix(".")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            Text(sent ? "Check your email" : "Your email")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            Text(sent
                 ? "We sent a six-digit code to \(email). It is good for about an hour."
                 : "Arch will email you a six-digit code. There is no password to make or forget.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            if sent {
                codeField
            } else {
                emailField
            }

            if let problem {
                // Stated in the same register as everything else. Nothing here is
                // the reader's fault in a way worth colouring.
                Text(problem)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ArchButton(
                title: sent ? "Sign in" : "Email me a code",
                isEnabled: !working && (sent ? code.count == 6 : addressLooksReal),
                action: advance
            )

            if sent {
                ArchTextButton(title: "Use a different address") {
                    sent = false
                    code = ""
                    problem = nil
                }
            } else {
                Text("Your address is never shown to anyone and never appears on your profile.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(sent ? 380 : 360)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .archSheetBackground()
    }

    private var emailField: some View {
        ArchField(
            text: $email,
            placeholder: "sam@example.com",
            keyboard: .emailAddress,
            surface: ArchColor.night
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .accessibilityIdentifier("signin.email")
    }

    private var codeField: some View {
        ArchField(
            text: $code,
            placeholder: "123456",
            keyboard: .numberPad,
            surface: ArchColor.night
        )
        .accessibilityIdentifier("signin.code")
        .onChange(of: code) { _, new in
            // Digits only, six of them. Filtering as it is typed rather than
            // refusing afterwards, because a paste from the mail app usually
            // carries a space or two with it.
            let digits = String(new.filter(\.isNumber).prefix(6))
            if digits != new { code = digits }
        }
    }

    private func advance() {
        problem = nil
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if demoMode {
            if sent { onSignedIn(address) } else { email = address; sent = true }
            return
        }

        working = true
        Task {
            do {
                if sent {
                    try await ArchBackend.signInWithEmail(address, code: code)
                    working = false
                    onSignedIn(address)
                } else {
                    try await ArchBackend.sendEmailCode(to: address)
                    email = address
                    sent = true
                    working = false
                }
            } catch {
                working = false
                problem = sent
                    ? "That code did not work. Codes expire after about an hour — ask for another if this one is old."
                    : "Arch could not send the code. Check the address, or try again in a moment."
            }
        }
    }
}

#Preview("Email") {
    EmailSignInSheet(onSignedIn: { _ in }, demoMode: true)
        .preferredColorScheme(.dark)
}
