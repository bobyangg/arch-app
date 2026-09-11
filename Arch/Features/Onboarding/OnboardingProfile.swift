import SwiftUI

/// Photos: four minimum, six maximum.
///
/// The shortfall is named — "Two more photos" — rather than left to be inferred
/// from a button that will not press.
struct OnboardingPhotos: View {
    let store: OnboardingStore

    @State private var isPicking = false

    private var profile: ProfileStore { store.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "Photos",
                detail: "At least \(Person.requiredPhotos), up to \(Person.photoLimit). The first one is what people see in their five."
            )

            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                PhotoGrid(
                    photos: profile.person.photos,
                    canAdd: profile.canAddPhoto,
                    canRemove: profile.canRemovePhoto,
                    uploads: profile.uploads,
                    onMove: { profile.movePhoto(id: $0, to: $1) },
                    onAdd: { isPicking = true },
                    onRemove: { profile.removePhoto(id: $0) },
                    onFinishUpload: { profile.finishUpload(id: $0) },
                    onRetryUpload: { profile.retryUpload(id: $0) }
                )

                Text(store.photoShortfallText)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }
        }
        .sheet(isPresented: $isPicking) {
            PhotoPickerView(slotsLeft: profile.slotsLeft) { profile.addPhotos($0) }
        }
    }
}

/// Three answers.
///
/// The three questions you start on are a starting point, not an assignment —
/// tapping one opens the same picker the You tab uses.
struct OnboardingAnswers: View {
    let store: OnboardingStore

    @State private var choosingFor: Prompt?

    private var profile: ProfileStore { store.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "Three answers",
                detail: "This is the part people actually read. The specific version always beats the general one."
            )

            VStack(spacing: ArchSpacing.m) {
                ForEach(profile.person.prompts) { prompt in
                    answer(prompt)
                }
            }
        }
        .sheet(item: $choosingFor) { prompt in
            PromptPickerView(
                current: prompt.question,
                taken: profile.questionsTaken(excluding: prompt.id),
                onChoose: { chosen in
                    profile.updatePrompt(id: prompt.id, question: chosen.text, answer: "")
                    choosingFor = nil
                },
                onCancel: { choosingFor = nil }
            )
            .padding(.horizontal, ArchSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ArchColor.stone)
            .presentationDetents([.large])
            .presentationCornerRadius(ArchRadius.sheet)
            .presentationBackground(ArchColor.stone)
        }
    }

    private func answer(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
            Button { choosingFor = prompt } label: {
                HStack(alignment: .firstTextBaseline, spacing: ArchSpacing.s) {
                    Text(prompt.question)
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
            .accessibilityLabel("Question: \(prompt.question)")
            .accessibilityHint("Choose a different question")

            TextField(
                "",
                text: binding(for: prompt),
                prompt: Text("Answer it properly.").foregroundColor(ArchColor.mortar),
                axis: .vertical
            )
            .archText(.callout)
            .foregroundStyle(ArchColor.limestone)
            .lineLimit(3...7)
            .padding(.horizontal, ArchSpacing.s)
            .padding(.vertical, ArchSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(ArchColor.stone)
            )
        }
    }

    /// Reads back through the store rather than from the captured value, so the
    /// field shows what was actually written.
    private func binding(for prompt: Prompt) -> Binding<String> {
        Binding(
            get: { profile.person.prompts.first { $0.id == prompt.id }?.answer ?? "" },
            set: { profile.updateAnswer(id: prompt.id, to: $0) }
        )
    }
}

/// Three interests.
struct OnboardingInterests: View {
    let store: OnboardingStore

    private let examples = ["Night baking", "Rolleiflex repair", "Above-ground platforms"]

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "Three interests",
                detail: "Short and specific. \"Bridge inspections\" tells someone more than \"travel\" ever will."
            )

            VStack(spacing: ArchSpacing.xs) {
                ForEach(0..<Person.requiredInterests, id: \.self) { index in
                    ArchField(
                        text: Binding(
                            get: { store.interestDrafts[index] },
                            set: { store.interestDrafts[index] = $0 }
                        ),
                        placeholder: examples[index],
                        characterLimit: Interest.characterLimit,
                        surface: ArchColor.stone
                    )
                }
            }

            InterestsBlock(interests: previewInterests)
                .opacity(previewInterests.isEmpty ? 0 : 1)
        }
    }

    /// Shows the chips as they are typed, since a chip is what these become.
    private var previewInterests: [Interest] {
        store.interestDrafts.enumerated().compactMap { index, text in
            text.isBlank ? nil : Interest(id: "draft-\(index)", text: text.trimmed)
        }
    }
}

// MARK: - Previews

#Preview("Photos") {
    OnboardingPhotos(store: OnboardingStore())
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

#Preview("Answers") {
    OnboardingAnswers(store: OnboardingStore())
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

#Preview("Interests") {
    OnboardingInterests(store: .configured {
        $0.interestDrafts = ["Room tone", "Click tracks", ""]
    })
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}
