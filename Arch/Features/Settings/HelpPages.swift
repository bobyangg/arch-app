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
            "You have five slots, or seven with Premium. Arch fills them with people it thinks you would actually like, and they stay there. There is nothing to work through and no queue to clear — if you do nothing, they stay."
        )
        section(
            "Dismissing costs you a slot",
            "If you dismiss someone, that slot sits open until tomorrow morning. It is meant to be a real decision, which is why Arch asks you to confirm it and why there is no way to swipe."
        )
        section(
            "There is no match step",
            "Nobody has to like you back before you can write. If you want to talk to someone in your roster, you write to them. That is the whole mechanism."
        )
        section(
            "You are never told who dismissed whom",
            "When somebody goes, Arch tells you a slot opened — never who left, and never why. Dismissing you and writing to you look identical from your side, on purpose."
        )
        section(
            "New people arrive in the morning",
            "Rosters are chosen overnight and are filled at nine, wherever you are. You can only be in someone's roster if they are in yours, so nobody ends up in a thousand lists while somebody else is in none."
        )
        section(
            "Somebody writing to you is a request",
            "Their message waits in Requests until you answer it. They leave your roster when they write — they have stopped being someone to consider and started being someone to answer — and that slot fills in the morning."
        )
        section(
            "Conversations end without a reason",
            "Somebody can leave a conversation, block you, or delete their account. All three look identical from your side — you can read what was said and you cannot reply — because if they looked different, the difference would tell you which one happened."
        )
        section(
            "The questions do the choosing",
            "Your questionnaire answers are how Arch decides who reaches you. They are not on your profile, nobody else sees them, and they do not add up to a score."
        )
    }

    // MARK: Safety

    @ViewBuilder
    private var safety: some View {
        section(
            "Every account has a verified number",
            "It is not a guarantee that someone is who they say, but it makes throwaway accounts expensive, which is most of the problem."
        )
        section(
            "Blocking is silent and complete",
            "A blocked person leaves your roster, stops appearing again, and stops seeing you. They are not told."
        )
        section(
            "Reporting",
            "Report anyone from the top of a conversation. Reports go to a person, not a filter, and you do not have to block someone to report them."
        )
        section(
            "Meeting",
            "Meet somewhere public the first time, tell someone where you are going, and get yourself home. This is dull advice and it is still the advice."
        )
    }

    // MARK: Contact

    @ViewBuilder
    private var contact: some View {
        section(
            "Write to a person",
            "help@arch.app reaches a small team, usually within a day. There is no chatbot in front of it."
        )
        section(
            "Something is broken",
            "Tell us what you were doing and what happened instead. Screenshots help more than descriptions."
        )
        section(
            "Something is wrong with someone",
            "Report them from the conversation rather than emailing — it comes through with the context attached, which gets it dealt with faster."
        )
        ArchButton(title: "Email help@arch.app", kind: .quiet) {}
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
