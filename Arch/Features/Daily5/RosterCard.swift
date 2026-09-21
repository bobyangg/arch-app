import SwiftUI

/// One person in your five.
///
/// The photograph is the tap target and it is left completely clean — no overlay,
/// no corner control. The dismiss affordance sits at the trailing edge of the name
/// row instead: still at the card's edge, but a text-row control rather than a
/// destructive button parked on top of the thing you actually want to tap.
///
/// Nothing here is ranked, scored or badged. The order of the list carries the
/// ranking and nothing else needs to say it.
struct RosterCard: View {
    let person: Person
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Button(action: onOpen) {
                // **The url was never passed, so this could only ever draw the
                // tone.** `ArchBackend.roster()` fetches the photographs and
                // signs their URLs in the same batch it fetches the people, so
                // the picture was loaded, in memory, and thrown away one
                // argument short of the screen. Opening the profile worked
                // because `ProfileDetailView` does pass it.
                PhotoPlaceholder(toneIndex: person.avatarToneIndex,
                                 url: person.mainPhoto?.url,
                                 data: person.mainPhoto?.local)
                    .aspectRatio(PhotoCard.aspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: ArchRadius.photo, style: .continuous))
            }
            .buttonStyle(PressScaleStyle(scale: 0.99))
            .accessibilityLabel(person.name)
            .accessibilityHint("Opens \(person.name)'s profile")

            HStack(alignment: .firstTextBaseline, spacing: ArchSpacing.s) {
                Button(action: onOpen) {
                    Text(person.name)
                        .archText(.titleM)
                        .foregroundStyle(ArchColor.limestone)
                }
                .buttonStyle(PressScaleStyle(scale: 1))
                .accessibilityHidden(true)

                Spacer(minLength: 0)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.mortar)
                        .frame(
                            width: ArchSpacing.minimumTapTarget,
                            height: ArchSpacing.minimumTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Dismiss \(person.name)")
                .accessibilityHint("Asks you to confirm first")
                // Pulled back so the 44pt target still lines up with the margin.
                .padding(.trailing, -ArchSpacing.s)
                .offset(y: ArchSpacing.xxs)
            }

            VitalsRow(vitals: person.vitals)
        }
    }
}

#Preview("Roster card") {
    ScrollView {
        VStack(spacing: ArchSpacing.cardGap) {
            RosterCard(person: MockData.nadia, onOpen: {}, onDismiss: {})
            RosterCard(person: MockData.teo, onOpen: {}, onDismiss: {})
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.vertical, ArchSpacing.xl)
    }
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
