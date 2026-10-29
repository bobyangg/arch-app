import SwiftUI
import UIKit

/// The three written pages.
///
/// Short on purpose. "How Arch works" is the one place the product explains its own
/// rules in full, and it is worth being plain about the parts people find strange —
/// that five is the whole thing, and that dismissing costs you.
struct HelpPage: View {
    /// Safety is a page on the website (`ArchConfig.safetyURL`), opened from the
    /// Settings row, so it is not one of these.
    enum Topic {
        case how, contact

        var title: String {
            switch self {
            case .how:     return "How Arch works"
            case .contact: return "Contact us"
            }
        }
    }

    let topic: Topic

    @Environment(\.openURL) private var openURL
    /// Said after the address was copied, when there is no Mail app to open.
    @State private var copied = false

    var body: some View {
        SettingsPage(title: topic.title) {
            switch topic {
            case .how:     how
            case .contact: contact
            }
        }
    }

    // MARK: How

    /// **One line each.** These were eight paragraphs; the rules fit in a
    /// sentence apiece, and the page is for scanning.
    @ViewBuilder
    private var how: some View {
        section("Five people at a time",
                "Eight with Premium. They stay until you dismiss them.")
        section("New matches at \(RefillCopy.batchHour())",
                "Every morning, for everyone at once.")
        section("No matching step",
                "Write to anyone in your five. They don\u{2019}t have to like you first.")
        section("Dismissing opens a spot",
                "It refills the next morning. Nobody is told who left.")
        section("Writing first sends a request",
                "They choose whether to answer.")
        section("Conversations can end quietly",
                "Leaving, blocking and deleting look the same from the other side.")
        section("Your answers are private",
                "They shape your matches. Nobody else sees them.")
    }

    // MARK: Contact

    @ViewBuilder
    private var contact: some View {
        section("Write to a person",
                "\(ArchConfig.supportEmail) reaches a real person, usually within a day.")
        section("About someone?",
                "Report them from your conversation instead. It arrives with the context.")

        // **It did nothing.** The button had no action, and the address was
        // `help@arch.app` while the site and the privacy policy say
        // support@archdating.com. Now it opens Mail; with no Mail app set up,
        // it copies the address instead and says so.
        ArchButton(title: "Email \(ArchConfig.supportEmail)", kind: .quiet) { email() }
            .accessibilityIdentifier("help.email")
        if copied {
            Text("Address copied. Paste it into any email app.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .frame(maxWidth: .infinity)
        }
    }

    private func email() {
        guard let url = URL(string: "mailto:\(ArchConfig.supportEmail)?subject=Arch") else { return }
        openURL(url) { opened in
            guard !opened else { return }
            UIPasteboard.general.string = ArchConfig.supportEmail
            copied = true
        }
    }

    // MARK: Shared

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
            Text(title)
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("How Arch works") {
    NavigationStack { HelpPage(topic: .how) }
        .preferredColorScheme(.dark)
}

#Preview("Contact us") {
    NavigationStack { HelpPage(topic: .contact) }
        .preferredColorScheme(.dark)
}
