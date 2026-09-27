import SwiftUI

/// The three written pages.
///
/// Short on purpose. "How Arch works" is the one place the product explains its own
/// rules in full, and it is worth being plain about the parts people find strange —
/// that five is the whole thing, and that dismissing costs you.
struct HelpPage: View {
    enum Topic {
        case how, safety, contact

        var title: String {
            switch self {
            case .how:     return "How Arch works"
            case .safety:  return "Safety"
            case .contact: return "Contact us"
            }
        }
    }

    let topic: Topic

    var body: some View {
        SettingsPage(title: topic.title) {
            switch topic {
            case .how:     how
            case .safety:  safety
            case .contact: contact
            }
        }
    }

    // MARK: How

    @ViewBuilder
    private var how: some View {
        section(
            "Five people, held",
            "You have five spots in your match list, or seven with Arch Premium. Arch is always looking for people you might genuinely connect with and fills those spots with its best matches. Once someone is found, they stay until you choose to dismiss them."
        )
        section(
            "Dismissing someone opens a spot",
            "Dismiss someone and their spot opens up for the next match cycle. It is meant to be a serious decision, so Arch asks you to confirm before dismissing. There are no swipes and no endless replacements throughout the day."
        )
        section(
            "There is no matching step",
            "If you are matched with someone, you can message them. They do not need to like you first. If you want to talk, just send them a message."
        )
        section(
            "Dismissals are anonymous",
            "When someone leaves your match list, Arch only tells you that a spot has opened. You will not be told who left or why."
        )
        section(
            "New matches appear every morning",
            "Arch is constantly evaluating potential matches throughout the day. Each morning at \(RefillCopy.batchHour()), your matches are refreshed with the people Arch thinks are the best fit for you. Everyone receives their new matches at the same time, so there is no waiting for a queue or wondering when someone new will appear."
        )
        section(
            "Someone writing to you is a request",
            "When someone messages you first, their message appears in Requests and you can choose whether to answer. Once they write, they leave your match list, because they are no longer someone you are considering: they have made the choice to reach out. You can dismiss them if you are not interested."
        )
        section(
            "Conversations can end without a reason",
            "Someone can leave a conversation, block you, or delete their account. From your side, all three look the same: you will still be able to read the conversation, but you will not be able to reply. We keep them looking the same so you are never left wondering exactly what happened."
        )
        section(
            "The questions help with matching",
            "The questions you answer help Arch understand what you are looking for and who you might connect with. They are not about finding the perfect person. They simply give Arch more context to make better matches."
        )
    }

    // MARK: Safety

    @ViewBuilder
    private var safety: some View {
        // Rewritten when email sign-in arrived, because the old line stopped
        // being true the moment it did: an email address costs nothing, so
        // "a new Apple ID and usually a new phone" was no longer the price. The
        // device is what still costs something, and that is what this now says.
        section(
            "Every account is tied to a device",
            "An account being verified does not guarantee someone is who they say they are. Signing in with Apple connects your account to an Apple ID, and adding an email connects it to that address. Underneath both, everything is tied to the physical device. So if someone gets removed, starting over is not as simple as signing up again: it usually means getting a new phone. That is by design, as it makes it genuinely inconvenient to create throwaway accounts."
        )
        section(
            "Blocking is silent and complete",
            "Block someone and they are gone for good: removed from your matches, unable to reappear, and unable to see your profile any more. No notification is sent. They will simply never know it happened."
        )
        section(
            "Reporting",
            "Spotted something concerning? Report it right from the conversation. A real person reviews every report, not a bot, and you are free to report someone without blocking them first."
        )
        meeting
    }

    // MARK: Contact

    @ViewBuilder
    private var contact: some View {
        section(
            "Write to a person",
            "Email help@arch.app and you will reach an actual person, usually within a day. No chatbot standing in the way."
        )
        section(
            "Something is broken",
            "Let us know what you were trying to do and what happened instead. A screenshot tells us more than a description ever could."
        )
        section(
            "Something is wrong with someone",
            "If it is about another person, report them directly from your conversation instead of emailing us. That way your report arrives with the full context attached, so we can act on it faster."
        )
        ArchButton(title: "Email help@arch.app", kind: .quiet) {}
    }

    /// The one part of Safety that is a list rather than a paragraph: these are
    /// five separate habits, and a reader scanning for them should find five
    /// lines rather than one block to parse.
    private var meeting: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
            Text("Meeting")
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)

            Text("Meeting for the first time? A few habits go a long way:")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: ArchSpacing.xs) {
                habit("Choose a public place: a coffee shop, a restaurant, or somewhere with other people around.")
                habit("Tell a friend or family member where you are going, who you are meeting, and when you expect to be back.")
                habit("Arrange your own transport there and back, rather than relying on the other person for a ride.")
                habit("Keep your phone charged and easy to reach.")
                habit("Trust your gut. If something feels off, it is okay to leave.")
            }
            .padding(.top, ArchSpacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func habit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ArchSpacing.xs) {
            Circle()
                .fill(ArchColor.mortar)
                .frame(width: 4, height: 4)
                .padding(.top, 8)
            Text(text)
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Shared

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
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

#Preview("Safety") {
    NavigationStack { HelpPage(topic: .safety) }
        .preferredColorScheme(.dark)
}

#Preview("Contact us") {
    NavigationStack { HelpPage(topic: .contact) }
        .preferredColorScheme(.dark)
}
