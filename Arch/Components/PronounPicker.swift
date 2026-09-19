import SwiftUI

/// Pronouns, as chips you can pick and unpick, with a field for anything the
/// chips do not cover.
///
/// The field alone asked people to type the same five things over and over, and
/// got "She / her", "she,her" and "shes" back — three ways of writing the one
/// thing, none of which line up on a profile. The chips make the common answers
/// one tap, and one tap again to take back. The field stays for everybody the
/// chips leave out; pronouns are not a closed list, and this component is not
/// going to pretend they are.
///
/// **More than one chip is allowed.** "she/they" is a real answer, and it is made
/// by picking two rather than by adding every combination as its own chip. The
/// picked sets are joined by their subject words in the order the chips sit in,
/// so the same two picks always read the same way.
///
/// The value is still one string, because that is what the profile chip shows and
/// what the column stores. `PronounSet.parse` reads a string back into picks and a
/// remainder, so a profile written before this existed still lights the right
/// chips.
struct PronounPicker: View {
    @Binding var text: String
    /// `night` on a `stone` sheet, `stone` on a `night` screen -- the same rule
    /// `ArchField` follows, for the field below the chips.
    var surface: Color = ArchColor.night

    @State private var picked: [PronounSet] = []
    @State private var other = ""

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pronouns")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                Spacer(minLength: 0)
                Text("Optional")
                    .archText(.caption)
                    .foregroundStyle(ArchColor.mortar)
            }

            FlowLayout(spacing: ArchSpacing.xs, lineSpacing: ArchSpacing.xs) {
                ForEach(PronounSet.presets) { set in
                    PronounChip(text: set.label, isSelected: picked.contains(set)) {
                        withAnimation(ArchMotion.quick) { toggle(set) }
                    }
                }
            }

            ArchField(
                text: $other,
                placeholder: "Something else",
                characterLimit: PronounSet.characterLimit,
                surface: surface
            )
            .onChange(of: other) { _, _ in compose() }
        }
        .onAppear(perform: read)
        // Written from outside -- a profile loading in after the sheet opened.
        .onChange(of: text) { _, new in
            if new != composed() { read() }
        }
    }

    private func toggle(_ set: PronounSet) {
        if let index = picked.firstIndex(of: set) {
            picked.remove(at: index)
        } else {
            picked.append(set)
        }
        compose()
    }

    /// Chips in preset order, then whatever was typed.
    private func composed() -> String {
        PronounSet.compose(picked: picked, other: other)
    }

    private func compose() {
        text = composed()
    }

    private func read() {
        let parsed = PronounSet.parse(text)
        picked = parsed.picked
        other = parsed.other
    }
}

/// One set of pronouns, as a chip knows it.
struct PronounSet: Identifiable, Hashable {
    /// The subject word: what a combination is written with.
    let subject: String
    /// The object word, so a single pick reads "she/her" and not "she".
    let object: String

    var id: String { subject }
    var label: String { "\(subject)/\(object)" }

    static let presets: [PronounSet] = [
        PronounSet(subject: "she", object: "her"),
        PronounSet(subject: "he", object: "him"),
        PronounSet(subject: "they", object: "them"),
        PronounSet(subject: "xe", object: "xem"),
        PronounSet(subject: "ze", object: "zir")
    ]

    /// The same limit the field had on its own.
    static let characterLimit = 20

    /// One pick is written in full; more than one is written by subject, so that
    /// "she" and "they" read as "she/they" rather than "she/her/they/them".
    /// Anything typed follows, after a comma, since it is not part of the join.
    static func compose(picked: [PronounSet], other: String) -> String {
        let ordered = presets.filter { picked.contains($0) }
        let joined: String
        switch ordered.count {
        case 0:  joined = ""
        case 1:  joined = ordered[0].label
        default: joined = ordered.map(\.subject).joined(separator: "/")
        }
        let typed = other.trimmingCharacters(in: .whitespaces)
        switch (joined.isEmpty, typed.isEmpty) {
        case (true, true):   return ""
        case (false, true):  return joined
        case (true, false):  return typed
        case (false, false): return "\(joined), \(typed)"
        }
    }

    /// The picks a string lights up, and what is left over for the field.
    ///
    /// A word before the first comma that names a preset -- by subject or by
    /// object -- lights that chip. What does not is kept as typed. So "she/her"
    /// and "she/they" both come back as picks, and "fae/faer" comes back as
    /// words, and neither is lost.
    static func parse(_ text: String) -> (picked: [PronounSet], other: String) {
        let parts = text.split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let head = parts.first, !head.isEmpty else { return ([], "") }

        let words = head.lowercased().split(separator: "/").map(String.init)
        var picked: [PronounSet] = []
        var unknown = false
        for word in words {
            if let set = presets.first(where: { $0.subject == word || $0.object == word }) {
                if !picked.contains(set) { picked.append(set) }
            } else {
                unknown = true
            }
        }
        let tail = parts.count > 1 ? parts[1] : ""

        // A head with a word the chips do not know is kept whole rather than
        // split: "she/fae" is one answer somebody wrote, not a pick plus a typo.
        if unknown {
            return ([], text.trimmingCharacters(in: .whitespaces))
        }
        return (picked, tail)
    }
}

/// A chip that can be picked. Selected is a border and a lift, like `OptionRow`,
/// rather than `lamp` -- the accent means "this is the action", and here every
/// chip is equally one.
struct PronounChip: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .archText(.footnote)
                .foregroundStyle(ArchColor.limestone)
                .padding(.horizontal, ArchSpacing.s)
                .padding(.vertical, ArchSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                        .fill(isSelected ? ArchColor.stoneRaised : ArchColor.stone)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                        .strokeBorder(
                            isSelected ? ArchColor.limestone.opacity(0.30) : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("pronoun.\(text)")
    }
}

#Preview("Pronouns") {
    struct Host: View {
        @State private var text = "she/they"
        var body: some View {
            VStack(alignment: .leading, spacing: ArchSpacing.l) {
                PronounPicker(text: $text, surface: ArchColor.stone)
                Text("Reads as: \(text.isEmpty ? "nothing" : text)")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }
            .padding(ArchSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ArchColor.night)
        }
    }
    return Host().preferredColorScheme(.dark)
}
