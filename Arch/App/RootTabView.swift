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
    /// What iOS answered when onboarding asked. Seeded here so "Not now" is
    /// reflected in Settings from the first launch rather than the second.
    var allowsNotifications: Bool = true
    /// Deleting an account puts you back where you came from.
    var onDeleteAccount: () -> Void = {}

    @State private var store = DailyFiveStore()
    @State private var settings = SettingsStore()

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            TabBar(selection: $selection, unreadCount: store.unreadCount)
        }
        .background(ArchColor.night)
        .onAppear { settings.systemNotificationsAllowed = allowsNotifications }
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
                PremiumView(isSubscribed: settings.isSubscribed) {
                    settings.isSubscribed.toggle()
                    store.setSubscribed(settings.isSubscribed)
                }
            }
            tab(.daily) {
                DailyFiveView(
                    roster: store.roster,
                    conversationCount: store.openConversations.count,
                    conversationLimit: store.conversationLimit,
                    onOpenMessages: { selection = .messages },
                    isPaused: settings.isPaused,
                    onUnpause: { settings.isPaused = false },
                    onDismiss: { store.dismiss($0) },
                    onSend: { store.startConversation(with: $0, text: $1, quoting: $2) },
                    actions: conversationActions
                )
            }
            tab(.messages) {
                MessagesListView(
                    conversations: store.openConversations,
                    requests: store.requests,
                    onAccept: { store.accept($0) },
                    onDecline: { store.decline($0) },
                    onOpenDaily: { selection = .daily },
                    actions: conversationActions,
                    holdsSlot: { store.holdsSlot($0) }
                )
            }
            tab(.you) {
                YouProfileView(
                    store: profile,
                    settings: settings,
                    writtenAbout: MockData.writtenAbout,
                    onOpenPremium: { selection = .premium },
                    onDeleteAccount: onDeleteAccount
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
