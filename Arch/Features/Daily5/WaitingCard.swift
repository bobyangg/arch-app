import SwiftUI

/// Somebody you dismissed today, who has not gone yet.
///
/// A dismissal is scheduled rather than applied: it lands at nine tomorrow
/// morning, when the new roster is built and they leave in the same move their
/// replacement arrives in. Until then this card is where they sit.
///
/// **Quieter than a person's card and louder than an open slot**, which is where
/// it belongs — these are people you have decided about, so they should not pull
/// at you the way the five do, but they are still reachable and the card has to
/// say so rather than read like a receipt.
///
/// No countdown and no "act now". When the roster refills is a fact and it is
/// already on the open slots above; repeating it here as a deadline would turn a
/// decision you have already made into one you have to defend.
struct WaitingCard: View {
    let person: Person
    let onOpen: () -> Void
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: ArchSpacing.s) {
            Button(action: onOpen) {
                HStack(spacing: ArchSpacing.s) {
                    PhotoPlaceholder(toneIndex: person.avatarToneIndex,
                                     url: person.mainPhoto?.url,
                                     data: person.mainPhoto?.local)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: ArchRadius.control,
                                                    style: .continuous))

                    Text(person.name)
                        .archText(.body)
                        .foregroundStyle(ArchColor.limestone)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())

            ArchTextButton(title: "Put back", action: onRestore)
        }
        .padding(ArchSpacing.s)
        .archGlassCard(radius: ArchRadius.card)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Waiting") {
    VStack(spacing: ArchSpacing.cardGap) {
        WaitingCard(person: MockData.people[0], onOpen: {}, onRestore: {})
        WaitingCard(person: MockData.people[1], onOpen: {}, onRestore: {})
    }
    .padding(.horizontal, ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
