import SwiftUI

/// Rewriting one answer, and choosing which question it answers.
///
/// Both live in one sheet because they are one decision. Changing the question
/// **clears the answer** — an answer written for a different question is not an
/// answer, it is a non sequitur on your profile — but nothing is committed until
/// you save, so backing out leaves the old question and the old answer intact.
struct EditAnswerSheet: View {
    let prompt: Prompt
    /// The questions your other answers are using, so the picker can mark them.
    var taken: [String] = []
    /// The chosen question and the answer written for it.
    let onSave: (String, String) -> Void

    @State private var question = ""
    @State private var draft = ""
    @State private var choosing = false
    @FocusState private var isWriting: Bool
    @Environment(\.dismiss) private var dismiss

    private let characterLimit = 320
    private let counterAppearsAt = 260

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if choosing {
                PromptPickerView(
                    current: question,
                    taken: taken,
                    onChoose: { chosen in
                        if chosen.text != question {
                            question = chosen.text
                            // A different question means the old answer no longer
                            // answers anything.
                            draft = ""
                        }
                        choosing = false
                        isWriting = true
                    },
                    onCancel: { choosing = false }
                )
                .padding(.horizontal, ArchSpacing.screenMargin)
            } else {
                editor
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.stone)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
        .onAppear {
            question = prompt.question
            draft = prompt.answer
            isWriting = true
        }
        .onChange(of: draft) { _, new in
            if new.count > characterLimit {
                draft = String(new.prefix(characterLimit))
            }
        }
    }

    // MARK: Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            questionRow
            field

            HStack {
                Spacer(minLength: 0)
                if draft.count >= counterAppearsAt {
                    Text("\(draft.count) of \(characterLimit)")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                        .monospacedDigit()
                }
            }
            .frame(height: 18)

            Spacer(minLength: 0)

            ArchButton(title: "Save", isEnabled: !trimmed.isEmpty) {
                onSave(question, trimmed)
            }
            ArchTextButton(title: "Cancel") { dismiss() }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.top, ArchSpacing.l)
        .padding(.bottom, ArchSpacing.m)
    }

    /// The question is the control. Tapping it is how you change it — there is no
    /// separate button competing with the thing it would act on.
    private var questionRow: some View {
        Button { choosing = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: ArchSpacing.s) {
                Text(question)
                    .archText(.prompt)
                    .foregroundStyle(ArchColor.mortar)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text("Change")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 1))
        .accessibilityLabel("Question: \(question)")
        .accessibilityHint("Choose a different question")
    }

    private var field: some View {
        ZStack(alignment: .topLeading) {
            if draft.isEmpty {
                Text("Answer it properly. The specific version is always better.")
                    .archText(.bodyL)
                    .foregroundStyle(ArchColor.mortar)
                    .padding(.top, ArchSpacing.s)
                    .padding(.leading, ArchSpacing.xxs + 1)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $draft)
                .archText(.bodyL)
                .foregroundStyle(ArchColor.limestone)
                .scrollContentBackground(.hidden)
                .focused($isWriting)
                .frame(minHeight: 170)
        }
        .padding(.horizontal, ArchSpacing.s)
        .padding(.vertical, ArchSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                .fill(ArchColor.night)
        )
    }
}

#Preview("Edit an answer") {
    EditAnswerSheet(
        prompt: MockData.you.prompts[0],
        taken: ["Something I am slower at than everyone else", "The best argument I have lost"],
        onSave: { _, _ in }
    )
    .frame(height: 560)
    .preferredColorScheme(.dark)
}

#Preview("An unanswered question") {
    EditAnswerSheet(
        prompt: Prompt(id: "blank", question: "A risk that worked out", answer: ""),
        onSave: { _, _ in }
    )
    .frame(height: 560)
    .preferredColorScheme(.dark)
}
