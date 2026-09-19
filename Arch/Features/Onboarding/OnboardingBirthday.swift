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

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "When were you born?",
                detail: "Your age is worked out from this and shown on your profile. The date itself is never shown to anyone."
            )

            // **One control, not three sheets.** All three parts on screen at
            // once, so a date reads as the single fact it is and any part of it
            // can be changed without leaving the other two behind a dismissal.
            ColumnPicker(columns: [
                .init(id: "Year",
                      options: Birthday.years().map(String.init),
                      selection: store.birthYear.map(String.init),
                      onPick: { store.birthYear = Int($0) }),
                .init(id: "Month",
                      options: Birthday.months,
                      selection: store.birthMonth.map { Birthday.months[$0 - 1] },
                      onPick: { store.birthMonth = Birthday.months.firstIndex(of: $0).map { $0 + 1 } }),
                .init(id: "Day",
                      options: (1...store.daysInChosenMonth).map(String.init),
                      selection: store.birthDay.map(String.init),
                      // A day cannot be offered before the month it belongs to
                      // is known.
                      isEnabled: store.birthYear != nil && store.birthMonth != nil,
                      onPick: { store.birthDay = Int($0) })
            ])

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
    }

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
