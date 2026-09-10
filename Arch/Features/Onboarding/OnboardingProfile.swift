import SwiftUI

/// Photos: four minimum, six maximum.
///
/// The shortfall is named — "Two more photos" — rather than left to be inferred
/// from a button that will not press.
struct OnboardingPhotos: View {
    let store: OnboardingStore

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
                    onMove: { profile.movePhoto(id: $0, to: $1) },
                    onAdd: { profile.addPhoto() },
                    onRemove: { profile.removePhoto(id: $0) }
                )

                Text(store.photoShortfallText)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }
        }
    }
}

/// Three answers.
///
/// The questions are assigned. Choosing your own is a later job, and pretending
/// otherwise here would mean two half-built ways to pick a prompt.
struct OnboardingAnswers: View {
    let store: OnboardingStore

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
    }

    private func answer(_ prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
            Text(prompt.question)
                .archText(.prompt)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

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
