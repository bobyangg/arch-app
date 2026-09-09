import SwiftUI

/// A written answer, given the same weight in the scroll as a photograph.
///
/// The question is set in New York and held back in `mortar`; the answer is the
/// loudest thing on the card. That order matters — you are meant to read the
/// person, not the form they filled in.
struct PromptCard: View {
    let prompt: Prompt
    var affordance: CardAffordance = .none

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text(prompt.question)
                .archText(.prompt)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            Text(prompt.answer)
                .archText(.bodyL)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)

            if hasAffordance {
                HStack {
                    Spacer(minLength: 0)
                    CardAffordanceView(affordance: affordance, subject: "this answer")
                }
                .padding(.top, ArchSpacing.xs)
                .padding(.trailing, -ArchSpacing.xs)
                .padding(.bottom, -ArchSpacing.s)
            }
        }
        .padding(ArchSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(ArchColor.stone)
        )
        .accessibilityElement(children: .contain)
    }

    private var hasAffordance: Bool {
        if case .none = affordance { return false }
        return true
    }
}

#Preview("Prompt card") {
    ScrollView {
        VStack(spacing: ArchSpacing.cardGap) {
            PromptCard(
                prompt: MockData.nadia.prompts[0],
                affordance: .like(isLiked: false, action: {})
            )
            PromptCard(
                prompt: MockData.teo.prompts[1],
                affordance: .like(isLiked: true, action: {})
            )
            PromptCard(
                prompt: MockData.you.prompts[0],
                affordance: .edit(action: {})
            )
            PromptCard(prompt: MockData.lena.prompts[2])
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.vertical, ArchSpacing.xxl)
    }
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
