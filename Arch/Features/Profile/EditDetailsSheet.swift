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
    @State private var isPickingHeight = false
    /// **Only when the profile arrived without one.** Every exactly-round height
    /// was lost to a conversion that required two numbers and got one, so there
    /// are profiles with no height at all — and freezing the field outright
    /// would freeze those empty forever. Filling a blank is not changing a
    /// value; a height that is already there stays put.
    @State private var canSetHeight = false
    /// Held by the view, not made inside the button: `CLLocationManager` answers
    /// through a delegate, and one created inside a closure is deallocated
    /// before iOS calls back. The symptom is a button that does nothing.
    @State private var location = DeviceLocation()
    @State private var locationPermission = LocationPermission.notAsked
    @State private var locationNote: String?
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool { place != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                Text("Your details")
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                    .padding(.top, ArchSpacing.l)

                VStack(spacing: ArchSpacing.xs) {
                    // **The name is what somebody was introduced to you as.**
                    // Changing it after the fact means the person in a
                    // conversation is not the person on the profile any more,
                    // and there is no notice anywhere that would say so.
                    FixedRow(label: "Name", value: name)
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
                    // **Gender joins the settled facts.** Pronouns sit below and
                    // stay editable, which is the distinction worth keeping: what
                    // you are is what somebody was shown, and what you are called
                    // is yours to correct.
                    FixedRow(label: "Gender", value: gender?.label ?? "")
                    PlaceRow(place: place) { isPickingPlace = true }
                    if canSetHeight {
                        HeightRow(height: height) { isPickingHeight = true }
                    } else {
                        FixedRow(label: "Height", value: height)
                    }
                    ArchField(text: $work, label: "Work")
                }

                Text(canSetHeight
                     ? "Your name, age and gender cannot be changed here. Your height is missing — once you set it, it stays."
                     : "Your name, age, gender and height are set when you sign up and cannot be changed here.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)

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
            // Decided once, on the way in. Reading it from `height` later would
            // flip the row back to fixed the moment one was chosen, mid-edit.
            canSetHeight = details.height.isEmpty
        }
        .sheet(isPresented: $isPickingHeight) {
            HeightPickerSheet(current: height) { height = $0 }
        }
    }

    // MARK: Pieces

}

#Preview("Edit details") {
    EditDetailsSheet(person: MockData.you) { _ in }
        .frame(height: 720)
        .preferredColorScheme(.dark)
}
