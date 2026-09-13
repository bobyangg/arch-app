import SwiftUI

/// Choosing a height.
///
/// It was a text field, which accepted "tall", "1.8m", "5'10", and every other way
/// people write this — none of which two profiles can be compared on and none of
/// which a filter can read.
///
/// **Not a system wheel picker.** `ConversationMenuSheet` already turned down a
/// native `Menu` for arriving with its own greys and corner radii, and a `.wheel`
/// `Picker` would be the same piece of borrowed chrome on a screen made of Arch's
/// own surfaces. A list of the same option rows the questionnaire uses costs
/// nothing extra and looks like the app.
struct HeightPickerSheet: View {
    let current: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            Text("Height")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.l)
                .padding(.horizontal, ArchSpacing.screenMargin)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: ArchSpacing.xs) {
                        ForEach(Person.heights, id: \.self) { height in
                            OptionRow(text: height, isSelected: height == current) {
                                onPick(height)
                                dismiss()
                            }
                            .id(height)
                        }
                    }
                    .padding(.horizontal, ArchSpacing.screenMargin)
                    .padding(.bottom, ArchSpacing.m)
                }
                .scrollIndicators(.hidden)
                // Opens on what you already are, rather than at four foot six.
                .onAppear {
                    guard Person.heights.contains(current) else { return }
                    proxy.scrollTo(current, anchor: .center)
                }
            }

            ArchTextButton(title: "Cancel") { dismiss() }
                .padding(.horizontal, ArchSpacing.screenMargin)
        }
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.stone)
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
    }
}

/// The row that opens the picker.
///
/// Built to read exactly like an `ArchField` — same label width, same padding,
/// same surface — because it sits in a column of them and a control that is
/// *nearly* a field is worse than one that is obviously not.
struct HeightRow: View {
    let height: String
    /// `night` on a sheet, `stone` on a night screen, matching `ArchField`.
    var surface: Color = ArchColor.night
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: ArchSpacing.s) {
                Text("Height")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .frame(width: 108, alignment: .leading)
                Text(height.isEmpty ? "Choose" : height)
                    .archText(.callout)
                    .foregroundStyle(height.isEmpty ? ArchColor.mortar : ArchColor.limestone)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .archText(.caption)
                    .foregroundStyle(ArchColor.mortar)
            }
            .padding(ArchSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(surface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.99))
        .accessibilityLabel(height.isEmpty ? "Height, not chosen" : "Height, \(height)")
    }
}

#Preview("Height") {
    HeightPickerSheet(current: "5 ft 10") { _ in }
        .frame(height: 520)
        .preferredColorScheme(.dark)
}

#Preview("Nothing chosen yet") {
    HeightPickerSheet(current: "") { _ in }
        .frame(height: 520)
        .preferredColorScheme(.dark)
}
