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
/// **Short on purpose.** A heading, the two documents and the box, centred.
/// There used to be a description and a six-line summary of the terms above
/// them; both were cut to shorten what onboarding asks people to read. The
/// French terms are still on the website, and linked from the English page.
struct OnboardingTerms: View {
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .center, spacing: ArchSpacing.xl) {
            StepHeading(title: "The terms", centered: true)

            links

            agreement
        }
        .frame(maxWidth: .infinity)
    }

    /// Opened in Safari rather than drawn here: the pages are long, they are
    /// the same pages everybody else reads, and a copy in the app would be a
    /// second version to keep in step with the first.
    private var links: some View {
        VStack(alignment: .center, spacing: ArchSpacing.s) {
            if let terms = ArchConfig.termsURL {
                Link("Read the Terms and Conditions", destination: terms)
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
            }
            .padding(ArchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .center)
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
