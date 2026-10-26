import SwiftUI

/// The line that says why a Save, Send or Continue is waiting: the text holds a
/// word Arch does not allow (`ContentFilter`).
///
/// Ink rather than red. `danger` is kept for deleting an account and nothing
/// else, and this is not an error -- it is the button explaining itself.
struct BlockedWordNote: View {
    let text: String

    var body: some View {
        Text(text)
            .archText(.footnote)
            .foregroundStyle(ArchColor.limestone)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("blockedWordNote")
    }
}

#Preview("Blocked word") {
    BlockedWordNote(text: "This has a word Arch does not allow. Take it out to continue.")
        .padding()
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}
