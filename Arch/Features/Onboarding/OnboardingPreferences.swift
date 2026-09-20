import SwiftUI

/// Who Arch should be looking for, in miles and in years.
///
/// **Asked here rather than left on a default nobody sees.** These two are the
/// hardest filters in the app -- the matcher refuses a pair outside either of
/// them, in both directions -- and they were being set for everybody to 25 miles
/// and 26 to 36 in `createDiscovery`, a line of code no reader ever met. Somebody
/// who is 22, or who lives an hour outside a city, was quietly given a rule that
/// did not fit them and no reason to look for it in Settings.
///
/// It sits after the questions about *you* and before the photographs, because
/// it is the first screen that is about anybody else, and because four
/// photographs is the longest step in onboarding and a sensible place to have
/// already made the cheap decisions.
///
/// Both are changeable in Settings for ever afterwards. Nothing here is a
/// commitment, which is why the screen says so rather than making the reader
/// wonder.
struct OnboardingPreferences: View {
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "Who you are looking for",
                detail: "Both of these are filters, not preferences — nobody outside them goes in your five, and you do not go in theirs."
            )

            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text("Age")
                    .archText(.prompt)
                    .foregroundStyle(ArchColor.mortar)

                Text(store.ageRangeText)
                    .archText(.titleL)
                    .foregroundStyle(ArchColor.limestone)
                    .contentTransition(.numericText())
                    .animation(ArchMotion.quick, value: store.minAgeDraft)
                    .animation(ArchMotion.quick, value: store.maxAgeDraft)

                RangeSlider(
                    low: Binding(get: { store.minAgeDraft }, set: { store.minAgeDraft = $0 }),
                    high: Binding(get: { store.maxAgeDraft }, set: { store.maxAgeDraft = $0 }),
                    bounds: SettingsStore.ageRange,
                    minimumSpan: 2
                )

                ends(low: "\(SettingsStore.ageRange.lowerBound)",
                     high: "\(SettingsStore.ageRange.upperBound)")
            }

            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text("Distance")
                    .archText(.prompt)
                    .foregroundStyle(ArchColor.mortar)

                Text(store.distanceText)
                    .archText(.titleL)
                    .foregroundStyle(ArchColor.limestone)
                    .contentTransition(.numericText())
                    .animation(ArchMotion.quick, value: store.distanceDraft)

                ValueSlider(
                    value: Binding(get: { store.distanceDraft }, set: { store.distanceDraft = $0 }),
                    bounds: SettingsStore.distanceRange,
                    label: "Distance"
                )

                // "Anywhere" rather than "100 miles", because the top of the
                // slider switches the filter off rather than drawing a
                // hundred-mile circle -- and a reader has no way to know that
                // from a number.
                ends(low: "\(SettingsStore.distanceRange.lowerBound) miles",
                     high: "Anywhere")
            }

            Text("Widening either one does not get you more people at once. It gives Arch more to choose your five from. You can change both in Settings whenever you like.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ends(low: String, high: String) -> some View {
        HStack {
            Text(low)
            Spacer(minLength: 0)
            Text(high)
        }
        .archText(.footnote)
        .foregroundStyle(ArchColor.mortar)
    }
}

#Preview("Who you are looking for") {
    OnboardingPreferences(store: OnboardingStore())
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

#Preview("Widened") {
    OnboardingPreferences(store: {
        let s = OnboardingStore()
        s.minAgeDraft = 21; s.maxAgeDraft = 45
        s.distanceDraft = SettingsStore.distanceRange.upperBound
        return s
    }())
    .padding(ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
