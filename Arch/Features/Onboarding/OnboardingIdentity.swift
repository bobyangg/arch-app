import SwiftUI

/// Name and email.
struct OnboardingIdentity: View {
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "Your name",
                detail: "This is what people see. Your email is only for signing in and account notices."
            )

            VStack(spacing: ArchSpacing.xs) {
                ArchField(
                    text: Binding(get: { store.name }, set: { store.name = $0 }),
                    label: "Name",
                    placeholder: "Sam",
                    surface: ArchColor.stone
                )
                ArchField(
                    text: Binding(get: { store.email }, set: { store.email = $0 }),
                    label: "Email",
                    placeholder: "sam@example.com",
                    keyboard: .emailAddress,
                    surface: ArchColor.stone
                )
            }

            Text("Your email is never shown to anyone.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
        }
    }
}

/// Age, where you live, height, work.
///
/// The neighbourhood and city fields preview the chip they become, using the same
/// `Person.location` string the roster renders — so you can see what a stranger
/// will actually read before you commit to it.
struct OnboardingAbout: View {
    let store: OnboardingStore

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "About you",
                detail: "Four facts that sit under your name. Nothing else is asked."
            )

            VStack(spacing: ArchSpacing.xs) {
                ArchField(
                    text: Binding(get: { store.ageText }, set: { store.ageText = $0 }),
                    label: "Age",
                    placeholder: "30",
                    keyboard: .numberPad,
                    surface: ArchColor.stone
                )
                ArchField(
                    text: Binding(get: { store.neighbourhood }, set: { store.neighbourhood = $0 }),
                    label: "Neighbourhood",
                    placeholder: "Fort Greene",
                    surface: ArchColor.stone
                )
                ArchField(
                    text: Binding(get: { store.city }, set: { store.city = $0 }),
                    label: "City",
                    placeholder: "Brooklyn",
                    surface: ArchColor.stone
                )
                ArchField(
                    text: Binding(get: { store.height }, set: { store.height = $0 }),
                    label: "Height",
                    placeholder: "5 ft 10",
                    surface: ArchColor.stone
                )
                ArchField(
                    text: Binding(get: { store.work }, set: { store.work = $0 }),
                    label: "Work",
                    placeholder: "Sound engineer",
                    surface: ArchColor.stone
                )
            }

            if !preview.isEmpty {
                VStack(alignment: .leading, spacing: ArchSpacing.xs) {
                    Text("People will see this as")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                    VitalsChip(text: preview)
                }
            }
        }
    }

    /// Mirrors `Person.location` rather than inventing a second way to join these.
    private var preview: String {
        let n = store.neighbourhood.trimmed
        let c = store.city.trimmed
        if n.isEmpty && c.isEmpty { return "" }
        if n.isEmpty { return c }
        if c.isEmpty { return n }
        return "\(n), \(c)"
    }
}

#Preview("Name and email") {
    OnboardingIdentity(store: OnboardingStore())
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

#Preview("About you") {
    OnboardingAbout(store: .configured {
        $0.ageText = "30"
        $0.neighbourhood = "Fort Greene"
        $0.city = "Brooklyn"
    })
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}
