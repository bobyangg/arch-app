import SwiftUI

/// A text field.
///
/// Pulled out of `EditDetailsSheet` and `EditInterestsSheet`, which had grown two
/// nearly-identical private copies, and now also carries every onboarding form.
///
/// Two shapes from one component: with a `label` it is a form row with the label
/// held back in `mortar` on the leading edge; without one it is a plain field
/// carrying only a placeholder.
struct ArchField: View {
    @Binding var text: String

    /// Leading label. Nil gives a placeholder-only field.
    var label: String?
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    /// Clips the text, and shows the remaining count only as you approach it.
    var characterLimit: Int?
    /// `night` on a `stone` sheet, `stone` on a `night` screen — a field is always
    /// a step *down* from whatever it sits on.
    var surface: Color = ArchColor.night
    var isFocused: FocusState<Bool>.Binding?

    private var remaining: Int? {
        guard let characterLimit else { return nil }
        let left = characterLimit - text.count
        return left <= 6 ? left : nil
    }

    var body: some View {
        HStack(spacing: ArchSpacing.s) {
            if let label {
                Text(label)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .frame(width: 108, alignment: .leading)
            }

            field

            if let remaining {
                Text("\(remaining)")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, ArchSpacing.s)
        .padding(.vertical, ArchSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                .fill(surface)
        )
    }

    @ViewBuilder
    private var field: some View {
        if let isFocused {
            base.focused(isFocused)
        } else {
            base
        }
    }

    private var base: some View {
        TextField("", text: $text, prompt: promptText)
            .archText(.callout)
            .foregroundStyle(ArchColor.limestone)
            .keyboardType(keyboard)
            .onChange(of: text) { _, new in
                if let characterLimit, new.count > characterLimit {
                    text = String(new.prefix(characterLimit))
                }
            }
    }

    private var promptText: Text? {
        placeholder.isEmpty ? nil : Text(placeholder).foregroundColor(ArchColor.mortar)
    }
}

#Preview("Fields") {
    FieldPreview()
}

private struct FieldPreview: View {
    @State private var name = "Sam"
    @State private var city = ""
    @State private var interest = "Above-ground platf"

    var body: some View {
        VStack(spacing: ArchSpacing.xs) {
            ArchField(text: $name, label: "Name")
            ArchField(text: $city, label: "City", placeholder: "Brooklyn")
            ArchField(
                text: $interest,
                placeholder: "Night baking",
                characterLimit: Interest.characterLimit
            )
            ArchField(
                text: $city,
                placeholder: "On a night screen",
                surface: ArchColor.stone
            )
        }
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
    }
}
