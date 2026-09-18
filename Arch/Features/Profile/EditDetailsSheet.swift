import SwiftUI

/// The facts under your name.
///
/// Neighbourhood and city are two fields but one chip — `Person.location` joins
/// them, so nothing else in the app has to decide how that string is written.
///
/// Height is a picker rather than a field, and gender is three rows rather than a
/// menu. Both were free text once; neither is comparable between two profiles when
/// it is.
struct EditDetailsSheet: View {
    let person: Person
    let onSave: (PersonDetails) -> Void

    @State private var name = ""
    @State private var age = ""
    @State private var gender: Gender?
    @State private var pronouns = ""
    @State private var place: Place?
    @State private var height = ""
    @State private var work = ""
    @State private var isPickingPlace = false
    /// Held by the view, not made inside the button: `CLLocationManager` answers
    /// through a delegate, and one created inside a closure is deallocated
    /// before iOS calls back. The symptom is a button that does nothing.
    @State private var location = DeviceLocation()
    @State private var locationPermission = LocationPermission.notAsked
    @State private var locationNote: String?
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && gender != nil
            && place != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                Text("Your details")
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                    .padding(.top, ArchSpacing.l)

                VStack(spacing: ArchSpacing.xs) {
                    ArchField(text: $name, label: "Name")
                    // **Age and height are shown and not edited.**
                    //
                    // Age never was editable in any meaningful sense -- it was a
                    // field over a birthdate recomputed from whatever number was
                    // in it, so saving an edit to your job title moved your
                    // birthday. It is worked out from a date now, and a date does
                    // not change.
                    //
                    // Height is frozen for the product reason rather than a
                    // technical one: an age and a height somebody can quietly
                    // revise are the two facts a profile is least able to be
                    // trusted on, and the profile is supposed to be the one
                    // somebody read yesterday. A genuine mistake is a support
                    // question, not a settings screen.
                    FixedRow(label: "Age", value: age)
                    PlaceRow(place: place) { isPickingPlace = true }
                    FixedRow(label: "Height", value: height)
                    ArchField(text: $work, label: "Work")
                }

                Text("Your age and height are set when you sign up and cannot be changed here.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)

                genderSection

                ArchField(text: $pronouns, label: "Pronouns", placeholder: "Optional")

                ArchButton(title: "Save", isEnabled: isValid) {
                    onSave(
                        PersonDetails(
                            name: name.trimmingCharacters(in: .whitespaces),
                            age: Int(age) ?? person.age,
                            gender: gender,
                            pronouns: pronouns.trimmingCharacters(in: .whitespaces),
                            place: place,
                            height: height,
                            work: work.trimmingCharacters(in: .whitespaces)
                        )
                    )
                }
                .padding(.top, ArchSpacing.s)

                ArchTextButton(title: "Cancel") { dismiss() }
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.bottom, ArchSpacing.m)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.stone)
        .presentationDetents([.height(720)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .archSheetBackground()
        .sheet(isPresented: $isPickingPlace) {
            PlacePickerView(
                permission: locationPermission,
                current: place,
                onChoose: { place = $0; isPickingPlace = false },
                // **This was a dead button.** The picker draws "Use my location"
                // whenever permission is not `.denied`, and `onUseLocation`
                // defaults to doing nothing — so on this screen, unlike in
                // onboarding, tapping it did exactly that. Nothing said so.
                //
                // The place that comes back carries the device fix as its
                // centre, so saving moves your stored position as well as the
                // words -- which is the point of tapping it. A place loaded from
                // the server has no centre, and that is what keeps an edit you
                // made to your job title from moving you.
                onUseLocation: {
                    locationNote = nil
                    guard ArchConfig.isConfigured else {
                        let fix = Coordinate(latitude: 40.6913, longitude: -73.9742)
                        place = PlaceLibrary.nearest(to: fix)
                        locationPermission = .granted
                        isPickingPlace = false
                        return
                    }
                    location.request { outcome in
                        switch outcome {
                        case .fix(let point):
                            locationPermission = .granted
                            Task { @MainActor in
                                if let found = await PlaceSearch.place(at: point) {
                                    place = found
                                    // Closing is the feedback: a geocoded place
                                    // is not in the list below, so a successful
                                    // tap changed nothing visible on this screen.
                                    isPickingPlace = false
                                } else {
                                    locationNote = "Arch found where you are but "
                                        + "could not name it. Search for your town "
                                        + "— it is exact either way."
                                }
                            }
                        case .refused:
                            locationPermission = .denied
                        case .unavailable:
                            locationNote = "Arch could not get a position just "
                                + "now. Search for your town instead."
                        }
                    }
                },
                onCancel: { isPickingPlace = false },
                locationNote: locationNote
            )
            .padding(.horizontal, ArchSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ArchColor.stone)
            .presentationDetents([.large])
            .presentationCornerRadius(ArchRadius.sheet)
            .archSheetBackground()
        }
        .onAppear {
            let details = person.details
            name = details.name
            age = details.age == 0 ? "" : "\(details.age)"
            gender = details.gender
            pronouns = details.pronouns
            place = details.place
            height = details.height
            work = details.work
        }
    }

    // MARK: Pieces

    private var genderSection: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
            Text("Gender")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)

            ForEach(Gender.allCases) { option in
                OptionRow(text: option.label, isSelected: gender == option) {
                    gender = option
                }
            }
        }
    }

}

#Preview("Edit details") {
    EditDetailsSheet(person: MockData.you) { _ in }
        .frame(height: 720)
        .preferredColorScheme(.dark)
}
