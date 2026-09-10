import SwiftUI

/// Reordering photos and answers.
///
/// A separate surface rather than dragging inside the profile itself: a photo card
/// in the scroll is 470pt tall, and dragging one of those through a long scroll is
/// miserable on a phone. Collapsed to a grid, the whole set is visible at once.
///
/// **The first slot is the main photo.** Drag a photo to the front and that is what
/// people see in their five — there is no separate "set as main" control to keep in
/// sync with the ordering.
///
/// Photos and answers use the *same* drag mechanism. `List` with `.onMove` needs
/// edit mode to show its handles and drags `List`'s own styling onto a screen built
/// out of custom surfaces; one mechanism for both is less code and behaves
/// identically in both halves.
///
/// The grid itself is `PhotoGrid`, shared with onboarding.
struct ArrangeProfileView: View {
    let store: ProfileStore

    @Environment(\.dismiss) private var dismiss

    private var person: Person { store.person }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: ArchSpacing.xxl) {
                    photoSection
                    answerSection
                }
                .padding(.horizontal, ArchSpacing.screenMargin)
                .padding(.top, ArchSpacing.l)
                .padding(.bottom, ArchSpacing.sectionGap)
            }
            .scrollIndicators(.hidden)
        }
        .background(ArchColor.night)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: ArchSpacing.s) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                    .frame(width: ArchSpacing.minimumTapTarget, height: ArchSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Back to your profile")

            Text("Arrange")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Text("Done")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.mortar)
            }
            .buttonStyle(PressScaleStyle(scale: 1))
        }
        .padding(.leading, ArchSpacing.xs)
        .padding(.trailing, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
        }
    }

    // MARK: Photos

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Photos")
                .archText(.prompt)
                .foregroundStyle(ArchColor.mortar)

            PhotoGrid(
                photos: person.photos,
                canAdd: store.canAddPhoto,
                canRemove: store.canRemovePhoto,
                onMove: { store.movePhoto(id: $0, to: $1) },
                onAdd: { store.addPhoto() },
                onRemove: { store.removePhoto(id: $0) }
            )

            PhotoGridCaption(count: person.photos.count)
                .padding(.top, ArchSpacing.xxs)
        }
    }

    // MARK: Answers

    private var answerSection: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Answers")
                .archText(.prompt)
                .foregroundStyle(ArchColor.mortar)

            VStack(spacing: ArchSpacing.xs) {
                ForEach(Array(person.prompts.enumerated()), id: \.element.id) { index, prompt in
                    answerRow(prompt, at: index)
                }
            }

            if person.answeredPrompts.count < Person.requiredPrompts {
                Text("You have written \(person.answeredPrompts.count) of \(Person.requiredPrompts) answers.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .padding(.top, ArchSpacing.xxs)
            }
        }
    }

    private func answerRow(_ prompt: Prompt, at index: Int) -> some View {
        HStack(spacing: ArchSpacing.s) {
            Image(systemName: "line.3.horizontal")
                .archText(.subhead)
                .foregroundStyle(ArchColor.mortar)

            Text(prompt.question)
                .archText(.footnote)
                .foregroundStyle(ArchColor.limestone)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, ArchSpacing.s)
        .padding(.vertical, ArchSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                .fill(ArchColor.stone)
        )
        .draggable(prompt.id)
        .dropDestination(for: String.self) { ids, _ in
            guard let dragged = ids.first else { return false }
            store.moveAnswer(id: dragged, to: index)
            return true
        }
        .accessibilityLabel("Answer \(index + 1), \(prompt.question)")
    }
}

// MARK: - Previews

#Preview("Arrange, full") {
    NavigationStack {
        ArrangeProfileView(store: ProfileStore(person: MockData.you))
    }
    .preferredColorScheme(.dark)
}

#Preview("Arrange, unfinished") {
    NavigationStack {
        ArrangeProfileView(store: ProfileStore(person: MockData.youIncomplete))
    }
    .preferredColorScheme(.dark)
}
