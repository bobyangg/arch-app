import SwiftUI

/// Several wheels side by side, reading as one control.
///
/// **Three sheets to enter one date was three sheets too many.** A birthday is a
/// single fact, and asking for it as year, then month, then day — each behind its
/// own row, its own sheet and its own dismissal — made three decisions out of one
/// and hid two of them at any moment. Here all three are on screen at once, next
/// to each other, inside one surface: you can see what you have chosen and change
/// any part of it without leaving anything.
///
/// **Scrolling is choosing.** Each column is a wheel: it settles with one row in
/// the band across the middle, and that row is the answer. It used to be a list
/// you scrolled and then had to tap, which is two gestures for one decision and
/// the second was easy to miss. Tapping a row still works -- it brings that row
/// to the middle -- and VoiceOver can step through a column with a swipe.
///
/// Still not a `UIDatePicker`, and for the reason `HeightPickerSheet` turned down
/// the wheel: it arrives with its own greys, its own corner radii and its own
/// idea of type, on a screen made entirely of Arch's surfaces. These are drawn
/// like the rest of the app.
struct ColumnPicker: View {

    /// One column: what it is called, what it offers, and what is chosen.
    struct Column: Identifiable {
        let id: String
        let options: [String]
        /// Nil until something is chosen — a birthday half entered is a real
        /// state and an empty column is how it looks.
        let selection: String?
        /// Where the wheel rests before anything is chosen. Resting there chooses
        /// nothing: an answer nobody gave would be the app's answer, and for a
        /// birthday that is the age on somebody's profile. Defaults to the first
        /// option.
        var resting: String? = nil
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
                WheelColumn(column: column)
            }
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                .fill(ArchColor.stone)
        )
    }
}

/// One wheel.
private struct WheelColumn: View {
    let column: ColumnPicker.Column

    private static let rowHeight: CGFloat = 36

    /// The row in the middle of the wheel, which the scroll view keeps up to date
    /// as it moves and settles.
    @State private var centred: String?
    /// Set just before the wheel is moved by the app rather than by a finger --
    /// to follow a day that the month corrected, say -- so that moving it does
    /// not count as somebody choosing.
    @State private var movingItself = false

    init(column: ColumnPicker.Column) {
        self.column = column
        // Set here rather than on appear: a change after the first render is
        // indistinguishable from a scroll, and would choose the resting row.
        _centred = State(initialValue: column.selection ?? column.resting ?? column.options.first)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(column.id)
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .padding(.top, ArchSpacing.s)
                .padding(.bottom, ArchSpacing.xxs)

            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(column.options, id: \.self) { option in
                            row(option)
                                .id(option)
                        }
                    }
                    .scrollTargetLayout()
                }
                // **Half the wheel above the first row and below the last**, so
                // either end can reach the middle and be chosen like any other.
                .contentMargins(.vertical, max(0, (geo.size.height - Self.rowHeight) / 2),
                                for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centred, anchor: .center)
                .scrollIndicators(.hidden)
                .background { band }
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(column.isEnabled ? 1 : 0.4)
        .allowsHitTesting(column.isEnabled)
        // A finger moved the wheel: what is in the middle now is the answer.
        .onChange(of: centred) { _, new in
            if movingItself {
                movingItself = false
                return
            }
            guard column.isEnabled, let new, new != column.selection else { return }
            column.onPick(new)
        }
        // The answer moved without the wheel -- the store took 31 back to 30
        // when June was chosen -- and the wheel has to be seen to follow it,
        // rather than the app changing an answer behind the reader's back.
        .onChange(of: column.selection) { _, new in
            guard let new, new != centred else { return }
            movingItself = true
            centred = new
        }
        // A list that lost the row the wheel was resting on, before anything was
        // chosen: rest on the nearest end instead, still choosing nothing.
        .onChange(of: column.options) { _, options in
            guard let current = centred, !options.contains(current) else { return }
            movingItself = true
            centred = options.last
        }
        .sensoryFeedback(.selection, trigger: column.selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(column.id)
        .accessibilityValue(column.selection ?? "not chosen")
        .accessibilityAdjustableAction { direction in
            let options = column.options
            let index = column.selection.flatMap { options.firstIndex(of: $0) }
            switch direction {
            case .increment:
                column.onPick(options[min((index ?? -1) + 1, options.count - 1)])
            case .decrement:
                column.onPick(options[max((index ?? 1) - 1, 0)])
            @unknown default:
                break
            }
        }
    }

    /// The band across the middle. Lit once this column has an answer, faint
    /// until then, so a wheel that is only resting does not look chosen.
    private var band: some View {
        RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
            .fill(column.selection == nil ? ArchColor.limestone.opacity(0.06) : ArchColor.lamp)
            .frame(height: Self.rowHeight)
            .padding(.horizontal, ArchSpacing.xxs)
            .animation(ArchMotion.quick, value: column.selection == nil)
    }

    private func row(_ option: String) -> some View {
        let isChosen = option == column.selection
        return Text(option)
            .archText(.callout)
            .foregroundStyle(isChosen ? ArchColor.onLamp : ArchColor.limestone)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
            // Tapping a row is the other way to choose it. It is chosen first
            // and then brought to the middle, so the scroll it causes is the
            // app's and chooses nothing on the way.
            .onTapGesture {
                guard option != column.selection else { return }
                column.onPick(option)
            }
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
