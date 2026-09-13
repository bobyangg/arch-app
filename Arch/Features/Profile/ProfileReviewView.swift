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
/// **Notes** is the part the AI does, and it is not built. It says so.
struct ProfileReviewView: View {
    let person: Person
    /// Item id to the number of people who wrote about it.
    let writtenAbout: [String: Int]

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

    /// The half that needs a model, and does not have one.
    private var notes: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Notes on your profile")
                .archText(.prompt)
                .foregroundStyle(ArchColor.mortar)

            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text("Not running yet")
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
                Text("This is where specific notes on your photos and answers will go — what is vague, what to say instead. It is not built yet, and until it is, the half above is the honest part.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ArchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                    .fill(ArchColor.stone)
            )
        }
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
                PhotoPlaceholder(toneIndex: photo.toneIndex)
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
