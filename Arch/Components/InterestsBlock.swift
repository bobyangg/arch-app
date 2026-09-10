import SwiftUI

/// Three short things someone is into, sitting in the profile scroll after the
/// second photo.
///
/// Not a card. The chips already carry `stone`, and a `stone` card behind them
/// would be a surface on a surface — so this is a labelled group on `night`
/// instead, which also keeps it distinct from the photo and answer cards it sits
/// between.
///
/// Interests are **not** tappable. Everywhere else in a profile, tapping selects
/// something to write your first message about; a two-word tag is not a statement
/// you can respond to, and "Say something about: Room tone" is worse than no quote
/// at all.
struct InterestsBlock: View {
    let interests: [Interest]
    /// Your own profile: shows the edit affordance and the remaining empty slots.
    var isOwn: Bool = false
    var onEdit: (() -> Void)?

    private var emptySlots: Int {
        isOwn ? max(0, Person.requiredInterests - interests.count) : 0
    }

    var body: some View {
        if interests.isEmpty && !isOwn {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Interests")
                        .archText(.prompt)
                        .foregroundStyle(ArchColor.mortar)
                    Spacer(minLength: 0)
                    if isOwn, let onEdit {
                        CardAffordanceView(
                            affordance: .edit(action: onEdit),
                            subject: "your interests"
                        )
                        .padding(.trailing, -ArchSpacing.xs)
                        .padding(.vertical, -ArchSpacing.s)
                    }
                }

                FlowLayout(spacing: ArchSpacing.xs, lineSpacing: ArchSpacing.xs) {
                    ForEach(interests) { interest in
                        InterestChip(text: interest.text)
                    }
                    ForEach(0..<emptySlots, id: \.self) { _ in
                        AddInterestChip()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Heavier than a vitals chip — `limestone` at 13 rather than `mortar` at 12 —
/// because an interest is something the person wrote, not metadata about them.
struct InterestChip: View {
    let text: String

    var body: some View {
        Text(text)
            .archText(.footnote)
            .foregroundStyle(ArchColor.limestone)
            .padding(.horizontal, ArchSpacing.s)
            .padding(.vertical, ArchSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(ArchColor.stone)
            )
    }
}

/// An interest you have not written yet. Outlined rather than dashed — a dashed
/// border reads as an error to be fixed, and an unfinished profile is not an error.
struct AddInterestChip: View {
    var body: some View {
        HStack(spacing: ArchSpacing.xxs) {
            Image(systemName: "plus")
                .archText(.caption)
            Text("Add an interest")
                .archText(.footnote)
        }
        .foregroundStyle(ArchColor.mortar)
        .padding(.horizontal, ArchSpacing.s)
        .padding(.vertical, ArchSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                .strokeBorder(ArchColor.quietBorder, lineWidth: 1)
        )
    }
}

// MARK: - Previews

#Preview("Interests") {
    VStack(alignment: .leading, spacing: ArchSpacing.xxxl) {
        InterestsBlock(interests: MockData.nadia.interests)
        InterestsBlock(interests: MockData.lena.interests)
        InterestsBlock(
            interests: MockData.you.interests,
            isOwn: true,
            onEdit: {}
        )
        InterestsBlock(
            interests: Array(MockData.you.interests.prefix(1)),
            isOwn: true,
            onEdit: {}
        )
    }
    .padding(ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
