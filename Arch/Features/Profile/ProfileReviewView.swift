import SwiftUI

/// A review of your own profile.
///
/// Two halves, and only one of them needs an AI.
///
/// **What people write about** is arithmetic, not judgement. When somebody writes
/// to you they pick a photo or an answer to write about, and the composer carries
/// it through — so the app already knows which parts of your profile give people
/// something to say. That is a real signal rather than one a model has to invent.
///
/// Deliberately *not* likes, views, or a score. Arch has no like, tells you nothing
/// about who looked at you, and is not about to grow a popularity number here of
/// all places. "Four people wrote about this" is a fact about your writing. "Your
/// profile scores 72" would be a fact about your worth, and the app does not have
/// an opinion on that.
///
/// **Notes** is the part a model does. It reads the photographs as photographs and
/// the answers as writing, and says what is vague and what to say instead — and it
/// is held to the same rule as the half above: nothing about the person, nothing
/// that is a score. The server's schema has no field for one.
struct ProfileReviewView: View {
    let person: Person
    /// Item id to the number of people who wrote about it.
    let writtenAbout: [String: Int]

    @State private var review = ProfileReviewStore()
    @Environment(\.dismiss) private var dismiss

    /// Photos and answered prompts, most-written-about first.
    ///
    /// Built from `answeredPrompts` rather than `items`, because an empty answer is
    /// a row with nothing in it — and "nobody wrote about your blank prompt" is not
    /// a finding.
    private var ranked: [(item: ProfileItem, count: Int)] {
        let items = person.photos.map(ProfileItem.photo)
            + person.answeredPrompts.map(ProfileItem.prompt)
        return items
            .map { (item: $0, count: writtenAbout[$0.id] ?? 0) }
            .sorted { $0.count > $1.count }
    }

    private var written: [(item: ProfileItem, count: Int)] { ranked.filter { $0.count > 0 } }
    private var untouched: [(item: ProfileItem, count: Int)] { ranked.filter { $0.count == 0 } }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: ArchSpacing.sectionGap) {
                    if written.isEmpty {
                        nothingYet
                    } else {
                        section(
                            "What people write about",
                            "When somebody writes to you they pick something to write about. This is what they pick."
                        ) {
                            ForEach(written, id: \.item.id) { entry in
                                row(entry.item, count: entry.count)
                            }
                        }

                        if !untouched.isEmpty {
                            section(
                                "Nobody has written about these",
                                "Not a verdict — often it just means there is nothing in them to answer."
                            ) {
                                ForEach(untouched, id: \.item.id) { entry in
                                    row(entry.item, count: 0)
                                }
                            }
                        }
                    }

                    notes
                }
                .padding(.horizontal, ArchSpacing.screenMargin)
                .padding(.top, ArchSpacing.l)
                .padding(.bottom, ArchSpacing.sectionGap)
            }
            .scrollIndicators(.hidden)
        }
        .background(ArchColor.night)
        .toolbar(.hidden, for: .navigationBar)
        .task { await review.load(person) }
    }

    // MARK: Pieces

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

            Text("Profile review")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            Spacer(minLength: 0)
        }
        .padding(.leading, ArchSpacing.xs)
        .padding(.trailing, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
        }
    }

    private var nothingYet: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Nothing to go on yet")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
            Text("When somebody writes to you, this shows which of your photos and answers they picked out. Come back once a few people have.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The half that needs a model.
    private var notes: some View {
        section(
            "Notes on your profile",
            "About the photographs as photographs and the answers as writing. Nothing here is a score, and nothing here is about you."
        ) {
            switch review.state {
            case .idle, .loading:
                quietCard {
                    HStack(spacing: ArchSpacing.s) {
                        ProgressView()
                            .tint(ArchColor.mortar)
                        Text("Reading your profile")
                            .archText(.body)
                            .foregroundStyle(ArchColor.limestone)
                    }
                    Text("A moment. It looks at every photograph and every answer.")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .failed(let sentence):
                quietCard {
                    Text(sentence)
                        .archText(.body)
                        .foregroundStyle(ArchColor.limestone)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { await review.load(person, fresh: true) }
                    } label: {
                        Text("Try again")
                            .archText(.subhead)
                            .foregroundStyle(ArchColor.mortar)
                    }
                    .buttonStyle(PressScaleStyle(scale: 1))
                }

            case .ready(let notes):
                quietCard {
                    Text(notes.overall)
                        .archText(.body)
                        .foregroundStyle(ArchColor.limestone)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(ordered(notes)) { note in
                    noteRow(note)
                }

                // Asking again is a real action with a real cost, so it is the
                // quietest control on the screen and the server, not the app,
                // decides how many it will run.
                ArchTextButton(title: "Ask again") {
                    Task { await review.load(person, fresh: true) }
                }
                .disabled(review.isLoading)
            }
        }
    }

    /// Photographs first, in profile order, then the answers.
    private func ordered(_ notes: ProfileNotes) -> [ProfileNote] {
        notes.items.sorted {
            if $0.kind != $1.kind { return $0.kind == .photo }
            return $0.position < $1.position
        }
    }

    /// The note beside the thing it is about, so the reader never has to match a
    /// number to a card.
    private func noteRow(_ note: ProfileNote) -> some View {
        HStack(alignment: .top, spacing: ArchSpacing.s) {
            switch note.kind {
            case .photo:
                if let photo = photo(at: note.position) {
                    PhotoPlaceholder(toneIndex: photo.toneIndex, url: photo.url)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: ArchRadius.detail, style: .continuous))
                }
            case .answer:
                EmptyView()
            }

            VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: ArchSpacing.xs) {
                    Text(subject(of: note))
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                    Spacer(minLength: ArchSpacing.s)
                    // A word, not a colour. "Change" in terracotta would make the
                    // accent mean "wrong", and it means "act" everywhere else.
                    Text(note.verdict.word)
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                }
                if case .answer = note.kind, let prompt = prompt(at: note.position) {
                    Text(prompt.answer)
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                        .lineLimit(2)
                }
                Text(note.note)
                    .archText(.callout)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ArchSpacing.xxs)
            }
        }
        .padding(ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                .fill(ArchColor.stone)
        )
    }

    private func subject(of note: ProfileNote) -> String {
        switch note.kind {
        case .photo:  return "Photo \(note.position)"
        case .answer: return prompt(at: note.position)?.question ?? "Answer \(note.position)"
        }
    }

    private func photo(at position: Int) -> Photo? {
        let index = position - 1
        return person.photos.indices.contains(index) ? person.photos[index] : nil
    }

    private func prompt(at position: Int) -> Prompt? {
        let answered = person.answeredPrompts
        let index = position - 1
        return answered.indices.contains(index) ? answered[index] : nil
    }

    private func quietCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) { content() }
            .padding(ArchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                    .fill(ArchColor.stone)
            )
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        _ detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                Text(title)
                    .archText(.prompt)
                    .foregroundStyle(ArchColor.mortar)
                Text(detail)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: ArchSpacing.xs) { content() }
        }
    }

    private func row(_ item: ProfileItem, count: Int) -> some View {
        HStack(alignment: .top, spacing: ArchSpacing.s) {
            switch item {
            case .photo(let photo):
                PhotoPlaceholder(toneIndex: photo.toneIndex, url: photo.url)
                    .frame(width: 44, height: 55)
                    .clipShape(RoundedRectangle(cornerRadius: ArchRadius.detail, style: .continuous))
                Text("Photo \(photoNumber(photo))")
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
            case .prompt(let prompt):
                VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                    Text(prompt.question)
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                    Text(prompt.answer)
                        .archText(.callout)
                        .foregroundStyle(ArchColor.limestone)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: ArchSpacing.s)

            if count > 0 {
                Text(count == 1 ? "1 person" : "\(count) people")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .monospacedDigit()
            }
        }
        .padding(ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                .fill(ArchColor.stone)
        )
    }

    private func photoNumber(_ photo: Photo) -> Int {
        (person.photos.firstIndex(of: photo) ?? 0) + 1
    }
}

#Preview("Profile review") {
    NavigationStack {
        ProfileReviewView(person: MockData.you, writtenAbout: MockData.writtenAbout)
    }
    .preferredColorScheme(.dark)
}

#Preview("Nothing to go on yet") {
    NavigationStack {
        ProfileReviewView(person: MockData.you, writtenAbout: [:])
    }
    .preferredColorScheme(.dark)
}
