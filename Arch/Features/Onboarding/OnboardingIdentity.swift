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
/// on. Pronouns are chips for the same reason, with a field kept for whatever the
/// chips leave out; they are the one optional thing on the screen and say so.
struct OnboardingAbout: View {
    let store: OnboardingStore

    @State private var isPickingHeight = false
    @State private var isPickingPlace = false
    @State private var locationNote: String?
    /// Held by the view rather than made inside the button, because
    /// `CLLocationManager` answers through a delegate — one created inside a
    /// closure is deallocated before iOS calls back, and the callback never
    /// arrives. The symptom is a button that does nothing, intermittently.
    @State private var location = DeviceLocation()

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

            PronounPicker(
                text: Binding(get: { store.pronounsDraft }, set: { store.pronounsDraft = $0 }),
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
                // Real in a real build, stood in for in a design one.
                //
                // The design build keeps the stub for two reasons rather than
                // laziness: a simulator has no location to give, and the UI tests
                // run there -- a permission prompt they cannot answer would hang
                // them. The fix it invents is Fort Greene, which is where the mock
                // profile lives.
                onUseLocation: {
                    locationNote = nil
                    guard ArchConfig.isConfigured else {
                        let fix = Coordinate(latitude: 40.6913, longitude: -73.9742)
                        store.useDeviceLocation(
                            fix, place: PlaceLibrary.nearest(to: fix)
                        )
                        isPickingPlace = false
                        return
                    }
                    location.request { outcome in
                        switch outcome {
                        case .fix(let point):
                            // The name for the point comes from the geocoder, so
                            // this is a second round trip and has to be awaited.
                            // The position is applied either way -- a nameless
                            // fix still places you for the distance filter.
                            Task { @MainActor in
                                let found = await PlaceSearch.place(at: point)
                                store.useDeviceLocation(point, place: found)
                                if found == nil {
                                    locationNote = "Arch found where you are but "
                                        + "could not name it. Search for your town "
                                        + "— it is exact either way."
                                } else {
                                    // **Closing is the feedback.** A place from a
                                    // geocoder is not in the list below, so on
                                    // success nothing on this screen changed and
                                    // the button looked broken. The chip on the
                                    // step behind now says where you are.
                                    isPickingPlace = false
                                }
                            }
                        case .refused:
                            // Not an error and not worth a screen. The list under
                            // the button is the same list either way, and it was
                            // always the path rather than the fallback.
                            store.refuseDeviceLocation()
                        case .unavailable:
                            // Distinct from a refusal: they did not say no, the
                            // device could not answer. Hiding the button here
                            // would read as "you denied this", which is a lie.
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
