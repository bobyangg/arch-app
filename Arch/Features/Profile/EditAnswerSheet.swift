import SwiftUI

/// Rewriting one answer.
///
/// The question is shown but not editable — choosing a different question is a
/// separate job with its own screen, and pretending otherwise here would mean two
/// half-built ways to change your prompts.
struct EditAnswerSheet: View {
    let prompt: Prompt
    let onSave: (String) -> Void

    @State private var draft = ""
    @FocusState private var isWriting: Bool
    @Environment(\.dismiss) private var dismiss

    private let characterLimit = 320
    private let counterAppearsAt = 260

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            Text(prompt.question)
                .archText(.prompt)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.l)

            editor

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
                onSave(trimmed)
            }
            ArchTextButton(title: "Cancel") { dismiss() }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.stone)
        .presentationDetents([.height(480)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
        .onAppear {
            draft = prompt.answer
            isWriting = true
        }
        .onChange(of: draft) { _, new in
            if new.count > characterLimit {
                draft = String(new.prefix(characterLimit))
            }
        }
    }

    private var editor: some View {
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
                .frame(minHeight: 160)
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
    EditAnswerSheet(prompt: MockData.you.prompts[0]) { _ in }
        .frame(height: 480)
        .preferredColorScheme(.dark)
}

#Preview("Edit an empty answer") {
    EditAnswerSheet(
        prompt: Prompt(
            id: "blank",
            question: "The best argument I have lost",
            answer: ""
        )
    ) { _ in }
    .frame(height: 480)
    .preferredColorScheme(.dark)
}
