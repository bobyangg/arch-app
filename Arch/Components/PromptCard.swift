import SwiftUI

/// A written answer, given the same weight in the scroll as a photograph.
///
/// The question is set in New York and held back in `mortar`; the answer is the
/// loudest thing on the card. That order matters — you are meant to read the
/// person, not the form they filled in.
///
/// As with `PhotoCard`, there is no like button. Tapping the card selects it as
/// the thing your first message will be about.
struct PromptCard: View {
    let prompt: Prompt
    /// Editing, on your own profile. Never a like.
    var affordance: CardAffordance = .none
    /// Selected as the thing the first message will be about.
    var isSelected: Bool = false
    /// Trims the answer, for the quoted block in the composer and the thread.
    var lineLimit: Int?
    var onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) { card }
                .buttonStyle(PressScaleStyle(scale: 0.985))
                .accessibilityLabel("\(prompt.question). \(prompt.answer)")
                .accessibilityHint("Write your message about this answer")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        } else {
            card.accessibilityElement(children: .combine)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text(prompt.question)
                .archText(.prompt)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            Text(prompt.answer)
                .archText(.bodyL)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: lineLimit == nil)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)

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
        .overlay(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .strokeBorder(isSelected ? ArchColor.lampQuiet : Color.clear, lineWidth: 1)
        )
        .animation(ArchMotion.quick, value: isSelected)
    }

    private var hasAffordance: Bool {
        if case .none = affordance { return false }
        return true
    }
}

#Preview("Prompt card") {
    ScrollView {
        VStack(spacing: ArchSpacing.cardGap) {
            PromptCard(prompt: MockData.nadia.prompts[0], onTap: {})
            PromptCard(prompt: MockData.teo.prompts[1], isSelected: true, onTap: {})
            PromptCard(prompt: MockData.you.prompts[0], affordance: .edit(action: {}))
            PromptCard(prompt: MockData.lena.prompts[2], lineLimit: 2)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.vertical, ArchSpacing.xxl)
    }
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
