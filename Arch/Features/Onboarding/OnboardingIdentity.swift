import SwiftUI

/// Your name.
///
/// The email field is gone: signing in with Apple already supplied one, usually a
/// private relay address, and asking again would be asking for something Arch
/// already has and does not show to anybody.
///
/// The name arrives filled in for the same reason, and stays editable — Apple hands
/// over whatever is on the Apple ID, which is not always what somebody wants a
/// stranger to read.
struct OnboardingIdentity: View {
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "Your name",
                detail: "This is what people see. Apple gave us the one on your account — change it if it is not what you go by."
            )

            VStack(spacing: ArchSpacing.xs) {
                ArchField(
                    text: Binding(get: { store.name }, set: { store.name = $0 }),
                    label: "Name",
                    placeholder: "Sam",
                    surface: ArchColor.stone
                )
            }

            Text("Your Apple email is never shown to anyone, and Arch only uses it for account notices.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
        }
    }
}

/// Age, gender, where you live, height, work.
///
/// Where you live is picked from a list rather than typed. Free text gave three
/// spellings of Bed-Stuy and no position at all, which left the distance filter
/// with nothing to filter on — and the name you pick is the chip a stranger reads,
/// so it may as well be the same value the matcher uses.
///
/// Height is a picker. It was a text field, which accepted "tall" and "1.8m" and
/// every other way people write this, none of which two profiles can be compared
/// on. Pronouns are the one optional thing on the screen and are marked as such.
struct OnboardingAbout: View {
    let store: OnboardingStore

    @State private var isPickingHeight = false
    @State private var isPickingPlace = false

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "About you",
                detail: "The facts that sit under your name. Nothing else is asked."
            )

            VStack(spacing: ArchSpacing.xs) {
                ArchField(
                    text: Binding(get: { store.ageText }, set: { store.ageText = $0 }),
                    label: "Age",
                    placeholder: "30",
                    keyboard: .numberPad,
                    surface: ArchColor.stone
                )
                PlaceRow(place: store.place, surface: ArchColor.stone) {
                    isPickingPlace = true
                }
                HeightRow(
                    height: store.height,
                    surface: ArchColor.stone
                ) { isPickingHeight = true }
                ArchField(
                    text: Binding(get: { store.work }, set: { store.work = $0 }),
                    label: "Work",
                    placeholder: "Sound engineer",
                    surface: ArchColor.stone
                )
            }

            VStack(alignment: .leading, spacing: ArchSpacing.xs) {
                Text("Gender")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                ForEach(Gender.allCases) { option in
                    OptionRow(text: option.label, isSelected: store.genderDraft == option) {
                        store.genderDraft = option
                    }
                }
            }

            ArchField(
                text: Binding(get: { store.pronounsDraft }, set: { store.pronounsDraft = $0 }),
                label: "Pronouns",
                placeholder: "Optional",
                characterLimit: 20,
                surface: ArchColor.stone
            )

            if let place = store.place {
                VStack(alignment: .leading, spacing: ArchSpacing.xs) {
                    Text("People will see this as")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                    VitalsChip(text: place.label)
                }
            }
        }
        .sheet(isPresented: $isPickingHeight) {
            HeightPickerSheet(current: store.height) { store.height = $0 }
        }
        .sheet(isPresented: $isPickingPlace) {
            PlacePickerView(
                permission: store.locationPermission,
                current: store.place,
                onChoose: { store.place = $0; isPickingPlace = false },
                // The design build has no CoreLocation, so this stands in for a
                // fix arriving: a point in Fort Greene, coarsened on the way in.
                onUseLocation: {
                    store.useDeviceLocation(
                        Coordinate(latitude: 40.6913, longitude: -73.9742)
                    )
                },
                onCancel: { isPickingPlace = false }
            )
            .padding(.horizontal, ArchSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ArchColor.stone)
            .presentationDetents([.large])
            .presentationCornerRadius(ArchRadius.sheet)
            .presentationBackground(ArchColor.stone)
        }
    }

}

#Preview("Your name") {
    OnboardingIdentity(store: OnboardingStore())
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

#Preview("About you") {
    OnboardingAbout(store: .configured {
        $0.ageText = "30"
        $0.place = PlaceLibrary.place(matching: "bk-fort-greene")
    })
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}
