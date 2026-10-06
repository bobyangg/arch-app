import SwiftUI

/// The terms, accepted before anything about you is collected.
///
/// **Second, straight after the birthday.** The terms are for people eighteen and
/// over, so the screen that settles that comes first; everything after this one
/// is a name, a town and four photographs, and the terms say what Arch may do
/// with those. Agreeing after handing them over would be agreeing late.
///
/// **A box to tick, not a sentence under a button.** The terms say they bind once
/// they are "expressly accepted", and a line reading "by continuing you agree" is
/// the weakest version of that there is. Continue does nothing until the box is
/// ticked, and ticking it is recorded on the server with the version.
///
/// The six lines are the short version, and they say so. They are the parts of
/// the terms somebody is likeliest to run into; the full text is one tap away,
/// in English and in French, and it is what counts.
struct OnboardingTerms: View {
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "The terms",
                detail: "What you agree to by joining Arch. This is the short version; the full terms are what count."
            )

            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                line("You are 18 or over, and this account is yours alone.")
                line("Your profile is honest, and your first photo is you.")
                line("No harassment, no scams, and no unwanted sexual content.")
                line("Arch does not run background checks. Meet somewhere public, and never send money.")
                line("Premium renews until you cancel it in your Apple ID settings.")
                line("You can delete your account at any time, in Settings.")
            }
            .padding(ArchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                    .fill(ArchColor.stone)
            )

            links

            agreement
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .archText(.body)
            .foregroundStyle(ArchColor.limestone)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Opened in Safari rather than drawn here: the pages are long, they are
    /// the same pages everybody else reads, and a copy in the app would be a
    /// second version to keep in step with the first.
    private var links: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            if let terms = ArchConfig.termsURL {
                Link("Read the Terms and Conditions", destination: terms)
            }
            if let french = ArchConfig.termsFrenchURL {
                Link("Lire les conditions en français", destination: french)
            }
            if let privacy = ArchConfig.privacyURL {
                Link("Read the Privacy Policy", destination: privacy)
            }
        }
        .archText(.callout)
        .foregroundStyle(ArchColor.lamp)
        .tint(ArchColor.lamp)
    }

    private var agreement: some View {
        Button {
            store.acceptedTerms.toggle()
        } label: {
            HStack(alignment: .top, spacing: ArchSpacing.s) {
                Image(systemName: store.acceptedTerms ? "checkmark.square.fill" : "square")
                    .archText(.bodyL)
                    .foregroundStyle(store.acceptedTerms ? ArchColor.lamp : ArchColor.mortar)
                Text("I have read and agree to the Terms and Conditions, and I have read the Privacy Policy.")
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(ArchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(store.acceptedTerms ? ArchColor.stoneRaised : ArchColor.stone)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.99))
        .accessibilityLabel("I have read and agree to the Terms and Conditions, and I have read the Privacy Policy")
        .accessibilityAddTraits(store.acceptedTerms ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Not yet ticked") {
    OnboardingTerms(store: OnboardingStore())
        .padding(.horizontal, ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

#Preview("Ticked") {
    OnboardingTerms(store: {
        let s = OnboardingStore()
        s.acceptedTerms = true
        return s
    }())
    .padding(.horizontal, ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
