import SwiftUI

/// Choosing which question you answer.
///
/// Questions already used by your other answers stay visible and inert rather than
/// being hidden. Hiding them makes the library look shorter than it is and leaves
/// you hunting for a question you have already got — showing them, marked, answers
/// the question you actually have, which is "where did that one go".
struct PromptPickerView: View {
    /// The question this slot is on now.
    let current: String
    /// Questions your other answers occupy.
    let taken: [String]
    let onChoose: (PromptQuestion) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: ArchSpacing.xl) {
                    ForEach(PromptLibrary.groups) { group in
                        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
                            Text(group.title)
                                .archText(.prompt)
                                .foregroundStyle(ArchColor.mortar)

                            VStack(spacing: ArchSpacing.xs) {
                                ForEach(group.questions) { question in
                                    row(question)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, ArchSpacing.screenMargin)
                .padding(.top, ArchSpacing.l)
                .padding(.bottom, ArchSpacing.sectionGap)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack(spacing: ArchSpacing.s) {
            Button(action: onCancel) {
                Image(systemName: "chevron.left")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                    .frame(width: ArchSpacing.minimumTapTarget, height: ArchSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Back to your answer")

            Text("Choose a question")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            Spacer(minLength: 0)
        }
        .padding(.leading, -ArchSpacing.s)
        .padding(.bottom, ArchSpacing.xs)
    }

    @ViewBuilder
    private func row(_ question: PromptQuestion) -> some View {
        let isCurrent = question.text == current
        let isTaken = taken.contains(question.text) && !isCurrent

        Button {
            if !isTaken { onChoose(question) }
        } label: {
            HStack(spacing: ArchSpacing.s) {
                Text(question.text)
                    .archText(.body)
                    .foregroundStyle(isTaken ? ArchColor.mortar : ArchColor.limestone)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if isTaken {
                    Text("In use")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                } else if isCurrent {
                    Image(systemName: "checkmark")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.limestone)
                }
            }
            .padding(ArchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(isCurrent ? ArchColor.stoneRaised : ArchColor.stone)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .strokeBorder(
                        isCurrent ? ArchColor.limestone.opacity(0.30) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PressScaleStyle(scale: isTaken ? 1 : 0.99))
        .disabled(isTaken)
        .accessibilityLabel(question.text)
        .accessibilityValue(isTaken ? "Already used by another answer" : (isCurrent ? "Current" : ""))
    }
}

#Preview("Choose a question") {
    PromptPickerView(
        current: "Where I go when I need to think",
        taken: ["Something I am slower at than everyone else", "The best argument I have lost"],
        onChoose: { _ in },
        onCancel: {}
    )
    .padding(.horizontal, ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ArchColor.stone)
    .preferredColorScheme(.dark)
}
