import SwiftUI

/// Writing your three interests.
///
/// Free text rather than a picker. A curated list would hand everyone "Travel" and
/// "Coffee", and the whole premise of a slow app is that people say something
/// specific enough to be worth reading.
struct EditInterestsSheet: View {
    let interests: [Interest]
    let onSave: ([String]) -> Void

    @State private var drafts: [String] = ["", "", ""]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            Text("Interests")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.l)

            Text("Three things you are actually into. Short and specific beats broad.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: ArchSpacing.xs) {
                ForEach(0..<Person.requiredInterests, id: \.self) { index in
                    ArchField(
                        text: $drafts[index],
                        placeholder: examples[index],
                        characterLimit: Interest.characterLimit
                    )
                }
            }

            Spacer(minLength: 0)

            ArchButton(title: "Save", isEnabled: hasSomething) {
                onSave(drafts)
            }
            ArchTextButton(title: "Cancel") { dismiss() }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.stone)
        .presentationDetents([.height(460)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
        .onAppear {
            for (index, interest) in interests.prefix(3).enumerated() {
                drafts[index] = interest.text
            }
        }
    }

    private let examples = ["Night baking", "Rolleiflex repair", "Above-ground platforms"]

    private var hasSomething: Bool {
        drafts.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

#Preview("Edit interests") {
    EditInterestsSheet(interests: MockData.you.interests) { _ in }
        .frame(height: 460)
        .preferredColorScheme(.dark)
}

#Preview("Edit interests, mostly empty") {
    EditInterestsSheet(interests: Array(MockData.you.interests.prefix(1))) { _ in }
        .frame(height: 460)
        .preferredColorScheme(.dark)
}
