import SwiftUI

/// Your own profile, rendered the way other people see it, with the edits folded
/// in rather than hidden behind a separate "edit profile" screen.
///
/// The division of labour: **Arrange** owns photos — adding, removing, ordering —
/// and the inline pencils own text. That keeps one mechanism per job instead of
/// two ways to do each.
struct YouProfileView: View {
    let store: ProfileStore
    let settings: SettingsStore
    /// How many people wrote about each photo and answer. Empty is a real state —
    /// a new profile nobody has written to yet.
    var writtenAbout: [String: Int] = [:]
    /// Switches to the Premium tab, rather than rebuilding the paywall inside a
    /// settings push.
    var onOpenPremium: () -> Void = {}

    // NavigationPath rather than [Route]: Settings pushes SettingsRow values into
    // this same stack, and a typed array path only accepts one type.
    @State private var path = NavigationPath()
    @State private var editing: Sheet?

    enum Route: Hashable {
        case arrange
        case settings
        case review
    }

    enum Sheet: String, Identifiable {
        case details
        case interests
        var id: String { rawValue }
    }

    /// The answer currently open in the editor. Separate from `editing` because it
    /// carries a value rather than a case.
    @State private var editingAnswer: Prompt?

    private var person: Person { store.person }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                scroll
            }
            .background(ArchColor.night)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .arrange:  ArrangeProfileView(store: store)
                case .settings: SettingsView(store: settings, onOpenPremium: onOpenPremium)
                case .review:   ProfileReviewView(person: person, writtenAbout: writtenAbout)
                }
            }
        }
        .sheet(item: $editing) { sheet in
            switch sheet {
            case .details:
                EditDetailsSheet(person: person) { name, age, neighbourhood, city, height, work in
                    store.updateDetails(
                        name: name, age: age, neighbourhood: neighbourhood,
                        city: city, height: height, work: work
                    )
                    editing = nil
                }
            case .interests:
                EditInterestsSheet(interests: person.interests) { texts in
                    store.setInterests(texts)
                    editing = nil
                }
            }
        }
        .sheet(item: $editingAnswer) { prompt in
            EditAnswerSheet(
                prompt: prompt,
                taken: store.questionsTaken(excluding: prompt.id)
            ) { question, answer in
                store.updatePrompt(id: prompt.id, question: question, answer: answer)
                editingAnswer = nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: ArchSpacing.s) {
            Text("You")
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)

            Spacer(minLength: 0)

            Button { path.append(.arrange) } label: {
                Text("Arrange")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }
            .buttonStyle(PressScaleStyle(scale: 1))

            // The gear is the rightmost thing on the screen, so nothing competes
            // with it for "this is settings".
            Button { path.append(.settings) } label: {
                Image(systemName: "gearshape")
                    .archText(.body)
                    .foregroundStyle(ArchColor.mortar)
                    .frame(width: ArchSpacing.minimumTapTarget, height: ArchSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Settings")
            .padding(.trailing, -ArchSpacing.s)
            .offset(y: ArchSpacing.xxs)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.top, ArchSpacing.m)
        .padding(.bottom, ArchSpacing.m)
    }

    // MARK: Scroll

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                leadPhoto
                identity
                completeness
                rows
                reviewRow
            }
            .padding(.bottom, ArchSpacing.sectionGap)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var leadPhoto: some View {
        if let photo = person.mainPhoto {
            PhotoPlaceholder(toneIndex: photo.toneIndex)
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Your main photo")
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(person.name)
                    .archText(.titleL)
                    .foregroundStyle(ArchColor.limestone)
                Spacer(minLength: 0)
                CardAffordanceView(
                    affordance: .edit(action: { editing = .details }),
                    subject: "your details"
                )
                .padding(.trailing, -ArchSpacing.xs)
            }
            VitalsRow(vitals: person.vitals)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.top, ArchSpacing.l)
    }

    /// One sentence naming what is still missing, which disappears once the
    /// profile is finished. Not a meter — a percentage would be a score, and Arch
    /// does not show scores.
    @ViewBuilder
    private var completeness: some View {
        if !person.isComplete {
            Text(completenessSentence)
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, ArchSpacing.screenMargin)
                .padding(.top, ArchSpacing.m)
        }
    }

    private var rows: some View {
        VStack(spacing: ArchSpacing.cardGap) {
            ForEach(person.scrollRows) { row in
                rowView(row)
            }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.top, ArchSpacing.xl)
    }

    @ViewBuilder
    private func rowView(_ row: ProfileRow) -> some View {
        switch row {
        case .item(let item):
            switch item {
            case .photo(let photo):
                // Photos are managed in one place, so the pencil routes there
                // rather than opening a second, half-capable photo editor.
                PhotoCard(
                    photo: photo,
                    affordance: .edit(action: { path.append(.arrange) }),
                    position: photoPosition(photo)
                )
            case .prompt(let prompt):
                PromptCard(
                    prompt: prompt,
                    affordance: .edit(action: { editingAnswer = prompt })
                )
            }
        case .interests:
            InterestsBlock(
                interests: person.interests,
                isOwn: true,
                onEdit: { editing = .interests }
            )
        }
    }

    // MARK: Review

    /// The way into the profile review, at the *bottom* of the scroll.
    ///
    /// Putting it at the top would make "how am I doing" the first thing you meet
    /// on your own profile, which is the beginning of a scoreboard. At the bottom
    /// you have already read your profile the way other people read it, and the
    /// row is an afterthought you can take or leave.
    ///
    /// No badge, no lock, no lamp. Premium is a sentence in the detail line, the
    /// same way the paywall itself refuses to sell with colour.
    private var reviewRow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ArchColor.hairline)
                .frame(height: ArchSpacing.hairline)

            Button {
                if settings.isSubscribed {
                    path.append(Route.review)
                } else {
                    onOpenPremium()
                }
            } label: {
                HStack(alignment: .top, spacing: ArchSpacing.s) {
                    VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                        Text("Review your profile")
                            .archText(.body)
                            .foregroundStyle(ArchColor.limestone)
                        Text(reviewDetail)
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.mortar)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: ArchSpacing.s)

                    Image(systemName: "chevron.right")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                        .padding(.top, ArchSpacing.xxs)
                }
                .padding(.vertical, ArchSpacing.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 1))
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.top, ArchSpacing.sectionGap)
    }

    private var reviewDetail: String {
        settings.isSubscribed
        ? "Which of your photos and answers people write about."
        : "Part of Arch Premium. Which of your photos and answers people write about, and notes on what to change."
    }

    // MARK: Helpers

    private func photoPosition(_ photo: Photo) -> Int {
        (person.photos.firstIndex(of: photo) ?? 0) + 1
    }

    private var completenessSentence: String {
        let missing = person.missing
        guard !missing.isEmpty else { return "" }

        let joined: String
        switch missing.count {
        case 1:
            joined = missing[0]
        case 2:
            joined = "\(missing[0]) and \(missing[1])"
        default:
            joined = missing.dropLast().joined(separator: ", ") + ", and \(missing[missing.count - 1])"
        }
        return "Add \(joined) to finish your profile."
    }
}

// MARK: - Previews

#Preview("You, finished") {
    YouProfileView(store: ProfileStore(person: MockData.you), settings: SettingsStore())
        .preferredColorScheme(.dark)
}

#Preview("You, unfinished") {
    YouProfileView(store: ProfileStore(person: MockData.youIncomplete), settings: SettingsStore())
        .preferredColorScheme(.dark)
}

#Preview("You, subscribed") {
    YouProfileView(
        store: ProfileStore(person: MockData.you),
        settings: {
            let settings = SettingsStore()
            settings.isSubscribed = true
            return settings
        }(),
        writtenAbout: MockData.writtenAbout
    )
    .preferredColorScheme(.dark)
}
