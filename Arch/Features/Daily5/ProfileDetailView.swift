import SwiftUI

/// One person, read properly: a single vertical scroll alternating photographs and
/// written answers.
///
/// **Viewing is a no-op.** Nothing is recorded, nothing is sent, and back returns
/// you to the roster having changed nothing. There is no view count anywhere in
/// this screen and no state that could imply they know you were here.
///
/// **There is no like.** Tapping a photo or an answer selects it as the thing your
/// first message will be about, and the bottom bar relabels to say so. That is the
/// only thing a tap on a card does. The interests block is the one thing here that
/// is not tappable — a two-word tag is not something you can write a reply to.
struct ProfileDetailView: View {
    let person: Person
    let onDismiss: () -> Void
    let onSend: (String, ProfileItem?) -> Void

    @State private var selected: ProfileItem?
    @State private var isComposing = false
    @Environment(\.dismiss) private var dismiss

    init(
        person: Person,
        selecting initialSelection: ProfileItem? = nil,
        onDismiss: @escaping () -> Void,
        onSend: @escaping (String, ProfileItem?) -> Void
    ) {
        self.person = person
        self.onDismiss = onDismiss
        self.onSend = onSend
        _selected = State(initialValue: initialSelection)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                leadPhoto
                identity
                hint
                scrollBody
            }
            .padding(.bottom, ArchSpacing.sectionGap)
        }
        .background(ArchColor.night)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) { backButton }
        .safeAreaInset(edge: .bottom) { actionBar }
        .sheet(isPresented: $isComposing) {
            MessageComposerSheet(
                person: person,
                quoted: selected,
                onSend: { text in
                    isComposing = false
                    onSend(text, selected)
                }
            )
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var leadPhoto: some View {
        if let photo = person.photos.first {
            PhotoPlaceholder(toneIndex: photo.toneIndex)
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }

    /// Name and vitals sit *beneath* the photo rather than over it. Over the image
    /// they would need a dark scrim to stay legible, and Arch does not use gradient
    /// washes.
    private var identity: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text(person.name)
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)
            VitalsRow(vitals: person.vitals)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.top, ArchSpacing.l)
    }

    private var hint: some View {
        Text("Tap a photo or answer to write about it.")
            .archText(.footnote)
            .foregroundStyle(ArchColor.mortar)
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.top, ArchSpacing.l)
            .padding(.bottom, ArchSpacing.xl)
    }

    /// Order comes from `Person.scrollRows`, so this screen and the You tab cannot
    /// drift into different interleaves.
    private var scrollBody: some View {
        VStack(spacing: ArchSpacing.cardGap) {
            ForEach(person.scrollRows) { row in
                rowView(row)
            }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
    }

    @ViewBuilder
    private func rowView(_ row: ProfileRow) -> some View {
        switch row {
        case .item(let item):
            switch item {
            case .photo(let photo):
                PhotoCard(
                    photo: photo,
                    position: photoPosition(photo),
                    isSelected: selected?.id == item.id,
                    onTap: { toggle(item) }
                )
            case .prompt(let prompt):
                PromptCard(
                    prompt: prompt,
                    isSelected: selected?.id == item.id,
                    onTap: { toggle(item) }
                )
            }
        case .interests:
            // Not selectable, and not a `ProfileItem` — see `InterestsBlock`.
            InterestsBlock(interests: person.interests)
        }
    }

    private func photoPosition(_ photo: Photo) -> Int {
        (person.photos.firstIndex(of: photo) ?? 0) + 1
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)
                .frame(width: 36, height: 36)
                .background(Circle().fill(ArchColor.stone))
                .frame(width: ArchSpacing.minimumTapTarget, height: ArchSpacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.leading, ArchSpacing.s)
        .padding(.top, ArchSpacing.xs)
        .accessibilityLabel("Back to your five")
    }

    /// Both available actions, weighted honestly: writing to someone is what the
    /// app is for, dismissing is the quietest thing on the screen.
    private var actionBar: some View {
        VStack(spacing: 0) {
            ArchButton(title: selected == nil ? "Send a message" : "Write about this") {
                isComposing = true
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.top, ArchSpacing.s)

            ArchTextButton(title: "Dismiss", action: onDismiss)
                .padding(.horizontal, ArchSpacing.screenMargin)
                .padding(.bottom, ArchSpacing.xxs)
        }
        .background(ArchColor.stoneRaised)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ArchColor.hairline)
                .frame(height: ArchSpacing.hairline)
        }
    }

    private func toggle(_ item: ProfileItem) {
        selected = selected?.id == item.id ? nil : item
    }
}

// MARK: - Previews

#Preview("Profile") {
    NavigationStack {
        ProfileDetailView(person: MockData.nadia, onDismiss: {}, onSend: { _, _ in })
    }
    .preferredColorScheme(.dark)
}

/// The state where a card has been chosen for the first message, so the bottom-bar
/// action has relabelled to "Write about this".
#Preview("Profile, answer selected") {
    NavigationStack {
        ProfileDetailView(
            person: MockData.teo,
            selecting: .prompt(MockData.teo.prompts[0]),
            onDismiss: {},
            onSend: { _, _ in }
        )
    }
    .preferredColorScheme(.dark)
}
