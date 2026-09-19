import SwiftUI

/// One value out of a list, as a row that opens a sheet of option rows.
///
/// `HeightRow` and `HeightPickerSheet` invented this shape and the birthday
/// screen needs three of it, so it is a pair of general pieces rather than four
/// near-copies. The reasoning in `HeightPickerSheet` still holds and is the
/// reason this is not a `Picker`: a `.wheel` picker arrives with its own greys
/// and corner radii, and every other control on these screens is made of Arch's
/// own surfaces.
struct ChoiceRow: View {
    let label: String
    /// Empty means nothing chosen yet, which reads as "Choose" rather than as a
    /// blank the reader has to guess the meaning of.
    let value: String
    var surface: Color = ArchColor.night
    var isEnabled: Bool = true
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: ArchSpacing.s) {
                Text(label)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .frame(width: 108, alignment: .leading)
                Text(value.isEmpty ? "Choose" : value)
                    .archText(.callout)
                    .foregroundStyle(value.isEmpty ? ArchColor.mortar : ArchColor.limestone)
                Spacer(minLength: 0)
                if isEnabled {
                    Image(systemName: "chevron.right")
                        .archText(.caption)
                        .foregroundStyle(ArchColor.mortar)
                }
            }
            .padding(ArchSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(surface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: isEnabled ? 0.99 : 1))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(value.isEmpty ? "\(label), not chosen" : "\(label), \(value)")
    }
}

/// The sheet the row opens.
struct ChoiceSheet: View {
    let title: String
    let options: [String]
    let current: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            Text(title)
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.l)
                .padding(.horizontal, ArchSpacing.screenMargin)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: ArchSpacing.xs) {
                        ForEach(options, id: \.self) { option in
                            OptionRow(text: option, isSelected: option == current) {
                                onPick(option)
                                dismiss()
                            }
                            .id(option)
                        }
                    }
                    .padding(.horizontal, ArchSpacing.screenMargin)
                    .padding(.bottom, ArchSpacing.m)
                }
                .scrollIndicators(.hidden)
                // Opens on what is already chosen rather than at the top, which
                // for a year list means not scrolling past thirty rows to find
                // the one with the tick on it.
                .onAppear {
                    guard options.contains(current) else { return }
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
        .archSheetBackground()
    }
}

#Preview("Year") {
    ChoiceSheet(title: "Year",
                options: Birthday.years().map(String.init),
                current: "1996") { _ in }
        .frame(height: 520)
        .preferredColorScheme(.dark)
}

#Preview("A row, nothing chosen") {
    VStack(spacing: ArchSpacing.xs) {
        ChoiceRow(label: "Year", value: "", surface: ArchColor.stone) {}
        ChoiceRow(label: "Month", value: "March", surface: ArchColor.stone) {}
        ChoiceRow(label: "Day", value: "", surface: ArchColor.stone, isEnabled: false) {}
    }
    .padding()
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}

/// A fact that is shown and cannot be changed.
///
/// Reads like `ChoiceRow` and `ArchField` because it sits in a column of them,
/// minus the chevron and the press — a row that looks tappable and is not is
/// worse than one that plainly is not.
struct FixedRow: View {
    let label: String
    let value: String
    var surface: Color = ArchColor.night

    var body: some View {
        HStack(spacing: ArchSpacing.s) {
            Text(label)
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .frame(width: 108, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .archText(.callout)
                .foregroundStyle(ArchColor.mortar)
            Spacer(minLength: 0)
        }
        .padding(ArchSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                .fill(surface)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value.isEmpty ? "not set" : value)")
        .accessibilityHint("Set when you signed up and cannot be changed")
    }
}

#Preview("A fixed row") {
    VStack(spacing: ArchSpacing.xs) {
        FixedRow(label: "Age", value: "29", surface: ArchColor.stone)
        FixedRow(label: "Height", value: "5 ft 10", surface: ArchColor.stone)
    }
    .padding()
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
