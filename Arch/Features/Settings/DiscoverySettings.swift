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
                    bounds: SettingsStore.distanceRange
                )

                HStack {
                    Text("\(SettingsStore.distanceRange.lowerBound) miles")
                    Spacer()
                    Text("\(SettingsStore.distanceRange.upperBound) miles")
                }
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
            }

            SettingNote("Everyone in \(store.rosterName) is inside this. Widening it gives Arch more people to choose from — it does not give you more slots.")
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

            SettingNote("Arch will not put anyone outside this in \(store.rosterName), and will not put you in theirs.")
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

            SettingNote("Arch will not put anyone outside this in \(store.rosterName), whatever else lines up. It is not shown on your profile, and nobody is told what you picked.")
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

            SettingNote("This is used to choose \(store.rosterName). It is not shown on your profile, and nobody is told what you picked.")
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
