import SwiftUI

/// Several lists side by side, reading as one control.
///
/// **Three sheets to enter one date was three sheets too many.** A birthday is a
/// single fact, and asking for it as year, then month, then day — each behind its
/// own row, its own sheet and its own dismissal — made three decisions out of one
/// and hid two of them at any moment. Here all three are on screen at once, next
/// to each other, inside one surface: you can see what you have chosen and change
/// any part of it without leaving anything.
///
/// Still not a `UIDatePicker`, and for the reason `HeightPickerSheet` turned down
/// the wheel: it arrives with its own greys, its own corner radii and its own
/// idea of type, on a screen made entirely of Arch's surfaces. The columns scroll
/// like a wheel and are drawn like the rest of the app.
struct ColumnPicker: View {

    /// One column: what it is called, what it offers, and what is chosen.
    struct Column: Identifiable {
        let id: String
        let options: [String]
        /// Nil until something is chosen — a birthday half entered is a real
        /// state and an empty column is how it looks.
        let selection: String?
        /// False for a column that cannot be answered yet. The day list cannot
        /// be offered before the month it belongs to is known: "31" is a
        /// different promise in June than in May.
        var isEnabled: Bool = true
        let onPick: (String) -> Void
    }

    let columns: [Column]
    var height: CGFloat = 196

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                if index > 0 {
                    Rectangle()
                        .fill(ArchColor.hairline)
                        .frame(width: ArchSpacing.hairline)
                        .padding(.vertical, ArchSpacing.s)
                }
                list(column)
            }
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                .fill(ArchColor.stone)
        )
    }

    private func list(_ column: Column) -> some View {
        VStack(spacing: 0) {
            Text(column.id)
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .padding(.top, ArchSpacing.s)
                .padding(.bottom, ArchSpacing.xxs)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(column.options, id: \.self) { option in
                            row(option, in: column)
                                .id(option)
                        }
                    }
                    // So the first and last rows can sit in the middle rather
                    // than being pinned against the ends of the column.
                    .padding(.vertical, ArchSpacing.m)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    guard let selection = column.selection else { return }
                    proxy.scrollTo(selection, anchor: .center)
                }
                // A day that moved because the month changed has to be seen to
                // have moved -- 31 becoming 30 off the top of the screen is the
                // app changing an answer behind the reader's back.
                .onChange(of: column.selection) { _, new in
                    guard let new else { return }
                    withAnimation(ArchMotion.quick) { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(column.isEnabled ? 1 : 0.4)
        .allowsHitTesting(column.isEnabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(column.selection.map { "\(column.id), \($0)" }
                            ?? "\(column.id), not chosen")
    }

    private func row(_ option: String, in column: Column) -> some View {
        let isChosen = option == column.selection
        return Button { column.onPick(option) } label: {
            Text(option)
                .archText(.callout)
                .foregroundStyle(isChosen ? ArchColor.onLamp : ArchColor.limestone)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ArchSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                        .fill(isChosen ? ArchColor.lamp : .clear)
                        .padding(.horizontal, ArchSpacing.xxs)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 1))
        .accessibilityLabel(option)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("A date") {
    ColumnPickerPreview()
        .padding()
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

private struct ColumnPickerPreview: View {
    @State private var year: Int? = 1996
    @State private var month: Int? = 3
    @State private var day: Int? = 14

    var body: some View {
        ColumnPicker(columns: [
            .init(id: "Year",
                  options: Birthday.years().map(String.init),
                  selection: year.map(String.init),
                  onPick: { year = Int($0) }),
            .init(id: "Month",
                  options: Birthday.months,
                  selection: month.map { Birthday.months[$0 - 1] },
                  onPick: { month = Birthday.months.firstIndex(of: $0).map { $0 + 1 } }),
            .init(id: "Day",
                  options: (1...31).map(String.init),
                  selection: day.map(String.init),
                  isEnabled: year != nil && month != nil,
                  onPick: { day = Int($0) })
        ])
    }
}
