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
    @State private var isPickingHeight = false
    @State private var isPickingPlace = false
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Int(age) != nil
            && gender != nil
            && place != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ArchSpacing.m) {
                Text("Your details")
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                    .padding(.top, ArchSpacing.l)

                VStack(spacing: ArchSpacing.xs) {
                    ArchField(text: $name, label: "Name")
                    ArchField(text: $age, label: "Age", keyboard: .numberPad)
                    PlaceRow(place: place) { isPickingPlace = true }
                    HeightRow(height: height) { isPickingHeight = true }
                    ArchField(text: $work, label: "Work")
                }

                genderSection

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
        .presentationBackground(ArchColor.stone)
        .sheet(isPresented: $isPickingHeight) {
            HeightPickerSheet(current: height) { height = $0 }
        }
        .sheet(isPresented: $isPickingPlace) {
            PlacePickerView(
                current: place,
                onChoose: { place = $0; isPickingPlace = false },
                onCancel: { isPickingPlace = false }
            )
            .padding(.horizontal, ArchSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ArchColor.stone)
            .presentationDetents([.large])
            .presentationCornerRadius(ArchRadius.sheet)
            .presentationBackground(ArchColor.stone)
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
        }
    }

    // MARK: Pieces

    private var genderSection: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
            Text("Gender")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)

            ForEach(Gender.allCases) { option in
                OptionRow(text: option.label, isSelected: gender == option) {
                    gender = option
                }
            }
        }
    }

}

#Preview("Edit details") {
    EditDetailsSheet(person: MockData.you) { _ in }
        .frame(height: 720)
        .preferredColorScheme(.dark)
}
