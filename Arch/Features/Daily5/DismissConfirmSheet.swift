import SwiftUI

/// Confirming a dismissal.
///
/// A sheet rather than an alert, because an alert is something you swat away and
/// this is a decision that costs you a slot until tomorrow. It states all three
/// facts plainly and then gets out of the way.
///
/// **Neither action is `lamp`.** Dismissing is not what the app is encouraging, so
/// the confirm button gets no colour — but making "Cancel" the loud one would lean
/// on the user in the opposite direction, and the choice is genuinely theirs.
///
/// Copy is written around the name rather than pronouns. Arch has no business
/// guessing anyone's.
struct DismissConfirmSheet: View {
    let person: Person
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Dismiss \(person.name)?")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.xl)

            Text("\(person.name) leaves your five. The slot fills with someone new tomorrow. You cannot undo this.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.s)

            Spacer(minLength: ArchSpacing.xl)

            ArchButton(title: "Dismiss \(person.name)", kind: .quiet, action: onConfirm)
            ArchTextButton(title: "Cancel", action: onCancel)
                .padding(.top, ArchSpacing.xxs)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArchColor.stone)
        .presentationDetents([.height(288)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
    }
}

#Preview("Dismiss confirmation") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            DismissConfirmSheet(person: MockData.nadia, onConfirm: {}, onCancel: {})
        }
        .preferredColorScheme(.dark)
}

#Preview("Sheet content only") {
    DismissConfirmSheet(person: MockData.marcus, onConfirm: {}, onCancel: {})
        .frame(height: 288)
        .preferredColorScheme(.dark)
}
