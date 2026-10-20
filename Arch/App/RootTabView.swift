import SwiftUI

/// The app shell: five tabs over one store.
///
/// All five tabs stay alive rather than being rebuilt on every switch, so a
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
    /// True once, straight after onboarding: the tour of Arch starts over the
    /// roster (`ArchTourOverlay`), and its Date planner step offers the
    /// questions the planner's own popup used to. `onPlannerIntroduced` is
    /// told as soon as it starts, so it never starts twice.
    var introducePlanner: Bool = false
    var onPlannerIntroduced: () -> Void = {}
    /// Deleting an account puts you back where you came from.
    var onDeleteAccount: () -> Void = {}
    /// Not the same thing as deleting, even though both land in the same place:
    /// with no password, signing in *is* entering your number, so the way back in
    /// is the screen a new account starts on.
    var onSignOut: () -> Void = {}

    /// **Tapping the tab you are already on returns it to its root**, which is
    /// what a tab bar has meant since the first one. Without it, Settings was a
    /// place you could only leave the way you came in, and the You button under
    /// it did nothing at all.
    ///
    /// A count rather than a flag, and the reason is that the signal is "it was
    /// tapped again" -- an event, not a state. A `Bool` set true twice in a row
    /// changes nothing, so the second tap would be swallowed, and it would have
    /// to be reset afterwards by whoever consumed it. An `Int` that only ever
    /// goes up has neither problem.
    @State private var youPops = 0
    @State private var messagePops = 0
    @State private var dailyPops = 0
    /// Whether each tab that can open a conversation currently has one on
    /// screen. Two flags rather than one, because all four tabs stay in the
    /// tree -- see `isReadingThread`.
    @State private var messagesThreadOpen = false
    /// Read here so the Premium tab redraws when a price loads or a purchase
    /// settles. `@Observable`, so reading it in `body` is the subscription.
    ///
    /// Computed rather than stored: `shared` belongs to the main actor, and a
    /// stored default is evaluated in an initialiser that may not.
    private var purchases: Purchases { Purchases.shared }
    @State private var dailyThreadOpen = false

    /// Set by "Change it" on a plan in a thread; the Date planner hears it.
    @State private var plannerPreset: PlannerPreset?
    /// The tour's step, while it is showing.
    @State private var tourStep: Int?
    /// Goes up when the tour's "Answer 5 quick questions" is tapped; the
    /// planner hears it and opens on its first question.
    @State private var plannerStarts = 0

    /// A conversation the Messages tab should open, from a tapped notification.
    @State private var messagesOpening: ConversationOpening?

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
            // Gone while you are reading a conversation. A thread is the one
            // screen in the app that is not about choosing between four places
            // to be, and four tabs under it are four ways to leave what you are
            // in the middle of.
            //
            // Tracked per tab because every tab stays in the view tree: a thread
            // left open in Daily 5 is still "open" while you are on You, so one
            // flag would hide the tab bar on a screen with no thread on it.
            if !isReadingThread {
            TabBar(
                selection: Binding(
                    get: { selection },
                    // `TabBar` writes the selection on every tap, including a tap
                    // on the tab already showing, so this is where "again" is
                    // known -- the only place that sees both what was tapped and
                    // what was already there.
                    set: { tapped in
                        if tapped == selection {
                            switch tapped {
                            case .you:      youPops += 1
                            case .messages: messagePops += 1
                            case .daily:    dailyPops += 1
                            default:        break
                            }
                        }
                        selection = tapped
                    }
                ),
                unreadCount: store.unreadCount
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(ArchMotion.standard, value: isOffline)
        .animation(ArchMotion.standard, value: isReadingThread)
        // What a plan in a thread can do, for whichever tab the thread is in.
        .environment(\.planActions, PlanActions(
            send: { conversation, text, plan in
                store.reply(to: conversation, text: text, plan: plan)
            },
            change: { conversation, plan, sender in
                // **Their plan becomes yours to change.** The planner opens on
                // the places they sent, kept as they are; swapping one lets the
                // planner choose again, and sharing sends it back -- where
                // "Change it" opens their planner on your version.
                plannerPreset = PlannerPreset(personID: conversation.person.id,
                                              time: plan.timeOfDay ?? .afternoon,
                                              day: plan.planDay,
                                              items: plan.planItems(
                                                  from: sender.map { "From \($0)\u{2019}s plan." }
                                                      ?? "From the plan you sent."))
                selection = .planner
            },
            showAgreed: { conversation in
                // "I'm in" lands on the plan you just said yes to.
                plannerPreset = PlannerPreset(personID: conversation.person.id,
                                              time: .afternoon,
                                              showsAgreed: true)
                selection = .planner
            }
        ))
        .background(ArchColor.night)
        .onAppear { settings.systemNotificationsAllowed = allowsNotifications }
        // A tapped notification lands in its conversation. `onReceive` hears
        // the value already waiting as well as later ones, so a tap that
        // launched the app -- before this screen existed -- is opened too.
        .onReceive(PushNotifications.shared.$tappedConversation) { id in
            guard let id else { return }
            Task { await openFromNotification(id) }
        }
        .onChange(of: introducePlanner, initial: true) { _, introduce in
            guard introduce else { return }
            tour(0)
            onPlannerIntroduced()
        }
        // Settings > Help > Take the tour again. Settings closes first, so the
        // You step shows your profile rather than the list you came from.
        .onChange(of: settings.tourRequests) { _, _ in
            youPops += 1
            tour(0)
        }
        // **The tour, over everything**, with the tab it is about cut out. The
        // tab bar says where each tab is; the frames are resolved here, over
        // the whole screen, so the cut-out lands on the tab.
        .overlayPreferenceValue(ArchTabFramesKey.self) { frames in
            if let step = tourStep {
                GeometryReader { proxy in
                    ArchTourOverlay(
                        index: step,
                        name: profile.person.name,
                        tabFrame: ArchTourStep.all[step].tab.flatMap { frames[$0] }.map { proxy[$0] },
                        offersQuestions: profile.person.datePreferences == nil,
                        onNext: { tour(step + 1) },
                        onBack: { tour(step - 1) },
                        onSkip: { tour(nil) },
                        onQuestions: {
                            withAnimation(ArchMotion.standard) { tourStep = nil }
                            selection = .planner
                            plannerStarts += 1
                        }
                    )
                }
                .ignoresSafeArea()
            }
        }
    }

    /// To a step of the tour, moving the app to the tab it is about -- or, past
    /// either end, out of it and back to the roster.
    private func tour(_ step: Int?) {
        withAnimation(ArchMotion.standard) {
            guard let step, ArchTourStep.all.indices.contains(step) else {
                tourStep = nil
                selection = .daily
                return
            }
            tourStep = step
            if let tab = ArchTourStep.all[step].tab {
                selection = tab
            } else if step == ArchTourStep.all.count - 1 {
                selection = .daily
            }
        }
    }

    /// Blocking writes to two places: the roster and conversations live in the
    /// Daily 5 store, the blocked list lives in Settings.
    /// A thread opened or closed in one of the two tabs that can open one.
    ///
    /// Both halves in one place: the tab bar goes away, and the three-second
    /// poll is pointed at the thread being read and taken off it again. Stopping
    /// matters as much as starting -- a timer left running on a screen nobody is
    /// looking at is a request every three seconds, for as long as the app is
    /// open.
    private func reading(_ tab: ArchTab, _ conversationID: String?) {
        switch tab {
        case .messages: messagesThreadOpen = conversationID != nil
        case .daily:    dailyThreadOpen = conversationID != nil
        default:        break
        }
        if let conversationID {
            store.watchThread(conversationID)
        } else {
            store.stopWatchingThread()
        }
    }

    /// The conversation a notification was about, opened in Messages.
    ///
    /// Asked for from the server first when it is not here yet -- the message
    /// that sent the notification is newer than the last refresh, and a tap
    /// that launched the app comes before the first one. If it still is not
    /// there (the conversation has since ended, say), the app just opens.
    private func openFromNotification(_ id: String) async {
        if store.conversation(id) == nil {
            await store.refreshConversations()
        }
        PushNotifications.shared.tappedConversation = nil
        guard store.conversation(id) != nil else { return }
        selection = .messages
        messagesOpening = ConversationOpening(conversationID: id)
    }

    /// Whether the tab showing is showing a conversation.
    private var isReadingThread: Bool {
        (selection == .messages && messagesThreadOpen)
            || (selection == .daily && dailyThreadOpen)
    }

    private var conversationActions: ConversationActions {
        ConversationActions(
            leave: { store.leave($0) },
            block: { person in
                store.block(person)
                if !settings.blocked.contains(person.name) {
                    settings.blocked.append(person.name)
                }
            },
            // **This dropped every report.** It took the reason as `_` and only
            // ever acted on "block as well", so nothing reached `reports`.
            report: { conversation, reason in
                store.report(conversation, reason: reason)
            }
        )
    }

    private var content: some View {
        ZStack {
            tab(.premium) {
                if ArchConfig.isConfigured {
                    // Real money. Prices come from Apple in the reader's own
                    // currency; Premium is granted by the server after it has
                    // asked Apple, and arrives here through `applySubscription`.
                    PremiumView(
                        plans: purchases.plans,
                        isSubscribed: settings.isSubscribed,
                        isAvailable: !purchases.plans.isEmpty,
                        isWorking: purchases.isWorking,
                        problem: purchases.problem,
                        onPurchase: { plan in Task { await purchases.purchase(planID: plan.id) } },
                        onRestore: { Task { await purchases.restore() } }
                    )
                } else {
                    // The design build has no App Store and no account, so the
                    // one way to see both states of this screen is to flip them.
                    PremiumView(isSubscribed: settings.isSubscribed, onPurchase: { _ in
                        settings.isSubscribed.toggle()
                        store.setSubscribed(settings.isSubscribed)
                    })
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
                    waiting: store.waiting,
                    onDismiss: { store.dismiss($0) },
                    onRestore: { store.restore($0) },
                    onSend: { store.startConversation(with: $0, text: $1, quoting: $2) },
                    actions: conversationActions,
                    live: { store.conversation($0) },
                    onReply: { store.reply(to: $0, text: $1) },
                    popToRoot: dailyPops,
                    onThreadOpenChanged: { reading(.daily, $0) }
                )
            }
            tab(.messages) {
                MessagesListView(
                    // `threads`, not `openConversations`: the list shows what
                    // you have written and are waiting on as well as what is
                    // open. The count above stays `openConversations`, because
                    // that is what the server computes the roster hold from.
                    conversations: store.threads,
                    requests: store.requests,
                    onAccept: { store.accept($0) },
                    onDecline: { store.decline($0) },
                    onOpenDaily: { selection = .daily },
                    actions: conversationActions,
                    holdsSlot: { store.holdsSlot($0) },
                    live: { store.conversation($0) },
                    onSend: { store.reply(to: $0, text: $1) },
                    popToRoot: messagePops,
                    onThreadOpenChanged: { reading(.messages, $0) },
                    opening: messagesOpening
                )
            }
            tab(.planner) {
                DatePlannerView(
                    you: profile.person,
                    candidates: plannerCandidates,
                    preset: plannerPreset,
                    onSend: { conversation, text, plan in
                        store.reply(to: conversation, text: text, plan: plan)
                    },
                    onOpenDaily: { selection = .daily },
                    startQuestions: plannerStarts,
                    onSavePreferences: { profile.setDatePreferences($0) }
                )
            }
            tab(.you) {
                YouProfileView(
                    store: profile,
                    settings: settings,
                    writtenAbout: MockData.writtenAbout,
                    onOpenPremium: { selection = .premium },
                    onDeleteAccount: onDeleteAccount,
                    onSignOut: onSignOut,
                    popToRoot: youPops
                )
            }
        }
    }

    /// Who the Date planner offers: the people in Messages, and nobody from the
    /// Daily 5. A date is planned with somebody you are talking to; the roster
    /// is where you decide whether to start. `threads` is the same list the
    /// Messages tab draws, so the two can never disagree about who is in it.
    /// Each person once, in case a list ever holds two threads with one person.
    private var plannerCandidates: [PlannerCandidate] {
        var seen = Set<String>()
        return store.threads.compactMap { conversation in
            seen.insert(conversation.person.id).inserted
                ? PlannerCandidate(person: conversation.person, conversation: conversation)
                : nil
        }
    }

    /// All five stay in the tree; the one you chose is the one you can see.
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
