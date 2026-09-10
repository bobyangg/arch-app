import SwiftUI

/// The four facts under your name.
///
/// Neighbourhood and city are two fields but one chip — `Person.location` joins
/// them, so nothing else in the app has to decide how that string is written.
struct EditDetailsSheet: View {
    let person: Person
    /// name, age, neighbourhood, city, height, work
    let onSave: (String, Int, String, String, String, String) -> Void

    @State private var name = ""
    @State private var age = ""
    @State private var neighbourhood = ""
    @State private var city = ""
    @State private var height = ""
    @State private var work = ""
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Int(age) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            Text("Your details")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.l)

            VStack(spacing: ArchSpacing.xs) {
                ArchField(text: $name, label: "Name")
                ArchField(text: $age, label: "Age", keyboard: .numberPad)
                ArchField(text: $neighbourhood, label: "Neighbourhood")
                ArchField(text: $city, label: "City")
                ArchField(text: $height, label: "Height")
                ArchField(text: $work, label: "Work")
            }

            Text("Your neighbourhood and city show together, as \(previewLocation).")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            ArchButton(title: "Save", isEnabled: isValid) {
                onSave(
                    name.trimmingCharacters(in: .whitespaces),
                    Int(age) ?? person.age,
                    neighbourhood.trimmingCharacters(in: .whitespaces),
                    city.trimmingCharacters(in: .whitespaces),
                    height.trimmingCharacters(in: .whitespaces),
                    work.trimmingCharacters(in: .whitespaces)
                )
            }
            ArchTextButton(title: "Cancel") { dismiss() }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.stone)
        .presentationDetents([.height(620)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
        .onAppear {
            name = person.name
            age = "\(person.age)"
            neighbourhood = person.neighbourhood
            city = person.city
            height = person.height
            work = person.work
        }
    }

    private var previewLocation: String {
        let n = neighbourhood.trimmingCharacters(in: .whitespaces)
        let c = city.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return c.isEmpty ? "one chip" : c }
        return c.isEmpty ? n : "\(n), \(c)"
    }
}

#Preview("Edit details") {
    EditDetailsSheet(person: MockData.you) { _, _, _, _, _, _ in }
        .frame(height: 620)
        .preferredColorScheme(.dark)
}
