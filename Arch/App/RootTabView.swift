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

    /// Injected by `ArchApp`, which owns them so that a reload after a dropped
    /// connection refreshes what is already on screen rather than replacing the
    /// objects underneath it.
    ///
    /// Optional, with an owned fallback, because every `#Preview` of this tree
    /// wants a store full of `MockData` and no session at all. A plain default
    /// parameter would not do: a view struct is re-made on every render of its
    /// parent, and the store would be new each time.
    var injectedDaily: DailyFiveStore?
    var injectedSettings: SettingsStore?

    /// What iOS answered when onboarding asked. Seeded here so "Not now" is
    /// reflected in Settings from the first launch rather than the second.
    var allowsNotifications: Bool = true
    /// Deleting an account puts you back where you came from.
    var onDeleteAccount: () -> Void = {}
    /// Not the same thing as deleting, even though both land in the same place:
    /// with no password, signing in *is* entering your number, so the way back in
    /// is the screen a new account starts on.
    var onSignOut: () -> Void = {}

    @State private var ownedDaily = DailyFiveStore()
    @State private var ownedSettings = SettingsStore()

    private var store: DailyFiveStore { injectedDaily ?? ownedDaily }
    private var settings: SettingsStore { injectedSettings ?? ownedSettings }
    /// A design build has no network to lose. A real one watches `NWPathMonitor`
    /// and writes here; everything below reads it and nothing else changes.
    @State private var isOffline = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if isOffline { OfflineBanner() }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            TabBar(selection: $selection, unreadCount: store.unreadCount)
        }
        .animation(ArchMotion.standard, value: isOffline)
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
                    isOffline: isOffline,
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
                    onDeleteAccount: onDeleteAccount,
                    onSignOut: onSignOut
                )
            }
        }
    }

    /// All four stay in the tree; the one you chose is the one you can see.
    ///
    /// The change is a cross-fade, on the same curve the tab bar's pill moves
    /// on, so the two read as one gesture. The incoming tab is layered on top and
    /// settles from a hair under full size — enough to say "this is a new place",
    /// not enough to be a slide: the tabs are not arranged left to right in any
    /// sense that matters, and a slide would claim they were. Under Reduce Motion
    /// the scale is dropped and only the fade remains.
    @ViewBuilder
    private func tab<Content: View>(
        _ which: ArchTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isCurrent = selection == which
        content()
            .opacity(isCurrent ? 1 : 0)
            .scaleEffect(isCurrent || reduceMotion ? 1 : 0.99)
            .zIndex(isCurrent ? 1 : 0)
            .animation(ArchMotion.honouring(reduceMotion, ArchMotion.tabSwitch), value: selection)
            .allowsHitTesting(isCurrent)
            .accessibilityHidden(!isCurrent)
    }
}

#Preview("App shell") {
    RootTabView(profile: ProfileStore(person: MockData.you))
        .preferredColorScheme(.dark)
}
