import SwiftUI

/// The app shell: four tabs over one store.
///
/// All four tabs stay alive rather than being rebuilt on every switch, so a
/// half-scrolled profile or an open thread is still there when you come back —
/// which is what a tab bar is supposed to do.
struct RootTabView: View {
    @State private var selection: ArchTab = .daily
    /// Built by onboarding and handed over, so the profile you filled in is the
    /// one the You tab edits.
    let profile: ProfileStore

    @State private var store = DailyFiveStore()
    @State private var settings = SettingsStore()

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            TabBar(selection: $selection, unreadCount: store.unreadCount)
        }
        .background(ArchColor.night)
    }

    /// Blocking writes to two places: the roster and conversations live in the
    /// Daily 5 store, the blocked list lives in Settings.
    private var conversationActions: ConversationActions {
        ConversationActions(
            leave: { store.leave($0) },
            block: { person in
                store.block(person)
                if !settings.blocked.contains(person.name) {
                    settings.blocked.append(person.name)
                }
            },
            report: { person, _, alsoBlock in
                // Reporting on its own removes nothing. You reported them; you did
                // not ask to lose the conversation.
                guard alsoBlock else { return }
                store.block(person)
                if !settings.blocked.contains(person.name) {
                    settings.blocked.append(person.name)
                }
            }
        )
    }

    private var content: some View {
        ZStack {
            tab(.premium) {
                PremiumView(isSubscribed: settings.isSubscribed)
            }
            tab(.daily) {
                DailyFiveView(
                    roster: store.roster,
                    onDismiss: { store.dismiss($0) },
                    onSend: { store.startConversation(with: $0, text: $1, quoting: $2) },
                    actions: conversationActions
                )
            }
            tab(.messages) {
                MessagesListView(
                    conversations: store.conversations,
                    onOpenDaily: { selection = .daily },
                    actions: conversationActions,
                    holdsSlot: { store.holdsSlot($0) }
                )
            }
            tab(.you) {
                YouProfileView(
                    store: profile,
                    settings: settings,
                    onOpenPremium: { selection = .premium }
                )
            }
        }
    }

    @ViewBuilder
    private func tab<Content: View>(
        _ which: ArchTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selection == which ? 1 : 0)
            .allowsHitTesting(selection == which)
            .accessibilityHidden(selection != which)
    }
}

#Preview("App shell") {
    RootTabView(profile: ProfileStore(person: MockData.you))
        .preferredColorScheme(.dark)
}
