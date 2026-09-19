import SwiftUI

/// When you were born, asked once and asked first.
///
/// **First, because everything after it is wasted if the answer is no.** Somebody
/// under eighteen who is asked for a birthday on the fifth screen has already
/// written their name, chosen a neighbourhood and uploaded four photographs, and
/// Arch has to then delete all of it. Asking before any of that is collected means
/// there is nothing to delete.
///
/// **Being too young is not a ban and this screen does not treat it as one.**
/// There is no removal record, nothing is sent anywhere, and the pickers stay
/// exactly as they were: the overwhelmingly likely cause of an age of four is a
/// year picked one row off, and a screen that locked on the first wrong answer
/// would punish a scroll. The only thing that happens is that Continue stops
/// working and the reason says so.
struct OnboardingBirthday: View {
    let store: OnboardingStore

    private enum Field: String, Identifiable {
        case year, month, day
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    @State private var picking: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "When were you born?",
                detail: "Your age is worked out from this and shown on your profile. The date itself is never shown to anyone."
            )

            VStack(spacing: ArchSpacing.xs) {
                ChoiceRow(label: "Year",
                          value: store.birthYear.map(String.init) ?? "",
                          surface: ArchColor.stone) { picking = .year }

                ChoiceRow(label: "Month",
                          value: store.birthMonthName,
                          surface: ArchColor.stone) { picking = .month }

                // A day cannot be offered before the month it belongs to is
                // known: "31" is a different promise in June than in May.
                ChoiceRow(label: "Day",
                          value: store.birthDay.map(String.init) ?? "",
                          surface: ArchColor.stone,
                          isEnabled: store.birthYear != nil && store.birthMonth != nil) {
                    picking = .day
                }
            }

            if let birthday = store.birthday {
                if birthday.isOldEnough() {
                    VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                        Text("You are")
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.mortar)
                        VitalsChip(text: "\(birthday.age())")
                    }
                } else {
                    tooYoung(age: birthday.age())
                }
            }
        }
        .sheet(item: $picking) { field in
            ChoiceSheet(title: field.title,
                        options: options(for: field),
                        current: current(for: field)) { choice in
                choose(field, choice)
            }
        }
    }

    /// Said plainly and without a colour that makes it an alarm — no red anywhere
    /// in Arch, and least of all on a screen somebody may have reached by
    /// mis-scrolling a list.
    private func tooYoung(age: Int) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
            Text("Arch is for people 18 and over")
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)
            Text("That date makes you \(age). If it is not right, change it above — "
                 + "nothing has been saved and nothing is held against you.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(ArchColor.stone)
        )
    }

    // MARK: The lists

    private func options(for field: Field) -> [String] {
        switch field {
        case .year:  return Birthday.years().map(String.init)
        case .month: return Birthday.months
        case .day:   return (1...store.daysInChosenMonth).map(String.init)
        }
    }

    private func current(for field: Field) -> String {
        switch field {
        case .year:  return store.birthYear.map(String.init) ?? ""
        case .month: return store.birthMonthName
        case .day:   return store.birthDay.map(String.init) ?? ""
        }
    }

    private func choose(_ field: Field, _ choice: String) {
        switch field {
        case .year:
            store.birthYear = Int(choice)
        case .month:
            store.birthMonth = Birthday.months.firstIndex(of: choice).map { $0 + 1 }
        case .day:
            store.birthDay = Int(choice)
        }
        picking = nil
    }
}

#Preview("Nothing chosen") {
    OnboardingBirthday(store: OnboardingStore())
        .padding(.horizontal, ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

#Preview("Old enough") {
    OnboardingBirthday(store: {
        let s = OnboardingStore()
        s.birthYear = 1996; s.birthMonth = 3; s.birthDay = 14
        return s
    }())
    .padding(.horizontal, ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}

/// The case the screen exists for, and the one it must not punish.
#Preview("Too young") {
    OnboardingBirthday(store: {
        let s = OnboardingStore()
        s.birthYear = 2015; s.birthMonth = 6; s.birthDay = 2
        return s
    }())
    .padding(.horizontal, ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
