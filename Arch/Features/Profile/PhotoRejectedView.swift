import SwiftUI

/// A photograph moderation would not take.
///
/// **Built on `RemovedAccountView`'s skeleton**, because this is the same job in
/// miniature: bad news, delivered plainly, without the app performing its own
/// disapproval. Title, one sentence of why, the consequences bare, then the way
/// out. No red, no icon, no alert — Arch has no red anywhere, and a photograph that
/// did not pass review is not a hazard.
///
/// **It names the photograph by showing it.** `RemovedAccountView` names a category
/// and never the evidence, for good reasons that do not apply here: the evidence is
/// the reader's own property, and it is the only stable way to say *which one*. A
/// position number changes the moment somebody reorders, and "your third photo" is
/// a puzzle rather than an answer.
///
/// **And it says why.** Vague moderation is the thing people hate most about it,
/// because there is nothing to act on — and the reasons in `PhotoRejection` are
/// deliberately written so that none of them accuse anybody. In most cases the
/// photograph was blurred or had two people in it.
struct PhotoRejectedView: View {
    let photo: Photo
    let reason: PhotoRejection
    /// How many photographs are on the profile now. Below the floor, replacing this
    /// one stops being optional, and the screen says so once.
    var remaining: Int
    /// Whether a review has already been asked for. One per photograph.
    var review: AppealState = .notSent

    let onChooseAnother: () -> Void
    let onAskForReview: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isAsking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .archText(.titleL)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("photo.rejected.title")

                Text(opening)
                    .archText(.body)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ArchSpacing.s)

                // Small, and once. Large enough to recognise, not so large that the
                // screen becomes about looking at it.
                PhotoPlaceholder(toneIndex: photo.toneIndex, url: photo.url)
                    .aspectRatio(PhotoCard.aspect, contentMode: .fit)
                    .frame(width: 132)
                    .clipShape(
                        RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    )
                    .padding(.top, ArchSpacing.l)

                VStack(alignment: .leading, spacing: ArchSpacing.s) {
                    ForEach(consequences, id: \.self) { line in
                        Text(line)
                            .archText(.body)
                            .foregroundStyle(ArchColor.limestone)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, ArchSpacing.xl)

                Spacer(minLength: ArchSpacing.xl)

                reviewSection
                    .padding(.top, ArchSpacing.xxl)
            }
            .padding(ArchSpacing.screenMargin)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ArchColor.night)
        .navigationTitle("")
        .sheet(isPresented: $isAsking) {
            PhotoReviewSheet { note in
                onAskForReview(note)
                isAsking = false
            }
        }
    }

    /// Two different pieces of news, and only one of them is bad.
    ///
    /// A main-photo rule does not take the photograph down — it says this one
    /// cannot be the one people meet you with. Saying "not on your profile" there
    /// would be false, and would send somebody off to delete a photograph that is
    /// fine.
    private var title: String {
        reason.isMainPhotoRule
            ? "This cannot be your first photo"
            : "One of your photos is not on your profile"
    }

    private var opening: String {
        reason.isMainPhotoRule
            ? "Your first photo is what people see in their five, so it has to be one "
              + "clear photograph of you on your own — and \(reason.sentence)."
            : "Arch could not use it because \(reason.sentence)."
    }

    /// Three at most, and the third only when it is true.
    private var consequences: [String] {
        if reason.isMainPhotoRule {
            return [
                "It is still on your profile, exactly where it is.",
                "Only the first one has to be of you on your own. The rest are "
                    + "yours — where you were, what you made, who you were with.",
                "Drag another photo to the front and this one moves down."
            ]
        }
        var lines = [
            "It was not shown to anyone, and never has been.",
            "Your other photos are on your profile as normal."
        ]
        if remaining < Person.requiredPhotos {
            // Said once, plainly, and not as an alarm. A profile below the floor is
            // a thing to fix rather than a punishment.
            lines.append(
                "A profile needs \(ArchCopy.word(Person.requiredPhotos)) photos, "
                + "so adding another is the quickest way back."
            )
        }
        return lines
    }

    /// Both quiet. The app is not pushing the reader toward either one — replacing
    /// the photograph is usually faster, and asking for a second look is legitimate.
    /// "Choose another" is wrong when the photograph is not going anywhere.
    private var chooseTitle: String {
        reason.isMainPhotoRule ? "Rearrange my photos" : "Choose another"
    }

    @ViewBuilder
    private var reviewSection: some View {
        switch review {
        case .notSent:
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                ArchButton(title: chooseTitle, kind: .quiet, action: onChooseAnother)
                ArchButton(title: "Ask us to look again", kind: .quiet) { isAsking = true }
                Text("One person looks at every photo that is sent back. It usually takes a day.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .sent:
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                ArchButton(title: chooseTitle, kind: .quiet, action: onChooseAnother)
                VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                    Text("A person is looking at it")
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                    Text("You can add a different photo in the meantime, and this one will appear if it is cleared.")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        case .answered:
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                ArchButton(title: chooseTitle, kind: .quiet, action: onChooseAnother)
                VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                    Text("A person looked at it again")
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                    // Refuses to imply it is coming back, for the same reason
                    // `AppealSheet` does.
                    Text("The decision stands, and there is no second look. Another photo is the way on.")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Asking for a second look.
///
/// Modelled on `AppealSheet`, including the part that matters: **it does not imply
/// the photograph is coming back.** Most photographs sent back stay back, and a
/// sheet that suggested otherwise would be collecting hope rather than information.
struct PhotoReviewSheet: View {
    let onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    private static let limit = 500

    private var trimmed: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            Text("Tell us what we missed")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            Text("A person reads this. If the photo is of you and something about it was misread, say so here.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                "",
                text: $note,
                prompt: Text("What do you think we got wrong?")
                    .foregroundColor(ArchColor.mortar),
                axis: .vertical
            )
            .archText(.callout)
            .foregroundStyle(ArchColor.limestone)
            .lineLimit(4...8)
            .padding(ArchSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(ArchColor.night)
            )
            .onChange(of: note) { _, new in
                if new.count > Self.limit { note = String(new.prefix(Self.limit)) }
            }

            ArchButton(title: "Send", kind: .quiet, isEnabled: !trimmed.isEmpty) {
                onSend(trimmed)
            }

            Text("Your other photos are unaffected while this is read.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .archSheetBackground()
    }
}

#Preview("Not of you") {
    NavigationStack {
        PhotoRejectedView(
            photo: MockData.you.photos[0],
            reason: .notYou,
            remaining: 5,
            onChooseAnother: {},
            onAskForReview: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Below the floor") {
    NavigationStack {
        PhotoRejectedView(
            photo: MockData.you.photos[1],
            reason: .moreThanOnePerson,
            remaining: 3,
            onChooseAnother: {},
            onAskForReview: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Already looked at") {
    NavigationStack {
        PhotoRejectedView(
            photo: MockData.you.photos[2],
            reason: .screenshot,
            remaining: 5,
            review: .answered,
            onChooseAnother: {},
            onAskForReview: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}
