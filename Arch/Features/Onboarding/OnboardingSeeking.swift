import SwiftUI

/// Who you want to meet.
///
/// Its own step rather than another row on "About you", because it is not a fact
/// about you — it is a *requirement*, and it belongs with the questionnaire's
/// three hard ones rather than with your height. Arch will not put anyone outside
/// it in your roster however well everything else lines up.
///
/// **Multi-select, and no "Everyone".** A word that stands in for a list is a word
/// that hides what is in the list. Picking all three says the same thing and says
/// it plainly.
///
/// Like the questionnaire, the answer never appears on your profile and nobody is
/// told what you chose.
struct OnboardingSeeking: View {
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "Who you want to meet",
                detail: "Pick as many as apply. Arch will not put anyone outside this in your five."
            )

            VStack(spacing: ArchSpacing.xs) {
                ForEach(Gender.allCases) { option in
                    OptionRow(
                        text: option.plural,
                        isSelected: store.seekingDrafts.contains(option)
                    ) {
                        toggle(option)
                    }
                }
            }

            Text("This is not shown on your profile, and nobody is told what you picked. You can change it in Settings.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Deselecting is allowed right down to one. Emptying it is not — an empty
    /// preference is a preference for nobody, and the Continue button would simply
    /// stop working with nothing on screen saying why.
    private func toggle(_ option: Gender) {
        withAnimation(ArchMotion.quick) {
            if store.seekingDrafts.contains(option) {
                guard store.seekingDrafts.count > 1 else { return }
                store.seekingDrafts.remove(option)
            } else {
                store.seekingDrafts.insert(option)
            }
        }
    }
}

#Preview("Nothing picked yet") {
    OnboardingSeeking(store: OnboardingStore())
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

#Preview("Two picked") {
    OnboardingSeeking(
        store: .configured { $0.seekingDrafts = [.woman, .nonBinary] }
    )
    .padding(ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
