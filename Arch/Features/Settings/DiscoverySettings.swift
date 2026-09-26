import SwiftUI

/// How far away people can be.
///
/// The note is the important part: widening the radius does not get you more
/// people at once. It gets Arch more to choose five from. Every distance control
/// in every other app means "more results", and this one does not.
struct DistanceSetting: View {
    let store: SettingsStore

    var body: some View {
        SettingsPage(title: "Distance") {
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text(store.distanceText)
                    .archText(.titleL)
                    .foregroundStyle(ArchColor.limestone)
                    .contentTransition(.numericText())
                    .animation(ArchMotion.quick, value: store.distance)

                ValueSlider(
                    value: Binding(get: { store.distance }, set: { store.distance = $0 }),
                    bounds: SettingsStore.distanceRange,
                    label: "Distance"
                )

                HStack {
                    Text("\(SettingsStore.distanceRange.lowerBound) miles")
                    Spacer()
                    Text("Anywhere")
                }
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
            }

            SettingNote("Everyone in \(store.rosterName) is inside this. Widening it gives Arch more people to choose from. It does not give you more spots.")

            SettingNote("Measured from where you live, never shown to anybody. Arch puts no distance on a profile and never sorts people by how near they are.")
        }
    }
}

/// The ages you want to be shown.
struct AgeSetting: View {
    let store: SettingsStore

    var body: some View {
        SettingsPage(title: "Age range") {
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text(store.ageText)
                    .archText(.titleL)
                    .foregroundStyle(ArchColor.limestone)

                RangeSlider(
                    low: Binding(get: { store.minAge }, set: { store.minAge = $0 }),
                    high: Binding(get: { store.maxAge }, set: { store.maxAge = $0 }),
                    bounds: SettingsStore.ageRange,
                    minimumSpan: 2
                )

                HStack {
                    Text("\(SettingsStore.ageRange.lowerBound)")
                    Spacer()
                    Text("\(SettingsStore.ageRange.upperBound)")
                }
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
            }

            SettingNote("Arch will not put people outside this in your matches, and will not put you in theirs.")
        }
    }
}

/// Who you want to meet.
///
/// A requirement, not a weight. It sits in Discovery with distance and age because
/// that is where you would look for it, but it behaves like the questionnaire's
/// three hard questions: nobody outside it reaches you, whatever else lines up.
struct SeekingSetting: View {
    let store: SettingsStore

    var body: some View {
        SettingsPage(title: "Who you want to meet") {
            VStack(spacing: ArchSpacing.xs) {
                ForEach(Gender.allCases) { option in
                    OptionRow(
                        text: option.plural,
                        isSelected: store.seeking.contains(option)
                    ) {
                        withAnimation(ArchMotion.quick) { store.toggleSeeking(option) }
                    }
                }
            }

            SettingNote("Arch will not put people outside this in your matches, whatever else lines up. It is not shown on your profile, and nobody is told what you picked.")
        }
    }
}

/// What you are here for.
struct IntentionSetting: View {
    let store: SettingsStore

    var body: some View {
        SettingsPage(title: "Looking for") {
            VStack(spacing: ArchSpacing.xs) {
                ForEach(SettingsStore.intentions, id: \.self) { option in
                    OptionRow(text: option, isSelected: store.lookingFor == option) {
                        store.lookingFor = option
                    }
                }
            }

            SettingNote("This is used to choose your matches. It is not shown on your profile, and nobody is told what you picked.")
        }
    }
}

/// Where you are.
///
/// On the profile, not in discovery settings, because it is the chip under your
/// name as much as it is a filter -- but this is where somebody looks for it, so
/// this is where the row is. The screen changes the profile through the same
/// `updateDetails` the details sheet uses, so there is one write and one rule
/// about what it does to your stored position.
///
/// **Two ways to set it, and neither of them starts out closed.** Everybody can
/// put themselves where their phone says they are, always. Choosing a place you
/// are not in -- the city you are moving to next month, the one you are in every
/// other week -- is free at signup and once afterwards; doing it again and again
/// is what Arch Premium buys.
///
/// Onboarding used to allow the search and this screen used to refuse it, which
/// gave a free account exactly one chance to set a town it was not in and no way
/// to correct it -- and the moment somebody most needs to change their town is
/// right after they find out it is wrong. One live profile was labelled Toronto
/// and positioned in Vancouver with no route out of it.
struct LocationSetting: View {
    let store: SettingsStore
    var profile: ProfileStore?
    var onOpenPremium: () -> Void = {}

    @State private var isPicking = false
    /// Held by the view, not made inside the button, for the reason given on
    /// `EditDetailsSheet.location`: a manager made in a closure is gone before
    /// iOS answers it.
    @State private var location = DeviceLocation()
    @State private var locationPermission = LocationPermission.notAsked
    @State private var locationNote: String?

    private var place: Place? { profile?.person.place }

    var body: some View {
        SettingsPage(title: "Where you are") {
            Text(place?.label ?? "Not set")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            SettingNote("This location is shown under your name. With your distance preference it sets boundaries on who you are able to match with. Arch keeps it to about a kilometre and never shows anybody how far away you are.")

            ArchButton(title: "Change", action: { isPicking = true })

            if !store.isSubscribed {
                // Two different sentences, because "you cannot" and "you can, once"
                // are two different situations and one line covering both would be
                // wrong in whichever one the reader is in.
                SettingNote(store.canChangePlace
                    ? "You can change your town by name once. After that it is part of Arch Premium. Putting you where your phone says you are stays free either way."
                    : "You have already changed your town once. Changing it again is part of Arch Premium. Putting you where your phone says you are stays free.")
            }
        }
        .sheet(isPresented: $isPicking) {
            PlacePickerView(
                permission: locationPermission,
                current: place,
                onChoose: { choose($0) },
                onUseLocation: useDeviceLocation,
                onCancel: { isPicking = false },
                locationNote: locationNote,
                canChoose: store.canChangePlace,
                onOpenPremium: { isPicking = false; onOpenPremium() }
            )
            .padding(.horizontal, ArchSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ArchColor.stone)
            .presentationDetents([.large])
            .presentationCornerRadius(ArchRadius.sheet)
            .archSheetBackground()
        }
    }

    /// The one write. Everything else on the details row is carried through
    /// unchanged, and the place arrives carrying its centre, which is what moves
    /// the stored position.
    private func choose(_ chosen: Place) {
        guard let profile else { return }
        var details = profile.person.details
        let moved = details.place?.id != chosen.id
        details.place = chosen
        profile.updateDetails(details)
        if moved { store.placeDidChange() }
        isPicking = false
    }

    /// The same path `EditDetailsSheet` takes, with the same stand-in for a
    /// design build, which has no location to give and UI tests that cannot
    /// answer a permission prompt.
    private func useDeviceLocation() {
        locationNote = nil
        guard ArchConfig.isConfigured else {
            let fix = Coordinate(latitude: 40.6913, longitude: -73.9742)
            locationPermission = .granted
            if let found = PlaceLibrary.nearest(to: fix) { choose(found) }
            return
        }
        location.request { outcome in
            switch outcome {
            case .fix(let point):
                locationPermission = .granted
                Task { @MainActor in
                    if let found = await PlaceSearch.place(at: point) {
                        choose(found)
                    } else {
                        locationNote = "Arch found where you are but could not "
                            + "name it. Try again in a moment."
                    }
                }
            case .refused:
                locationPermission = .denied
            case .unavailable:
                locationNote = "Arch could not get a position just now."
            }
        }
    }
}

#Preview("Distance") {
    NavigationStack { DistanceSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

#Preview("Age range") {
    NavigationStack { AgeSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

#Preview("Looking for") {
    NavigationStack { IntentionSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

#Preview("Who you want to meet") {
    NavigationStack { SeekingSetting(store: SettingsStore()) }
        .preferredColorScheme(.dark)
}

#Preview("Where you are") {
    NavigationStack {
        LocationSetting(store: SettingsStore(), profile: ProfileStore(person: MockData.you))
    }
    .preferredColorScheme(.dark)
}
