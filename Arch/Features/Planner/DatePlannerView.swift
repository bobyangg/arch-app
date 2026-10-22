import SwiftUI

/// Somebody to plan with: a person, and your conversation with them -- which is
/// where the plan goes when you send it.
struct PlannerCandidate: Identifiable, Hashable {
    let person: Person
    let conversation: Conversation
    var id: String { person.id }
}

/// The Date planner tab.
///
/// **Only people you are talking to.** A date is planned with somebody you have
/// written to, not somebody Arch has only suggested; the Daily 5 is where you
/// decide whether to talk, and the planner is for after that. It also means
/// every plan has somewhere to go: it is sent into your conversation.
///
/// Pick one of them, and Arch lays out an afternoon or an evening: three
/// stops, a reasonable walk apart, chosen from what you both wrote about
/// yourselves and placed about halfway between you. Any stop can be swapped for
/// the next-best one without disturbing the others.
///
/// **"Share this plan" shares only into Messages.** It opens a list of the
/// people you are talking to -- the one you planned with first -- and the plan
/// goes into whichever conversation you pick, as a card they can say yes to (see
/// `PlanCard`). Not the system share sheet: a plan carries where you will be and
/// when, and the only people it should reach are people you have chosen to talk
/// to here.
///
/// **It never shows how far away anybody lives.** The first stop says how far it
/// is from you, and for them it says only whether it is about as far, or a little
/// further, in words. Their side is computed from their neighbourhood's centre,
/// which is what their profile already shows; a planner that used anything
/// finer would be the one screen in Arch that could find somebody's street.
///
/// **Five questions come first.** The first time the tab is opened it explains
/// itself and asks what you want a date to be like (`PlannerGetStarted`,
/// `DatePreferenceQuestions`); every plan after that is shaped by your answers
/// and, when they have answered too, by theirs -- see `DateFit`.
///
/// **It is computed, not stored.** The plan is rebuilt from `you` and the
/// person you picked on every render, so editing your interests on the You tab,
/// or answering the questions again, changes the plan the next time you look.
///
/// **And a self plan, for a date with yourself.** Last in the row of faces,
/// as "Self plan": the same planner, from your interests and your answers
/// alone, around where you are. It goes to nobody -- there is no conversation
/// for it to go into.
///
/// **A plan you have both said yes to comes first.** Pick somebody you have
/// agreed a plan with -- or say "I'm in" in a thread -- and the planner shows
/// that plan as it was agreed (`AgreedPlan`), with **Make changes**. Changing
/// it opens the planner on its places, and what you share goes to them as a new
/// plan; the agreed one stands until they say yes to that.
/// Where to point the planner when it is opened from a plan in a thread: on this
/// person, at this time of day. Identified, so opening it twice on the same
/// person still counts as a change the planner hears.
struct PlannerPreset: Equatable {
    let personID: String
    let time: DatePlan.TimeOfDay
    /// The plan's day, when it had one and it is still ahead.
    var day: PlanDay? = nil
    /// The plan's items -- what kind of thing, and for how long -- so "Change
    /// it" starts from the same shape of date. Nil for a plan sent before
    /// plans were made of items.
    var items: [PlanItem]? = nil
    /// Open on the plan you have agreed with this person, as it was agreed,
    /// rather than on the planner: after "I'm in".
    var showsAgreed = false
    let id = UUID()
}

struct DatePlannerView: View {
    let you: Person
    let candidates: [PlannerCandidate]
    /// Where the design build plans: `VenueLibrary`, which is Brooklyn and has
    /// no network to need. The real build plans from Apple Maps instead, around
    /// each person, and only falls back to this in previews.
    var venues: [Venue] = VenueLibrary.all
    var preset: PlannerPreset? = nil
    var onSend: (Conversation, String, SharedPlan) -> Void = { _, _, _ in }
    /// Removes a plan you already sent, when the same plan is sent again.
    var onUnsend: (Conversation, String) -> Void = { _, _ in }
    var onOpenDaily: () -> Void = {}
    /// Goes up when the popup after onboarding says "Get started": the planner
    /// opens straight onto the first question. A count, because it is an event.
    var startQuestions: Int = 0
    var onSavePreferences: (DatePreferences) -> Void = { _ in }
    /// Arch Premium: fifteen saved plans instead of ten.
    var isPremium: Bool = false
    /// "See Arch Premium", from a full list of saved plans.
    var onOpenPremium: () -> Void = {}

    @Environment(\.openURL) private var openURL

    @State private var chosenID: String?
    /// The time of day you chose with the toggle, or nil to use what your
    /// answers (and theirs) prefer. Picking another person goes back to nil.
    @State private var pickedTime: DatePlan.TimeOfDay?
    /// The day you chose, or nil for the first one offered (tomorrow).
    @State private var pickedDay: PlanDay?
    /// The question showing, while the questions are; nil otherwise.
    @State private var questionIndex: Int?
    @State private var draft: [Int?] = Array(repeating: nil, count: DatePreferences.questions.count)
    /// The questions as far as you got, kept on the phone as you answer --
    /// option indices, "-" for one not answered yet; empty when nothing is
    /// waiting -- so backing out part-way loses nothing (`startAsking`).
    @AppStorage(DatePlannerView.draftKey) private var keptDraft = ""
    static let draftKey = "arch.datePreferenceDraft"
    /// What you have added to the date, in order. It opens with one blank
    /// item, and holds at most `PlanItem.maximum`.
    @State private var items: [PlanItem] = [PlanItem()]
    /// Said for a moment after the plan has been worked out again because
    /// somebody's interests changed, so that a rerun which lands on the same
    /// places is still visibly a rerun.
    @State private var replanned: String?
    /// Who the plan last went to, by name, for the line under the button.
    @State private var sentTo: String?
    /// The plan being shared, while the list of people is open.
    @State private var sharing: DatePlan?
    /// What Apple Maps found, per person. Kept while the tab is alive, so going
    /// back to somebody does not search again.
    @State private var nearby: [String: VenueSearch.Nearby] = [:]
    /// The people for whom Apple Maps could not be reached.
    @State private var unreachable: Set<String> = []
    /// Bumped by "Try again", which is what makes the search run again.
    @State private var attempt = 0

    /// A real build plans from Apple Maps. A design build has no backend, may
    /// have no network, and runs the UI tests -- it keeps the bundled venues.
    private var isLive: Bool { ArchConfig.isConfigured }

    /// The self plan's place in the row of faces, and its key wherever a
    /// person's id would go.
    static let selfPlanID = "self-plan"

    /// Planning for yourself: you chose "Self plan", or there is nobody else
    /// yet to plan with.
    private var isSolo: Bool { chosenID == Self.selfPlanID || candidates.isEmpty }

    /// The match you are planning with. Nil on a self plan.
    private var chosen: PlannerCandidate? {
        guard !isSolo else { return nil }
        return candidates.first { $0.id == chosenID } ?? candidates.first
    }

    /// Who the plan is for besides you: the match, or -- on a self plan -- you
    /// again, which is how the planner is asked for a plan for one.
    private var planningWith: Person? { isSolo ? you : chosen?.person }

    /// What the places found are kept under: the match's id, or the self plan's.
    private var planningID: String { isSolo ? Self.selfPlanID : (chosen?.id ?? "") }

    /// The day you picked, if it can still be planned for; otherwise
    /// tomorrow. Worked out on every draw, so a planner left open overnight
    /// moves on with the calendar.
    private var day: PlanDay? {
        if let pickedDay, pickedDay.isPlannable { return pickedDay }
        return PlanDay.earliest()
    }

    /// The calendar, while it is open.
    @State private var choosingDate = false
    /// Your answers, in their sheet, while it is open.
    @State private var showingPreferences = false
    /// The stops opened to their details, by item. Closed, a stop is two lines.
    @State private var openStops: Set<UUID> = []
    /// The finer print under the plan, while it is open.
    @State private var showingDetails = false
    /// Places never to offer: what you said was "Not for us", and what the
    /// team has taken off for everybody. Loaded once; a design build keeps
    /// yours for as long as the app is open.
    @State private var notToOffer: Set<String> = []
    /// Places Apple Maps could not find again by their own name where they are
    /// listed (`VenueSearch.isFoundAgain`). Left out like "Not for us", for as
    /// long as the app is open.
    @State private var notFoundAgain: Set<String> = []
    /// The place just hidden, for the line that offers to undo it.
    @State private var justHidden: (id: String, name: String)?
    /// The last Swap, for Undo: which item, what it was before, and the place
    /// it moved off. Cleared by anything that changes the plan another way.
    @State private var lastSwap: (itemID: UUID, previous: PlanItem, name: String)?
    /// The agreed plan being changed, by its message's id. While it matches
    /// the plan agreed with the person on screen, the planner shows, under a
    /// line saying what is being changed; otherwise the agreed plan does.
    @State private var changingAgreed: String?
    /// While Cancel is asking first.
    @State private var askingCancel = false
    /// What Add to calendar is adding, and what Export is sending, while
    /// their sheets are open.
    @State private var calendarDraft: PlanCalendarDraft?
    @State private var exporting: PlanShareItems?
    /// Your confirmed self plan, as JSON, kept on this phone: it goes into no
    /// conversation, so there is nowhere on the server it belongs. Empty when
    /// there is none.
    @AppStorage("arch.selfPlan") private var savedSelfPlan = ""
    /// Plans saved for later, as JSON, kept on this phone like the confirmed
    /// self plan: nothing is sent until you share one. Every account's are in
    /// here, each marked with its owner, and only yours are shown.
    @AppStorage("arch.savedPlans") private var savedPlansJSON = ""
    /// The list of saved plans, while its sheet is open.
    @State private var showingSaved = false
    /// The item a custom spot is being chosen for, while its sheet is open.
    @State private var customFor: UUID?
    /// The place "Maps" is showing on a map, while its sheet is open.
    @State private var mapping: Venue?
    /// "Photos and reviews on Google", while its page is open.
    @State private var browsing: BrowserPage?
    /// Saving with the list of saved plans already full.
    @State private var savedFull = false
    /// The distance in the preferences sheet while it moves; saved a moment
    /// after it stops.
    @State private var sheetMiles: Int?
    /// **One plan in progress per person.** What you built with somebody --
    /// the items, their hours and swaps, the time of day and the day -- is
    /// kept when you switch to somebody else, and is there when you come back.
    /// For as long as the app is open; a saved plan is the one that lasts.
    @State private var sessions: [String: PlanSession] = [:]

    private struct PlanSession {
        var items: [PlanItem]
        var time: DatePlan.TimeOfDay?
        var day: PlanDay?
    }
    /// A share that found the same plan already sent to that person, while
    /// the question about it is up.
    @State private var repeatShare: RepeatShare?

    /// The same plan, already in the conversation: the person, the plan about
    /// to go, and the earlier copies -- removable unless one was answered.
    private struct RepeatShare: Identifiable {
        let id = UUID()
        let candidate: PlannerCandidate
        let text: String
        let plan: SharedPlan
        let earlier: [String]
        /// Somebody said "I'm in" to it, or it was cancelled: it is history,
        /// not something to resend.
        let settled: Bool
    }
    /// While a confirmed self plan is being changed.
    @State private var changingSelf = false

    /// A confirmed self plan, as kept: whose it is, so another account
    /// signed in on this phone does not see it.
    private struct SavedSelfPlan: Codable {
        let owner: String
        let plan: SharedPlan
    }

    /// Your confirmed self plan, while its day is still to come.
    private var confirmedSelfPlan: SharedPlan? {
        guard let data = savedSelfPlan.data(using: .utf8),
              let saved = try? JSONDecoder().decode(SavedSelfPlan.self, from: data),
              saved.owner == you.id, saved.plan.isPlan else { return nil }
        if let day = saved.plan.planDay, day < .today { return nil }
        return saved.plan
    }
    /// Said after a date has been called off, until you pick somebody else.
    @State private var cancelledNote: String?

    /// Whether any item keeps a place from a plan that was sent. Those need no
    /// search and no answers to the questions to show: "Change it" on
    /// somebody's plan opens on their places, whatever else is not ready yet.
    private var hasKept: Bool { items.contains { $0.pinned != nil } }

    /// What the rankings are built from that can change under you: your
    /// interests, and the interests of the person you are planning with.
    private struct PlanInputs: Equatable {
        let personID: String?
        let yours: [String]
        let theirs: [String]
    }

    private var inputs: PlanInputs {
        PlanInputs(personID: planningID,
                   yours: you.interests.map(\.text),
                   theirs: chosen?.person.interests.map(\.text) ?? [])
    }

    /// The toggle's choice, or else the time your answers prefer -- and
    /// theirs, when there is somebody else.
    private func openingTime(with person: Person?) -> DatePlan.TimeOfDay {
        pickedTime ?? DateFit(yours: you.datePreferences, theirs: person?.datePreferences).time
    }

    var body: some View {
        TopBarScroll {
            VStack(alignment: .leading, spacing: 0) {
                masthead

                if questionIndex != nil {
                    DatePreferenceQuestions(index: $questionIndex, draft: $draft, centre: you.matchPoint) { answers in
                        saveAnswers(answers)
                    }
                } else if let chosen, let agreed = chosen.conversation.agreedPlan,
                          changingAgreed != agreed.messageID {
                    // Nothing here needs your answers to the questions: the
                    // plan is already made.
                    picker
                    settledScreen(settled(agreed, with: chosen),
                                  onChange: { change(agreed) },
                                  onCancel: { cancel(agreed, with: chosen) })
                } else if isSolo, let confirmed = confirmedSelfPlan, !changingSelf {
                    // Your confirmed self plan, settled the same way.
                    picker
                    settledScreen(settledSelf(confirmed),
                                  onChange: { changeSelf(confirmed) },
                                  onCancel: { cancelSelf(confirmed) })
                } else if you.datePreferences == nil && !hasKept {
                    if candidates.contains(where: { $0.conversation.agreedPlan != nil }) || cancelledNote != nil {
                        picker
                    }
                    cancelledLine
                    if let chosen, let agreed = chosen.conversation.agreedPlan {
                        changingBanner(agreed, with: chosen)
                    }
                    PlannerGetStarted(answered: keptAnswers?.compactMap { $0 }.count ?? 0) { startAsking() }
                } else if let person = planningWith {
                    picker
                    cancelledLine
                    if let chosen, let agreed = chosen.conversation.agreedPlan {
                        changingBanner(agreed, with: chosen)
                    }
                    if isSolo, changingSelf, let confirmed = confirmedSelfPlan {
                        changingSelfBanner(confirmed)
                    }
                    if isLive && nearby[planningID] == nil && !hasKept {
                        looking(for: planningID)
                    } else {
                        // Apple Maps' places in a real build, the bundled ones
                        // in a design build. Everything after this line is the
                        // same either way.
                        let found = nearby[planningID]
                        let time = openingTime(with: chosen?.person)
                        let plan = makePlan(for: person)
                        if isLive && (found?.venues.isEmpty ?? true) && !hasKept {
                            settingsRow(time)
                            nowhereNearby
                        } else {
                            // **Plan first.** One row of settings and one line
                            // saying what it is built on; then the stops.
                            settingsRow(time)
                            basisLine(plan)
                            distanceNote(plan)
                            if let justHidden {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(justHidden.name) will not be suggested again.")
                                        .archText(.footnote)
                                        .foregroundStyle(ArchColor.mortar)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: ArchSpacing.s)
                                    ArchTextButton(title: "Undo") { unhide() }
                                        .accessibilityIdentifier("planner.undoHide")
                                }
                                .padding(.bottom, ArchSpacing.s)
                            }
                            if let replanned {
                                Text(replanned)
                                    .archText(.footnote)
                                    .foregroundStyle(ArchColor.lamp)
                                    .padding(.bottom, ArchSpacing.s)
                                    .accessibilityIdentifier("planner.replanned")
                            }
                            itinerary(plan)
                                .task(id: plan.stops.map(\.venue.id).joined(separator: "|")) {
                                    // Not the places kept from a plan that was
                                    // sent: those are what they chose, and
                                    // "Change it" opens on them as they are.
                                    let kept = Set(items.compactMap(\.pinned?.id))
                                    await checkStops(plan.stops.map(\.venue).filter { !kept.contains($0.id) })
                                }
                            if !plan.stops.isEmpty {
                                facts(plan)
                            }
                        }
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.bottom, ArchSpacing.sectionGap)
        }
        // Share -- or Confirm, on a self plan -- kept in reach at the bottom
        // rather than at the end of the scroll.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let plan = planOnScreen, !plan.stops.isEmpty {
                bottomBar(plan)
            }
        }
        .background(ArchColor.night)
        .sheet(item: $mapping) { venue in
            PlaceMapSheet(venue: venue, onClose: { mapping = nil })
        }
        .sheet(item: $browsing) { page in
            InAppBrowser(url: page.url)
                .ignoresSafeArea()
        }
        .task(id: "\(planningID)#\(attempt)") { await findPlaces() }
        .task {
            guard isLive else { return }
            notToOffer.formUnion(await ArchBackend.placesNotToOffer())
        }
        // Somebody else: their own session comes back (`switchPlanning`), so
        // nothing here resets the items -- only what was said about the last
        // person's plan. Another time or another day resets the swaps, from
        // the controls that change them, not from here: restoring a session
        // sets the time and day too, and must not undo its swaps.
        .onChange(of: chosenID) { _, _ in
            openStops = []
            showingDetails = false
            lastSwap = nil
            sentTo = nil
            replanned = nil
            cancelledNote = nil
            changingSelf = false
        }
        .onChange(of: pickedTime) { _, _ in sentTo = nil }
        .onChange(of: pickedDay) { _, _ in sentTo = nil }
        // **Interests changed: plan again, and say so.** The plan is computed
        // from both of you on every draw, so it always followed an edit -- but
        // a swap count from the old rankings pointed at an arbitrary place in
        // the new ones, and a rerun that landed on the same places looked like
        // nothing had happened. Now every item goes back to its best place
        // under the new interests, and a line says why the plan moved. Theirs
        // arrive with the conversations, which are fetched every twelve seconds.
        .onChange(of: inputs) { old, new in
            // Picking somebody else is not a change of interests.
            guard old.personID == new.personID else { return }
            restartSwaps()
            sentTo = nil
            if old.yours != new.yours {
                replanned = "Replanned around your new interests."
            } else if old.theirs != new.theirs, let name = chosen?.person.name {
                replanned = "Replanned around \(name)\u{2019}s new interests."
            }
        }
        .onChange(of: you.datePreferences) { _, _ in restartSwaps() }
        // "Change it" on a plan in a thread lands here, on that person.
        .onChange(of: preset) { _, preset in
            guard let preset else { return }
            questionIndex = nil
            if preset.personID != planningID { keepSession() }
            chosenID = preset.personID
            sentTo = nil
            cancelledNote = nil
            // "I'm in": the agreed plan, as it was agreed.
            if preset.showsAgreed {
                changingAgreed = nil
                return
            }
            // A change to a plan, with one already agreed, is a change to it.
            changingAgreed = candidates.first { $0.id == preset.personID }?
                .conversation.agreedPlan?.messageID
            pickedTime = preset.time
            pickedDay = preset.day
            if let restored = preset.items, !restored.isEmpty {
                items = restored
            } else {
                restartSwaps()
            }
            sentTo = nil
            replanned = nil
        }
        // "Get started" in the popup after onboarding.
        .onChange(of: startQuestions) { _, _ in startAsking() }
        // Each answer is kept as it is given; leaving part-way keeps the rest.
        .onChange(of: draft) { _, answers in
            if questionIndex != nil { keep(answers) }
        }
        .onChange(of: questionIndex) { old, new in
            if old != nil, new == nil { leftQuestions() }
        }
    }

    /// The plan for the person on screen -- or you, on a self plan -- from
    /// Apple Maps' places in a real build and the bundled ones in a design
    /// build. While Apple Maps is still answering, places kept from a plan show
    /// at once and the rest fill in after; never the design build's Brooklyn.
    private func makePlan(for person: Person) -> DatePlan {
        let found = nearby[planningID]
        return DatePlanner.plan(you: you, them: person, time: openingTime(with: chosen?.person),
                                day: day, venues: found?.venues ?? (isLive ? [] : venues),
                                items: items,
                                theirCentre: found?.theirCentre,
                                halfwayName: found?.halfway,
                                alreadyShared: chosen.map(alreadyShared(with:)) ?? [],
                                excluded: notToOffer.union(notFoundAgain))
    }

    /// The plan the screen is showing, when it is showing one being made --
    /// for the bar pinned under it. Nil on the questions, Get started, a
    /// settled plan, and while there is nothing yet to plan from.
    private var planOnScreen: DatePlan? {
        guard questionIndex == nil, let person = planningWith else { return nil }
        if let chosen, let agreed = chosen.conversation.agreedPlan, changingAgreed != agreed.messageID { return nil }
        if isSolo, confirmedSelfPlan != nil, !changingSelf { return nil }
        if you.datePreferences == nil && !hasKept { return nil }
        if isLive && !hasKept && (nearby[planningID]?.venues.isEmpty ?? true) { return nil }
        return makePlan(for: person)
    }

    /// The places in plans you have already sent this person, so the planner
    /// can offer somewhere new first. Read off the conversation, which already
    /// holds every plan sent in it.
    private func alreadyShared(with candidate: PlannerCandidate) -> Set<String> {
        Set(candidate.conversation.messages
            .filter(\.isOutgoing)
            .compactMap(\.plan?.stops)
            .joined()
            .map(\.name))
    }

    /// To somebody else's plan: this one is put aside as it is, and theirs
    /// comes back -- or, for somebody you have not planned with yet, a blank
    /// item.
    private func switchPlanning(to id: String) {
        guard id != planningID else { return }
        keepSession()
        chosenID = id
        let session = sessions[id] ?? PlanSession(items: [PlanItem()], time: nil, day: nil)
        items = session.items
        pickedTime = session.time
        pickedDay = session.day
    }

    /// The plan on screen, put aside under whoever it is with.
    private func keepSession() {
        sessions[planningID] = PlanSession(items: items, time: pickedTime, day: pickedDay)
    }

    /// Every item back to the best place in its ranking. Places kept from a
    /// plan that was sent stay kept.
    private func restartSwaps() {
        lastSwap = nil
        items = items.map { item in
            var item = item
            item.skips = 0
            item.passed = []
            return item
        }
    }

    /// Swap: the next place along. A kept place -- from a plan that was sent
    /// -- is let go, and the planner chooses, starting past it.
    private func swap(_ index: Int, from venue: Venue) {
        guard items.indices.contains(index) else { return }
        // Kept for Undo: a Swap tapped by accident should cost one tap back.
        lastSwap = (items[index].id, items[index], venue.name)
        if items[index].pinned != nil {
            items[index].pinned = nil
            items[index].pinnedFrom = nil
            items[index].passed.insert(venue.id)
        } else {
            items[index].skips += 1
        }
        replanned = nil
        justHidden = nil
        sentTo = nil
    }

    /// Undo the last Swap: the item exactly as it was, so the place comes back.
    private func undoSwap() {
        guard let last = lastSwap,
              let index = items.firstIndex(where: { $0.id == last.itemID }) else { return }
        items[index] = last.previous
        lastSwap = nil
        sentTo = nil
    }

    /// "Not for us": never this place again, and the item moves on at once.
    /// Saved for your account in a real build, so it holds on every phone.
    private func hide(_ venue: Venue, at index: Int) {
        lastSwap = nil
        notToOffer.insert(venue.id)
        if items.indices.contains(index), items[index].pinned?.id == venue.id {
            items[index].pinned = nil
            items[index].pinnedFrom = nil
        }
        justHidden = (venue.id, venue.name)
        replanned = nil
        sentTo = nil
        guard isLive else { return }
        Task { try? await ArchBackend.hidePlace(key: venue.id, name: venue.name) }
    }

    private func unhide() {
        guard let hidden = justHidden else { return }
        notToOffer.remove(hidden.id)
        justHidden = nil
        guard isLive else { return }
        Task { try? await ArchBackend.unhidePlace(key: hidden.id) }
    }

    // MARK: Settled plans

    /// A plan that is decided, as its screen shows it: one agreed with a
    /// match, or a self plan you confirmed. One screen for both, so the two
    /// work the same way -- Maps on every stop, Add to calendar, Export, Make
    /// changes, and Cancel.
    private struct Settled {
        let plan: SharedPlan
        /// "You are both in", "Confirmed".
        let badge: String
        /// "Thursday evening with Hana", "Monday afternoon, just you". Also
        /// the heading of what Export sends.
        let title: String
        /// Under the stops, after when it ends: "Hana said yes."
        let closing: String
        /// A newer plan still waiting, when there is one.
        let note: String?
        /// Under Make changes: what a change does.
        let changeNote: String
        /// The calendar event's name.
        let eventTitle: String
        let cancelTitle: String
        let cancelQuestion: String
        let cancelMessage: String
    }

    /// "evening" or "afternoon".
    private func partOfDay(_ plan: SharedPlan) -> String {
        plan.timeOfDay == .evening ? "evening" : "afternoon"
    }

    /// "Thursday evening", or "the evening" for a plan with no day.
    private func when(_ plan: SharedPlan) -> String {
        plan.planDay.map { "\($0.weekdayName) \(partOfDay(plan))" } ?? "the \(partOfDay(plan))"
    }

    private func settled(_ agreed: AgreedPlan, with candidate: PlannerCandidate) -> Settled {
        let name = candidate.person.name
        let part = partOfDay(agreed.plan)
        return Settled(
            plan: agreed.plan,
            badge: "You are both in",
            title: agreed.plan.planDay.map { "\($0.weekdayName) \(part) with \(name)" } ?? "An \(part) with \(name)",
            closing: agreed.saidYesByThem ? "\(name) said yes." : "You said yes.",
            note: agreed.newerSentByYou.map { byYou in
                byYou ? "You sent \(name) a newer plan. It is waiting on them."
                      : "\(name) sent a newer plan. It is waiting on you in your conversation."
            },
            changeNote: "Changes go to \(name) as a new plan. This one stands until they say yes.",
            eventTitle: "Date with \(name)",
            cancelTitle: "Cancel the date",
            cancelQuestion: "Cancel your \(when(agreed.plan)) with \(name)?",
            cancelMessage: "\(name) will see that it is off, in your conversation."
        )
    }

    private func settledSelf(_ plan: SharedPlan) -> Settled {
        let part = partOfDay(plan)
        return Settled(
            plan: plan,
            badge: "Confirmed",
            title: plan.planDay.map { "\($0.weekdayName) \(part), just you" } ?? "An \(part), just you",
            closing: "A plan just for you.",
            note: nil,
            changeNote: "Changes replace this plan when you confirm them.",
            eventTitle: "Self plan",
            cancelTitle: "Cancel this plan",
            cancelQuestion: "Cancel your self plan for \(when(plan))?",
            cancelMessage: "It is only on this phone, so nobody else is told."
        )
    }

    /// "Make changes": the planner, opened on the agreed plan's day, time and
    /// places, each saying where it came from.
    private func change(_ agreed: AgreedPlan) {
        reopen(agreed.plan, from: "From your agreed plan.")
        changingAgreed = agreed.messageID
    }

    /// "Make changes" on a confirmed self plan.
    private func changeSelf(_ plan: SharedPlan) {
        reopen(plan, from: "From your confirmed plan.")
        changingSelf = true
    }

    private func reopen(_ plan: SharedPlan, from: String) {
        items = plan.planItems(from: from) ?? [PlanItem()]
        pickedTime = plan.timeOfDay
        pickedDay = plan.planDay
        replanned = nil
        justHidden = nil
        sentTo = nil
    }

    /// "Cancel the date": said in the conversation, tied to the plan, so it
    /// is off on both phones -- the card in the thread says who cancelled it.
    private func cancel(_ agreed: AgreedPlan, with candidate: PlannerCandidate) {
        let whenText = when(agreed.plan)
        onSend(candidate.conversation,
               "I have to cancel our plan for \(whenText).",
               SharedPlan(cancelling: agreed.messageID))
        cancelledNote = "Your plan with \(candidate.person.name) for \(whenText) is cancelled. It says so in your conversation."
        changingAgreed = nil
        sentTo = nil
    }

    /// "Confirm this plan": the self plan, frozen as it is and kept on this
    /// phone, and the screen it is settled on.
    private func confirmSelf(_ plan: DatePlan) {
        let frozen = SavedSelfPlan(owner: you.id, plan: SharedPlan(plan, sharedWith: you, plannedWith: you))
        guard let data = try? JSONEncoder().encode(frozen),
              let json = String(data: data, encoding: .utf8) else { return }
        savedSelfPlan = json
        changingSelf = false
        cancelledNote = nil
    }

    private func cancelSelf(_ plan: SharedPlan) {
        savedSelfPlan = ""
        changingSelf = false
        cancelledNote = "Your self plan for \(when(plan)) is cancelled."
    }

    /// After a cancel.
    @ViewBuilder
    private var cancelledLine: some View {
        if let cancelledNote {
            Text(cancelledNote)
                .archText(.footnote)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, ArchSpacing.l)
                .accessibilityIdentifier("planner.cancelled")
        }
    }

    /// A settled plan: when, where and for how long, each place a tap from
    /// Apple Maps -- and what can be done with it now.
    private func settledScreen(_ settled: Settled,
                               onChange: @escaping () -> Void,
                               onCancel: @escaping () -> Void) -> some View {
        let plan = settled.plan
        let stops = plan.stops ?? []
        let ends = stops.last.map { $0.start + ($0.minutes ?? 60) }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(settled.badge)
                    .archText(.caption)
                    .foregroundStyle(ArchColor.lamp)
                Text(settled.title)
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ArchSpacing.xxs)
                if let day = plan.planDay {
                    Text("\(day.long) \u{00B7} \(untilDay(day))")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                        .padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                        if let travel = stop.travel {
                            HStack(spacing: ArchSpacing.s) {
                                Rectangle()
                                    .fill(ArchColor.quietBorder)
                                    .frame(width: 2, height: 28)
                                    .padding(.leading, 32)
                                Text(travel)
                                    .archText(.footnote)
                                    .foregroundStyle(ArchColor.mortar)
                            }
                            .padding(.vertical, ArchSpacing.xxs)
                        } else if index > 0 {
                            Color.clear.frame(height: ArchSpacing.s)
                        }
                        settledStop(stop, index: index)
                    }
                }
                .padding(.top, ArchSpacing.m)

                Text(([ends.map { "Done by about \(DatePlanner.clockTime($0))." }].compactMap { $0 }
                      + [settled.closing])
                    .joined(separator: " "))
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .padding(.top, ArchSpacing.m)
            }
            .padding(ArchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                    .fill(ArchColor.stone)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("planner.agreed")

            if let note = settled.note {
                Text(note)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ArchSpacing.m)
            }

            // Out of Arch: into your calendar, or to anybody through any app.
            HStack(spacing: ArchSpacing.xs) {
                ArchButton(title: "Add to calendar", kind: .quiet) {
                    calendarDraft = PlanCalendarDraft(plan: plan, title: settled.eventTitle)
                }
                .accessibilityIdentifier("planner.agreed.calendar")
                ArchButton(title: "Export", kind: .quiet) {
                    exporting = PlanShareItems(items: PlanExport.items(for: plan, title: settled.title))
                }
                .accessibilityLabel("Export this plan")
                .accessibilityHint("Send it through Messages, Instagram or any other app")
                .accessibilityIdentifier("planner.agreed.export")
            }
            .padding(.top, ArchSpacing.m)

            ArchButton(title: "Make changes", kind: .quiet) {
                withAnimation(ArchMotion.standard) { onChange() }
            }
            .accessibilityIdentifier("planner.agreed.edit")
            .padding(.top, ArchSpacing.xs)

            Text(settled.changeNote)
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, ArchSpacing.s)

            // Asked first: for a date it tells them, and it cannot be taken back.
            ArchTextButton(title: settled.cancelTitle) { askingCancel = true }
                .accessibilityIdentifier("planner.agreed.cancel")
                .padding(.top, ArchSpacing.m)
        }
        .confirmationDialog(settled.cancelQuestion, isPresented: $askingCancel, titleVisibility: .visible) {
            Button("Yes, cancel it", role: .destructive) {
                withAnimation(ArchMotion.standard) { onCancel() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(settled.cancelMessage)
        }
        .sheet(item: $calendarDraft) { draft in
            // Apple's own new-event screen, filled in; nothing is added until
            // you tap Add there (`CalendarEventSheet`).
            CalendarEventSheet(plan: draft.plan, title: draft.title) { calendarDraft = nil }
                .ignoresSafeArea()
        }
        .sheet(item: $exporting) { export in
            PlanShareSheet(items: export.items)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    private func settledStop(_ stop: SharedPlan.Stop, index: Int) -> some View {
        HStack(alignment: .top, spacing: ArchSpacing.s) {
            Text(DatePlanner.clockTime(stop.start))
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
                Text(([stop.kind, stop.neighbourhood]
                      + (stop.minutes.map { ["\($0 / 60) hr"] } ?? []))
                    .joined(separator: " \u{00B7} "))
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }
            Spacer(minLength: 0)
            if let venue = stop.venue, venue.mapsURL != nil {
                ArchTextButton(title: "Maps") { mapping = venue }
                    .fixedSize()
                    .frame(height: 32)
                    .accessibilityLabel("Show \(stop.name) on a map")
                    .accessibilityIdentifier("planner.agreed.maps.\(index)")
            }
        }
    }

    /// "Tomorrow", "In 4 days".
    private func untilDay(_ day: PlanDay) -> String {
        let days = Calendar.current.dateComponents([.day], from: PlanDay.today.date, to: day.date).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1:    return "Tomorrow"
        default:   return "In \(days) days"
        }
    }

    /// Over the planner while an agreed plan is being changed.
    private func changingBanner(_ agreed: AgreedPlan, with candidate: PlannerCandidate) -> some View {
        changingBanner(
            title: "Changing your plan for \(when(agreed.plan))",
            detail: "Share it to send \(candidate.person.name) the new version. The plan you agreed stands until they say yes.",
            back: "Back to the agreed plan"
        ) {
            changingAgreed = nil
            sentTo = nil
        }
    }

    /// Over the planner while a confirmed self plan is being changed.
    private func changingSelfBanner(_ plan: SharedPlan) -> some View {
        changingBanner(
            title: "Changing your self plan for \(when(plan))",
            detail: "Confirm it to replace the one you have.",
            back: "Back to your confirmed plan"
        ) {
            changingSelf = false
        }
    }

    /// What is being changed, and the way back to it.
    private func changingBanner(title: String, detail: String, back: String,
                                onBack: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
            Text(title)
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)
            Text(detail)
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
            ArchTextButton(title: back) {
                withAnimation(ArchMotion.standard) { onBack() }
            }
            .fixedSize()
            .accessibilityIdentifier("planner.agreed.back")
        }
        .padding(ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(ArchColor.stone)
        )
        .padding(.bottom, ArchSpacing.l)
    }

    // MARK: Items

    /// "Custom spot": the place you named, kept as it is in this item -- as
    /// food or an activity by what it is, for the time it usually takes.
    private func addCustom(_ venue: Venue, to itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let category = venue.kind.category
        withAnimation(ArchMotion.standard) {
            items[index].category = category
            items[index].hours = category.defaultHours
            items[index].skips = 0
            items[index].pinned = venue
            items[index].pinnedFrom = "Your pick."
        }
        replanned = nil
        sentTo = nil
    }

    private func fill(_ index: Int, with category: DatePlan.Category) {
        guard items.indices.contains(index) else { return }
        items[index].category = category
        items[index].hours = category.defaultHours
        items[index].skips = 0
        replanned = nil
        sentTo = nil
    }

    private func add() {
        guard items.count < PlanItem.maximum else { return }
        items.append(PlanItem())
        replanned = nil
    }

    /// Never down to nothing: the last one removed leaves a blank one.
    private func remove(_ index: Int) {
        lastSwap = nil
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        if items.isEmpty { items = [PlanItem()] }
        replanned = nil
        sentTo = nil
    }

    /// Into the questions: where you left them if you backed out part-way,
    /// with every answer you had given; otherwise from what you said last
    /// time, if you have said anything.
    private func startAsking() {
        if let kept = keptAnswers {
            draft = kept
            withAnimation(ArchMotion.standard) { questionIndex = kept.firstIndex { $0 == nil } ?? 0 }
        } else {
            draft = you.datePreferences?.answers
                ?? Array(repeating: nil, count: DatePreferences.questions.count)
            withAnimation(ArchMotion.standard) { questionIndex = 0 }
        }
    }

    /// The answers kept from a run you backed out of: one per question, nil
    /// for any not answered. Nil when nothing is kept, or what is kept no
    /// longer fits the questions.
    private var keptAnswers: [Int?]? {
        let parts = keptDraft.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == DatePreferences.questions.count else { return nil }
        let answers: [Int?] = zip(parts, DatePreferences.questions).map { part, question in
            Int(part).flatMap { value in
                (question.isMiles ? DatePreferences.milesRange.contains(value)
                                  : question.options.indices.contains(value)) ? value : nil
            }
        }
        return answers.contains { $0 != nil } ? answers : nil
    }

    private func keep(_ answers: [Int?]) {
        keptDraft = answers.map { answer in answer.map { String($0) } ?? "-" }.joined(separator: ",")
    }

    /// Your answers, as yours: whether the questions were finished or left
    /// with every one answered.
    private func saveAnswers(_ preferences: DatePreferences) {
        keptDraft = ""
        onSavePreferences(preferences)
        restartSwaps()
        // Changing an agreed plan keeps its time of day.
        if changingAgreed == nil { pickedTime = nil }
    }

    /// Out of the questions without finishing them: Back from the first, or
    /// "Change it" from a thread. A full set is saved as your answers, as
    /// finishing would have done; part of one waits for next time.
    private func leftQuestions() {
        guard !keptDraft.isEmpty, let preferences = DatePreferences(answers: draft) else { return }
        if preferences == you.datePreferences {
            keptDraft = ""
        } else {
            saveAnswers(preferences)
        }
    }

    /// Asks Apple Maps about the person on screen, once.
    ///
    /// The person is read before the wait and checked after it: switching to
    /// somebody else cancels this, and a cancelled search must not mark the
    /// person it was for as unreachable.
    private func findPlaces() async {
        let id = planningID
        guard isLive, let person = planningWith, nearby[id] == nil else { return }
        unreachable.remove(id)
        // On a self plan, `person` is you: the search centres on you.
        let found = await VenueSearch.nearby(you: you, them: person)
        guard !Task.isCancelled else { return }
        if let found {
            nearby[id] = found
        } else {
            unreachable.insert(id)
        }
    }

    /// Each stop on screen, checked once against Apple Maps the way you would
    /// check it -- by searching its name where it is (`VenueSearch.isFoundAgain`).
    /// A stop that is not found there is left out, and the plan redraws with
    /// the next place in its place; the new stop is checked in turn.
    private func checkStops(_ venues: [Venue]) async {
        guard isLive else { return }
        for venue in venues where !notFoundAgain.contains(venue.id) {
            let found = await VenueSearch.isFoundAgain(venue)
            guard !Task.isCancelled else { return }
            if !found { notFoundAgain.insert(venue.id) }
        }
    }

    // MARK: Pieces

    private var masthead: some View {
        HStack(alignment: .center) {
            Text("Date planner")
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)
            Spacer(minLength: ArchSpacing.s)
            // Plans saved for later, a tap from the title. Not over the
            // questions, which are a screen of their own.
            if questionIndex == nil {
                Button { showingSaved = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: savedPlans.isEmpty ? "bookmark" : "bookmark.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(savedPlans.isEmpty ? "Saved" : "Saved \u{00B7} \(savedPlans.count)")
                            .archText(.footnote)
                    }
                    .foregroundStyle(ArchColor.limestone)
                    .padding(.horizontal, ArchSpacing.s)
                    .frame(height: 36)
                    .background(Capsule().fill(ArchColor.stone))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
                .accessibilityLabel("Saved plans, \(savedPlans.count)")
                .accessibilityIdentifier("planner.saved")
            }
        }
        .padding(.top, ArchSpacing.xs)
        .padding(.bottom, ArchSpacing.l)
        .sheet(isPresented: $showingSaved) {
            SavedPlansSheet(
                plans: savedPlans,
                person: { id in id == Self.selfPlanID ? you : candidates.first { $0.id == id }?.person },
                title: savedTitle,
                onOpen: { saved in
                    showingSaved = false
                    open(saved)
                },
                onDelete: { saved in unsave(saved.key) },
                onClose: { showingSaved = false },
                limit: savedLimit,
                premiumLimit: Self.savedLimitPremium,
                isPremium: isPremium,
                onOpenPremium: {
                    showingSaved = false
                    onOpenPremium()
                }
            )
        }
    }

    /// Your matches and the people you are talking to, in one row. Faces rather
    /// than names alone, because a row of names is a list you have to read.
    private var picker: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Plan with")
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)

            ScrollView(.horizontal) {
                // Top-aligned: "Agreed" or "Confirmed" under a name makes that
                // face's column taller, and centred it rose above the others.
                // The faces stay on one line; the word only adds below.
                HStack(alignment: .top, spacing: ArchSpacing.m) {
                    ForEach(candidates) { candidate in
                        let isChosen = candidate.id == chosen?.id
                        let hasAgreed = candidate.conversation.agreedPlan != nil
                        Button {
                            switchPlanning(to: candidate.id)
                        } label: {
                            VStack(spacing: ArchSpacing.xs) {
                                PhotoPlaceholder(toneIndex: candidate.person.avatarToneIndex,
                                                 url: candidate.person.mainPhoto?.url,
                                                 data: candidate.person.mainPhoto?.local)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: ArchRadius.control,
                                                                style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: ArchRadius.control + 3,
                                                         style: .continuous)
                                            .stroke(ArchColor.limestone, lineWidth: isChosen ? 2 : 0)
                                            .padding(-3)
                                    }
                                Text(candidate.person.name)
                                    .archText(.caption)
                                    .foregroundStyle(isChosen ? ArchColor.limestone : ArchColor.mortar)
                                // Somebody you have a plan with says so.
                                if hasAgreed {
                                    Text("Agreed")
                                        .archText(.caption)
                                        .foregroundStyle(ArchColor.lamp)
                                        .padding(.top, -ArchSpacing.xxs)
                                }
                            }
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel(hasAgreed ? "\(candidate.person.name), plan agreed" : candidate.person.name)
                        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
                        // By id: a name is also on their row in Messages and
                        // their card in the Daily 5.
                        .accessibilityIdentifier("planner.with.\(candidate.id)")
                    }
                    selfPlanButton
                }
                .padding(.vertical, ArchSpacing.xxs)
                .padding(.horizontal, 3)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("planner.picker")

            // With nobody else yet, the self plan is the plan -- and the way
            // to somebody to plan with is one tidy row: what it is, what to
            // do, and a tap to the Daily 5. It was a sentence with a link
            // squeezed beside it.
            if candidates.isEmpty {
                Button(action: onOpenDaily) {
                    HStack(spacing: ArchSpacing.s) {
                        Image(systemName: "person.2")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(ArchColor.mortar)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Plan with someone")
                                .archText(.subhead)
                                .foregroundStyle(ArchColor.limestone)
                            Text("Write to one of your matches first.")
                                .archText(.footnote)
                                .foregroundStyle(ArchColor.mortar)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ArchColor.mortar)
                    }
                    .padding(.horizontal, ArchSpacing.m)
                    .padding(.vertical, ArchSpacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                            .fill(ArchColor.stone)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.99))
                .accessibilityHint("Opens your Daily 5")
                .accessibilityIdentifier("planner.seeMatches")
            }
        }
        .padding(.bottom, ArchSpacing.l)
    }

    /// "Self plan": a date with yourself, last in the row. Your own profile
    /// photo -- the first of yours, as the You tab shows it -- because it is
    /// you it is planned for.
    private var selfPlanButton: some View {
        Button {
            switchPlanning(to: Self.selfPlanID)
        } label: {
            VStack(spacing: ArchSpacing.xs) {
                PhotoPlaceholder(toneIndex: you.avatarToneIndex,
                                 url: you.mainPhoto?.url,
                                 data: you.mainPhoto?.local)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: ArchRadius.control,
                                                style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ArchRadius.control + 3,
                                         style: .continuous)
                            .stroke(ArchColor.limestone, lineWidth: isSolo ? 2 : 0)
                            .padding(-3)
                    }
                Text("Self plan")
                    .archText(.caption)
                    .foregroundStyle(isSolo ? ArchColor.limestone : ArchColor.mortar)
                if confirmedSelfPlan != nil {
                    Text("Confirmed")
                        .archText(.caption)
                        .foregroundStyle(ArchColor.lamp)
                        .padding(.top, -ArchSpacing.xxs)
                }
            }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(confirmedSelfPlan != nil ? "Self plan, confirmed" : "Self plan")
        .accessibilityHint("Plans a date for you on your own")
        .accessibilityAddTraits(isSolo ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("planner.with.self")
    }

    /// **The settings, in one row**: the day (a calendar), the time of day,
    /// and your answers. Each is a tap; none is a section of its own.
    ///
    /// The day is a button rather than the system's compact date picker,
    /// because the app draws its own controls and a stock grey capsule would be
    /// the only one on the screen; the calendar it opens is the system's, which
    /// is the one people already know how to use. The time of day is two
    /// buttons rather than a segmented control, for the same reason.
    private func settingsRow(_ time: DatePlan.TimeOfDay) -> some View {
        HStack(spacing: ArchSpacing.xs) {
            Button { choosingDate = true } label: {
                Text(day.map { $0 == PlanDay.earliest() ? "Tomorrow" : $0.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
                     ?? "Pick a day")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.limestone)
                    .lineLimit(1)
                    .padding(.horizontal, ArchSpacing.s)
                    .frame(height: 36)
                    .background(Capsule().fill(ArchColor.stone))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .accessibilityLabel("Date, \(day?.long ?? "not chosen")")
            .accessibilityHint("Opens a calendar")
            .accessibilityIdentifier("planner.date")

            HStack(spacing: 0) {
                ForEach(DatePlan.TimeOfDay.allCases) { option in
                    let isOn = option == time
                    Button {
                        guard pickedTime != option else { return }
                        pickedTime = option
                        restartSwaps()
                    } label: {
                        Text(option.title)
                            .archText(.footnote)
                            .foregroundStyle(isOn ? ArchColor.limestone : ArchColor.mortar)
                            .lineLimit(1)
                            .padding(.horizontal, ArchSpacing.s)
                            .frame(height: 30)
                            .background(Capsule().fill(isOn ? ArchColor.stoneRaised : Color.clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(3)
            .background(Capsule().fill(ArchColor.stone))

            Spacer(minLength: 0)

            // Your answers: the line that used to sit on the screen, in a
            // sheet, with the way back into the questions.
            Button { showingPreferences = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ArchColor.limestone)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(ArchColor.stone))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.95))
            .accessibilityLabel("Your date preferences")
            .accessibilityIdentifier("planner.editPreferences")
        }
        .padding(.bottom, ArchSpacing.s)
        .sheet(isPresented: $choosingDate) {
            PlanDatePicker(
                selection: Binding(
                    get: { day ?? PlanDay.earliest() },
                    set: { day in
                        pickedDay = day
                        restartSwaps()
                    }
                ),
                onDone: { choosingDate = false }
            )
        }
        .sheet(isPresented: $showingPreferences, onDismiss: {
            saveSheetMiles()
            sheetMiles = nil
        }) { preferencesSheet }
    }

    /// Your answers, and the way back into the questions. Only ever yours:
    /// the other person's shape the plan and are never shown.
    private var preferencesSheet: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Your date preferences")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.xl)
            if let preferences = you.datePreferences {
                Text(preferences.summary(includingDistance: false))
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
                Text("How far you would travel")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                    .padding(.top, ArchSpacing.s)
                DistanceChooser(miles: Binding(get: { sheetMiles ?? preferences.miles },
                                               set: { sheetMiles = $0 }),
                                centre: you.matchPoint)
            }
            Text("They shape every plan. Nobody else sees them.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
            ArchButton(title: "Change your answers", kind: .quiet) {
                showingPreferences = false
                startAsking()
            }
            .accessibilityIdentifier("planner.changeAnswers")
            .padding(.top, ArchSpacing.s)
            ArchTextButton(title: "Done") { showingPreferences = false }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .archSheetBackground()
        // Saved a moment after the slider stops, not at every mile it passes;
        // the plan behind the sheet follows.
        .task(id: sheetMiles) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            saveSheetMiles()
        }
    }

    /// The distance from the preferences sheet, as your answer -- `distance`
    /// beside it for builds from before the slider.
    private func saveSheetMiles() {
        guard let miles = sheetMiles, var preferences = you.datePreferences,
              miles != preferences.miles else { return }
        preferences.reachMiles = miles
        preferences.distance = miles <= 1 ? .walkable : .ride
        onSavePreferences(preferences)
    }

    /// **What the plan is built on, in one line**: what you share -- or, on a
    /// self plan, what you like -- and where. "You both like being outside ·
    /// near Prospect Heights".
    private func basisLine(_ plan: DatePlan) -> some View {
        let phrases = plan.shared.map(\.phrase)
        let joined = phrases.count > 1
            ? phrases.dropLast().joined(separator: ", ") + " and " + (phrases.last ?? "")
            : (phrases.first ?? "")
        var parts: [String] = []
        if isSolo {
            parts.append(phrases.isEmpty ? "Leaning on your date preferences" : "You like \(joined)")
        } else {
            parts.append(phrases.isEmpty ? "Leaning on what \(chosen?.person.name ?? "they") wrote" : "You both like \(joined)")
        }
        if !plan.sameWords.isEmpty {
            parts.append("you both wrote \(plan.sameWords.map { "\u{201C}\($0)\u{201D}" }.joined(separator: " and "))")
        }
        if let halfway = plan.halfway {
            parts.append(isSolo ? "around \(halfway)" : "near \(halfway)")
        }
        return VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
            Text(parts.joined(separator: " \u{00B7} "))
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("planner.basis")
            // Your distance, never theirs: the plan simply stays inside both.
            // It opens your preferences, where its slider is.
            if let miles = you.datePreferences?.miles {
                Button { showingPreferences = true } label: {
                    Text("Up to \(miles) mi from you")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.lamp)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
                .accessibilityLabel("Up to \(miles) miles from you")
                .accessibilityHint("Change how far you would travel")
                .accessibilityIdentifier("planner.distance")
            }
        }
        .padding(.bottom, ArchSpacing.l)
    }

    /// Two cases, said differently: your distances do not overlap at all, or
    /// they do but nothing fits where they meet. Neither stops the plan, or
    /// Share.
    @ViewBuilder private func distanceNote(_ plan: DatePlan) -> some View {
        if plan.apart {
            Text("Your distances do not overlap, so this plan is about halfway between you. You can still send it.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)
                .padding(ArchSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                        .fill(ArchColor.stone)
                )
                .padding(.bottom, ArchSpacing.m)
                .accessibilityIdentifier("planner.apart")
        } else if plan.stretched {
            Text("Nothing fits that close, so this plan goes a little further.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, ArchSpacing.m)
                .accessibilityIdentifier("planner.stretched")
        }
    }

    /// What you have added, in order: each item the planner found a place for
    /// as its stop, a blank one as the choice of what it should be, and under
    /// them the way to add another.
    private func itinerary(_ plan: DatePlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if let stop = plan.stops.first(where: { $0.itemID == item.id }) {
                    if let travel = stop.travel {
                        travelLine(travel)
                    } else if index > 0 {
                        Color.clear.frame(height: ArchSpacing.s)
                    }
                    stopCard(stop, index: index, in: plan)
                } else {
                    if index > 0 { Color.clear.frame(height: ArchSpacing.s) }
                    if let category = item.category {
                        nothingFits(category, index: index)
                    } else {
                        blankCard(index: index)
                    }
                }
            }
            addRow
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planner.itinerary")
        .sheet(isPresented: Binding(get: { customFor != nil }, set: { if !$0 { customFor = nil } })) {
            CustomSpotSheet(
                isLive: isLive,
                near: you.matchPoint,
                library: venues,
                onPick: { venue in
                    if let id = customFor { addCustom(venue, to: id) }
                    customFor = nil
                },
                onCancel: { customFor = nil }
            )
        }
    }

    /// An item added and not yet told what it is.
    private func blankCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            HStack(alignment: .center, spacing: ArchSpacing.s) {
                Text(index == 0 ? "What should the date start with?" : "What next?")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                Spacer(minLength: 0)
                // Remove, as the icon Saved plans deletes with: on the item,
                // where Swap sits on a filled one, rather than a word under the
                // choices. Not on the only item. The negative padding keeps the
                // row the height of its words, so the card is the same height
                // with the icon as without.
                if items.count > 1 {
                    Button { withAnimation(ArchMotion.standard) { remove(index) } } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ArchColor.mortar)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.9))
                    .padding(.vertical, -6)
                    .accessibilityLabel("Remove this item")
                    .accessibilityIdentifier("planner.blankRemove.\(index)")
                }
            }
            HStack(spacing: ArchSpacing.xs) {
                ForEach(DatePlan.Category.allCases) { category in
                    Button { withAnimation(ArchMotion.standard) { fill(index, with: category) } } label: {
                        Text(category.title)
                            .archText(.subhead)
                            .foregroundStyle(ArchColor.limestone)
                            .frame(maxWidth: .infinity)
                            .frame(height: ArchSpacing.minimumTapTarget)
                            .background(
                                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                                    .fill(ArchColor.stoneRaised)
                            )
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.99))
                    .accessibilityIdentifier("planner.choose.\(category.rawValue)")
                }
            }
            // Food & drink or Activity, chosen by the planner -- or a place
            // you name yourself, where "Surprise me" used to be, centred under
            // the two.
            ArchTextButton(title: "Custom spot") {
                if items.indices.contains(index) { customFor = items[index].id }
            }
            .accessibilityHint("Search for a place and add it to the date")
            .accessibilityIdentifier("planner.choose.custom")
        }
        .padding(ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .strokeBorder(ArchColor.quietBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planner.blank")
    }

    /// An item the planner could find nowhere for: every place of that kind is
    /// shut that day, or ruled out by what one of you said.
    private func nothingFits(_ category: DatePlan.Category, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Nowhere fits for \(category.title.lowercased()) here, open at that time on this day.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ArchSpacing.s)
            ArchTextButton(title: "Remove") { withAnimation(ArchMotion.standard) { remove(index) } }
        }
        .padding(ArchSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(ArchColor.stone)
        )
    }

    /// Another item, while there is room. Hidden while a blank one is waiting
    /// to be chosen.
    @ViewBuilder
    private var addRow: some View {
        // At three it simply is not offered.
        if !items.contains(where: { $0.category == nil }), items.count < PlanItem.maximum {
            ArchButton(title: "Add to the date", kind: .quiet) {
                withAnimation(ArchMotion.standard) { add() }
            }
            .accessibilityIdentifier("planner.addItem")
            .padding(.top, ArchSpacing.m)
        }
    }

    /// **A stop, in two lines until you open it**: when, where, what kind,
    /// how long -- with Swap on the outside. Opened, it adds why it was
    /// chosen, its hours, the length, and Maps, Not for us and Remove. Two
    /// things show closed because they matter at a glance: a place kept from a
    /// plan that was sent ("From Hana's plan."), and hours that run out before
    /// the stop does.
    private func stopCard(_ stop: DatePlan.Stop, index: Int, in plan: DatePlan) -> some View {
        let isOpen = openStops.contains(stop.itemID)
        let kept = items.indices.contains(index) && items[index].pinned?.id == stop.venue.id
        let toggle = {
            withAnimation(ArchMotion.standard) {
                if isOpen { openStops.remove(stop.itemID) } else { openStops.insert(stop.itemID) }
            }
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: ArchSpacing.s) {
                Text(DatePlanner.clockTime(stop.start))
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                    .frame(width: 64, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.venue.name)
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(stop.venue.kind.label) \u{00B7} \(stop.venue.neighbourhood) \u{00B7} \(stop.minutes / 60) hr")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                    if kept {
                        Text(stop.reason)
                            .archText(.caption)
                            .foregroundStyle(ArchColor.lamp)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // A guess shown as a fact is how two people end up at a
                    // locked door: when the hours run out, it says so closed.
                    if !stop.isOpenThroughout {
                        Text(hoursLine(stop))
                            .archText(.caption)
                            .foregroundStyle(ArchColor.limestone)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                // Only where there is somewhere else to go. A Swap that lands on
                // the same place looks like a button that does not work.
                if stop.canSwap {
                    Button { swap(index, from: stop.venue) } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(ArchColor.mortar)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.9))
                    .accessibilityLabel("Swap \(stop.venue.name)")
                }
                Button(action: toggle) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ArchColor.mortar)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .frame(width: 28, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.9))
                .accessibilityLabel(isOpen ? "Hide details for \(stop.venue.name)" : "Show details for \(stop.venue.name)")
                .accessibilityIdentifier("planner.open.\(index)")
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)

            // Right after a Swap, the way back -- on the stop it changed.
            if let last = lastSwap, last.itemID == stop.itemID {
                HStack(alignment: .firstTextBaseline) {
                    Text("Swapped from \(last.name).")
                        .archText(.caption)
                        .foregroundStyle(ArchColor.mortar)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: ArchSpacing.s)
                    // An arrow rather than the word: it sits beside Swap's own
                    // arrow, and reads as "back" at a glance.
                    Button {
                        withAnimation(ArchMotion.standard) { undoSwap() }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(ArchColor.limestone)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.9))
                    .accessibilityLabel("Undo swap, back to \(last.name)")
                    .accessibilityIdentifier("planner.undoSwap")
                }
                .padding(.leading, 64 + ArchSpacing.s)
                // Stops short of the open/close arrow, so Undo sits exactly
                // under Swap: same width, same column.
                .padding(.trailing, 28 + ArchSpacing.s)
                .padding(.top, ArchSpacing.xxs)
            }

            if isOpen {
                VStack(alignment: .leading, spacing: ArchSpacing.xs) {
                    Rectangle().fill(ArchColor.quietBorder).frame(height: 1)
                    if !kept {
                        Text(stop.reason)
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.limestone)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if stop.isOpenThroughout {
                        Text(hoursLine(stop))
                            .archText(.caption)
                            .foregroundStyle(ArchColor.mortar)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Photos and reviews: Google's page for the place, over the
                    // planner (`VenueSearch.googleURL`).
                    if let google = VenueSearch.googleURL(for: stop.venue) {
                        Button { browsing = BrowserPage(url: google) } label: {
                            HStack(spacing: 4) {
                                Text("Photos and reviews on Google")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .archText(.caption)
                            .foregroundStyle(ArchColor.lamp)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.97))
                        .accessibilityLabel("Photos and reviews of \(stop.venue.name) on Google")
                        .accessibilityIdentifier("planner.google.\(index)")
                    }
                    if !stop.canSwap {
                        Text(onlyFit(stop, in: plan))
                            .archText(.caption)
                            .foregroundStyle(ArchColor.mortar)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // How long: one, two or three hours. Everything after it
                    // moves. Labelled, so the buttons say what they set.
                    HStack(spacing: ArchSpacing.xxs) {
                        Text("Duration")
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.mortar)
                            .frame(minWidth: 64, alignment: .leading)
                            .padding(.trailing, ArchSpacing.xxs)
                        ForEach(PlanItem.hourChoices, id: \.self) { hours in
                            let isOn = items.indices.contains(index) && items[index].hours == hours
                            Button {
                                if items.indices.contains(index) { items[index].hours = hours }
                                sentTo = nil
                            } label: {
                                Text("\(hours) hr")
                                    .archText(.footnote)
                                    .foregroundStyle(isOn ? ArchColor.limestone : ArchColor.mortar)
                                    .frame(width: 48, height: 32)
                                    .background(
                                        RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                                            .fill(isOn ? ArchColor.stoneRaised : ArchColor.night)
                                    )
                            }
                            .buttonStyle(PressScaleStyle(scale: 0.97))
                            .accessibilityLabel(hours == 1 ? "One hour" : "\(hours) hours")
                            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                            .accessibilityIdentifier("planner.hours.\(index).\(hours)")
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, ArchSpacing.xxs)

                    // What to do about the place: look it up, never again, or
                    // not in this plan -- spread edge to edge, Maps under the
                    // name and Remove at the right, the gaps between them even.
                    HStack(spacing: 0) {
                        if stop.venue.mapsURL != nil {
                            // The place on a map, in the app; Apple Maps is a
                            // tap further, from there.
                            ArchTextButton(title: "Maps") { mapping = stop.venue }
                                .fixedSize()
                                .accessibilityLabel("Show \(stop.venue.name) on a map")
                                .accessibilityIdentifier("planner.maps.\(index)")
                            Spacer(minLength: ArchSpacing.s)
                        }
                        // Not this place, ever: for the corner Apple Maps calls
                        // a park. Remove is for the item; this is for the place.
                        ArchTextButton(title: "Not for us") {
                            withAnimation(ArchMotion.standard) { hide(stop.venue, at: index) }
                        }
                        .fixedSize()
                        .accessibilityLabel("Never suggest \(stop.venue.name)")
                        .accessibilityIdentifier("planner.hide.\(index)")
                        Spacer(minLength: ArchSpacing.s)
                        ArchTextButton(title: "Remove") { withAnimation(ArchMotion.standard) { remove(index) } }
                            .fixedSize()
                            .accessibilityLabel("Remove \(stop.venue.name)")
                            .accessibilityIdentifier("planner.remove.\(index)")
                    }
                }
                .padding(.leading, 64 + ArchSpacing.s)
                .padding(.top, ArchSpacing.s)
            }
        }
        .padding(ArchSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(ArchColor.stone)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planner.stop")
    }

    /// "Open 11:00 am – 6:00 pm", "Usually open …", or, when getting there
    /// took longer than the planner allowed for, that it may be closing.
    private func hoursLine(_ stop: DatePlan.Stop) -> String {
        let hours = stop.venue.openingHours
        guard stop.isOpenThroughout else {
            return "Closes at \(DatePlanner.clockTime(hours.closes)), before this ends. Swap it or shorten the time."
        }
        return (hours.isTypical ? "Usually open " : "Open ") + hours.label
    }

    /// Why a stop has no Swap: it is the only place that fits.
    private func onlyFit(_ stop: DatePlan.Stop, in plan: DatePlan) -> String {
        guard !stop.isAnchor, let near = stop.placedNear,
              let anchor = plan.stops.first(where: \.isAnchor) else {
            return "The only place that fits what you both said."
        }
        return "The only place near \(near) that fits. Swap \(anchor.venue.name) to move the whole date."
    }

    /// Getting between two stops, drawn as the gap it is.
    private func travelLine(_ travel: DatePlan.Travel) -> some View {
        HStack(spacing: ArchSpacing.s) {
            Rectangle()
                .fill(ArchColor.quietBorder)
                .frame(width: 2, height: 28)
                .padding(.leading, 32)
            Text(travel.label)
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
        }
        .padding(.vertical, ArchSpacing.xxs)
    }

    /// **The rest of the facts in one line** -- when it is done, how far the
    /// first stop is -- with the finer print a tap away.
    private func facts(_ plan: DatePlan) -> some View {
        var line = ["Done about \(DatePlanner.clockTime(plan.endsAt))"]
        if let km = plan.fromYou { line.append(String(format: "%.1f km from you", km)) }
        return VStack(spacing: ArchSpacing.xs) {
            HStack(spacing: ArchSpacing.xxs) {
                Text(line.joined(separator: " \u{00B7} ") + " \u{00B7}")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                Button {
                    withAnimation(ArchMotion.standard) { showingDetails.toggle() }
                } label: {
                    Text(showingDetails ? "Less" : "Details")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.lamp)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("planner.details")
            }
            if showingDetails {
                Text(fineprint(plan))
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, ArchSpacing.l)
    }

    /// The day, whether it is fair, and -- in a real build -- that the hours
    /// are what places like these usually keep.
    private func fineprint(_ plan: DatePlan) -> String {
        var parts: [String] = []
        if let day = plan.day { parts.append("\(day.long), \(plan.time.title.lowercased()).") }
        if let fairness = plan.fairness { parts.append(fairness) }
        // Apple Maps does not give an app opening hours, so the plan cannot
        // know them. Better said than discovered at a locked door.
        if isLive {
            parts.append("Places are from Apple Maps, which does not share opening hours, so the hours shown are what places like these usually keep. Check before you go.")
        }
        return parts.joined(separator: " ")
    }

    /// Pinned at the bottom: Share this plan -- or, on a self plan, Confirm --
    /// and the line about what happened.
    ///
    /// **"Share this plan" shares only into Messages.** It opens the people you
    /// are talking to, the one you planned with first, and sends into the
    /// conversation you pick. A self plan has nobody to share it with; once
    /// confirmed, Export sends it anywhere you like.
    @ViewBuilder
    private func bottomBar(_ plan: DatePlan) -> some View {
        VStack(spacing: ArchSpacing.xs) {
            if let chosen {
                ArchButton(title: "Share this plan") { sharing = plan }
                saveLine(plan)
                if let sentTo {
                    Text("Sent to \(sentTo). It is in your conversation.")
                        .archText(.caption)
                        .foregroundStyle(ArchColor.mortar)
                }
                Color.clear.frame(height: 0)
                    .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
                        ShareWithSheet(
                            candidates: candidates,
                            plannedWith: chosen.id,
                            onPick: { picked in
                                if let sharing {
                                    share(sharing, to: picked, plannedWith: chosen.person)
                                }
                                self.sharing = nil
                            },
                            onCancel: { sharing = nil }
                        )
                    }
            } else {
                ArchButton(title: changingSelf ? "Confirm the changes" : "Confirm this plan") {
                    withAnimation(ArchMotion.standard) { confirmSelf(plan) }
                }
                .accessibilityIdentifier("planner.self.confirm")
                saveLine(plan)
            }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.top, ArchSpacing.s)
        .padding(.bottom, ArchSpacing.s)
        .frame(maxWidth: .infinity)
        .background(ArchColor.night)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planner.bottomBar")
        .alert(
            repeatShare.map { r in
                r.settled ? "\(r.candidate.person.name) already said yes to this plan"
                          : "You already sent this plan to \(r.candidate.person.name)"
            } ?? "",
            isPresented: Binding(get: { repeatShare != nil }, set: { if !$0 { repeatShare = nil } }),
            presenting: repeatShare
        ) { repeated in
            if repeated.settled {
                Button("Confirm", role: .cancel) {}
            } else {
                Button("Send it again") { resend(repeated) }
                Button("Cancel", role: .cancel) {}
            }
        } message: { repeated in
            Text(repeated.settled
                 ? "It\u{2019}s in your conversation. Change something to send a new plan."
                 : "The earlier one is removed, so only this one shows.")
        }
    }

    // MARK: Saved plans

    /// A plan kept for later: who it is with, and the plan as it was.
    struct SavedDatePlan: Codable, Identifiable, Hashable {
        let id: String
        /// Whose phone-side list it is in.
        let owner: String
        /// The match's id, or the self plan's.
        let withID: String
        let name: String
        let plan: SharedPlan
        let savedAt: Date
        /// The same plan however it was reached: who, when, and the places.
        let key: String
    }

    /// Saved plans you can keep: ten, or fifteen with Arch Premium.
    static let savedLimitFree = 10
    static let savedLimitPremium = 15
    private var savedLimit: Int { isPremium ? Self.savedLimitPremium : Self.savedLimitFree }

    private var savedFullMessage: String {
        let count = savedPlans.count
        if count > savedLimit {
            return "You have \(count) saved plans and can keep \(savedLimit). Delete \(count - savedLimit + 1) to save this one."
        }
        return isPremium
            ? "You can keep \(savedLimit) saved plans. Delete one to save this."
            : "You can keep \(savedLimit) saved plans, or \(Self.savedLimitPremium) with Arch Premium. Delete one to save this."
    }

    /// Yours, newest first.
    private var savedPlans: [SavedDatePlan] {
        allSavedPlans.filter { $0.owner == you.id }.sorted { $0.savedAt > $1.savedAt }
    }

    private var allSavedPlans: [SavedDatePlan] {
        guard let data = savedPlansJSON.data(using: .utf8),
              let plans = try? JSONDecoder().decode([SavedDatePlan].self, from: data) else { return [] }
        return plans
    }

    private func storeSavedPlans(_ plans: [SavedDatePlan]) {
        guard let data = try? JSONEncoder().encode(plans),
              let json = String(data: data, encoding: .utf8) else { return }
        savedPlansJSON = json
    }

    /// The plan on screen, frozen for keeping: with the reasons, since it is
    /// only ever yours.
    private func frozen(_ plan: DatePlan) -> SharedPlan {
        let other = chosen?.person ?? you
        return SharedPlan(plan, sharedWith: other, plannedWith: other)
    }

    private func savedKey(_ plan: SharedPlan) -> String {
        [planningID, plan.time ?? "", plan.day ?? "",
         (plan.stops ?? []).map { $0.placeID ?? $0.name }.joined(separator: ",")]
            .joined(separator: "|")
    }

    /// "Thursday evening with Hana", "Monday afternoon, just you".
    private func savedTitle(_ saved: SavedDatePlan) -> String {
        let part = saved.plan.timeOfDay == .evening ? "evening" : "afternoon"
        let when = saved.plan.planDay.map { "\($0.weekdayName) \(part)" } ?? "An \(part)"
        return saved.withID == Self.selfPlanID ? "\(when), just you" : "\(when) with \(saved.name)"
    }

    /// Save the plan on screen, or unsave it if it is already kept.
    private func toggleSave(_ plan: DatePlan) {
        let shared = frozen(plan)
        let key = savedKey(shared)
        if savedPlans.contains(where: { $0.key == key }) {
            unsave(key)
            return
        }
        // Full: ask to make room rather than drop the oldest. A plan you
        // kept stays until you delete it, even past the limit after Premium.
        guard savedPlans.count < savedLimit else {
            savedFull = true
            return
        }
        let saved = SavedDatePlan(id: UUID().uuidString, owner: you.id, withID: planningID,
                                  name: chosen?.person.name ?? you.name, plan: shared,
                                  savedAt: .now, key: key)
        storeSavedPlans(allSavedPlans + [saved])
    }

    private func unsave(_ key: String) {
        storeSavedPlans(allSavedPlans.filter { !($0.owner == you.id && $0.key == key) })
    }

    /// Back into the planner, on that person, with its places kept.
    private func open(_ saved: SavedDatePlan) {
        if saved.withID != planningID { keepSession() }
        chosenID = saved.withID
        items = saved.plan.planItems(from: "From your saved plan.") ?? [PlanItem()]
        pickedTime = saved.plan.timeOfDay
        pickedDay = saved.plan.planDay
        changingAgreed = nil
        changingSelf = false
        lastSwap = nil
        replanned = nil
        sentTo = nil
    }

    /// **Save, under the main button, quietly.** A line that says what it
    /// does; once saved, the bookmark fills and it says so. Tap again to
    /// unsave. Change the plan and it is a different plan, not saved.
    private func saveLine(_ plan: DatePlan) -> some View {
        let isSaved = savedPlans.contains { $0.key == savedKey(frozen(plan)) }
        return Button {
            withAnimation(ArchMotion.quick) { toggleSave(plan) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 14, weight: .semibold))
                Text(isSaved ? "Saved" : "Save for later")
                    .archText(.footnote)
            }
            .foregroundStyle(isSaved ? ArchColor.lamp : ArchColor.mortar)
            .frame(height: 32)
            .padding(.horizontal, ArchSpacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityLabel(isSaved ? "Saved. Tap to remove" : "Save this plan for later")
        .accessibilityAddTraits(isSaved ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("planner.save")
        .alert("Your saved plans are full", isPresented: $savedFull) {
            Button("See saved plans") { showingSaved = true }
            if !isPremium {
                Button("See Arch Premium") { onOpenPremium() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(savedFullMessage)
        }
    }

    // MARK: Sending the same plan twice

    /// Shares a plan -- unless the very same plan, every field of it, is
    /// already in that conversation from you. Then it asks first.
    private func share(_ plan: DatePlan, to picked: PlannerCandidate, plannedWith: Person) {
        let text = DatePlanner.message(for: plan)
        let shared = SharedPlan(plan, sharedWith: picked.person, plannedWith: plannedWith)
        let messages = picked.conversation.messages
        let earlier = messages.filter { $0.isOutgoing && $0.plan == shared }
        guard !earlier.isEmpty else {
            onSend(picked.conversation, text, shared)
            sentTo = picked.person.name
            return
        }
        let settled = earlier.contains { copy in
            messages.contains { $0.plan?.answering == copy.id || $0.plan?.cancelling == copy.id }
        }
        // After the share sheet has gone, so the two do not collide.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            repeatShare = RepeatShare(candidate: picked, text: text, plan: shared,
                                      earlier: earlier.map(\.id), settled: settled)
        }
    }

    /// "Send it again": the earlier copies go, and this one is sent -- so the
    /// conversation shows the plan once, as the newest message.
    private func resend(_ repeated: RepeatShare) {
        for id in repeated.earlier {
            onUnsend(repeated.candidate.conversation, id)
        }
        onSend(repeated.candidate.conversation, repeated.text, repeated.plan)
        sentTo = repeated.candidate.person.name
    }

    /// While Apple Maps is asked, and if it could not be.
    @ViewBuilder
    private func looking(for id: String) -> some View {
        if unreachable.contains(id) {
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text("Arch could not reach Apple Maps just now.")
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
                Text("It is where the places in a plan come from, so planning needs a connection.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
                ArchButton(title: "Try again", kind: .quiet) { attempt += 1 }
                    .padding(.top, ArchSpacing.xs)
            }
        } else {
            Text(isSolo ? "Finding places near you\u{2026}" : "Finding places near you both\u{2026}")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
        }
    }

    /// Apple Maps answered, and there was nowhere to put a plan.
    private var nowhereNearby: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Nowhere to plan around yet")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
            Text(isSolo ? "Apple Maps found no caf\u{00E9}s, parks or restaurants near you."
                        : "Apple Maps found no caf\u{00E9}s, parks or restaurants near the point halfway between you.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Nobody to plan with yet")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
            Text("Plans are for people you are talking to. Write to one of your matches, and you can plan a date with them here.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
            ArchButton(title: "See your matches", kind: .quiet, action: onOpenDaily)
                .padding(.top, ArchSpacing.s)
        }
    }
}

/// Plans saved for later: who each is with, when, and its stops. Open puts it
/// back in the planner with its places kept; the cross deletes it. A plan
/// with somebody no longer in Messages can be deleted and not opened.
struct SavedPlansSheet: View {
    let plans: [DatePlannerView.SavedDatePlan]
    let person: (String) -> Person?
    let title: (DatePlannerView.SavedDatePlan) -> String
    let onOpen: (DatePlannerView.SavedDatePlan) -> Void
    let onDelete: (DatePlannerView.SavedDatePlan) -> Void
    let onClose: () -> Void
    /// How many you can keep, and with Premium.
    var limit: Int = DatePlannerView.savedLimitFree
    var premiumLimit: Int = DatePlannerView.savedLimitPremium
    var isPremium: Bool = false
    var onOpenPremium: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Saved plans")
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                Spacer(minLength: 0)
                ArchTextButton(title: "Done", action: onClose)
                    .fixedSize()
            }
            .padding(.top, ArchSpacing.xl)
            .padding(.bottom, ArchSpacing.m)

            if plans.isEmpty {
                Text("Nothing saved yet")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                Text("Tap \u{201C}Save for later\u{201D} under Share to keep a plan.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .padding(.top, ArchSpacing.xxs)
                Text(isPremium ? "You can keep \(limit)." : "You can keep \(limit), or \(premiumLimit) with Arch Premium.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .padding(.top, ArchSpacing.xxs)
                Spacer(minLength: 0)
            } else {
                countLine
                    .padding(.bottom, ArchSpacing.s)
                ScrollView {
                    VStack(spacing: ArchSpacing.s) {
                        ForEach(plans) { saved in card(saved) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .archSheetBackground()
    }

    /// How many, against how many you can keep. Over it -- Premium ended --
    /// says how many to delete; nothing is ever deleted for you.
    private var countLine: some View {
        let count = plans.count
        let words = count > limit
            ? "\(count) saved, and you can keep \(limit). Delete \(count - limit + 1) to save another."
            : count == limit
                ? "\(count) of \(limit) saved. Delete one to save another."
                : "\(count) of \(limit) saved."
        return VStack(alignment: .leading, spacing: 2) {
            Text(words)
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .accessibilityIdentifier("planner.savedCount")
            if !isPremium {
                Button(action: onOpenPremium) {
                    Text("Keep \(premiumLimit) with Arch Premium")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.lamp)
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
            }
        }
    }

    private func card(_ saved: DatePlannerView.SavedDatePlan) -> some View {
        let who = person(saved.withID)
        return VStack(alignment: .leading, spacing: ArchSpacing.s) {
            HStack(spacing: ArchSpacing.s) {
                PhotoPlaceholder(toneIndex: who?.avatarToneIndex ?? 0,
                                 url: who?.mainPhoto?.url, data: who?.mainPhoto?.local)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(saved))
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                    if let day = saved.plan.planDay {
                        Text(day.long)
                            .archText(.caption)
                            .foregroundStyle(ArchColor.mortar)
                    }
                }
                Spacer(minLength: 0)
                Button { onDelete(saved) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ArchColor.mortar)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.9))
                .accessibilityLabel("Delete this saved plan")
                .accessibilityIdentifier("planner.savedDelete")
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array((saved.plan.stops ?? []).enumerated()), id: \.offset) { _, stop in
                    HStack(spacing: ArchSpacing.s) {
                        Text(DatePlanner.clockTime(stop.start))
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.mortar)
                            .frame(width: 64, alignment: .leading)
                        Text(stop.name)
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.limestone)
                    }
                }
            }
            if who == nil {
                Text("No longer in Messages.")
                    .archText(.caption)
                    .foregroundStyle(ArchColor.mortar)
            } else {
                ArchButton(title: "Open in the planner", kind: .quiet) { onOpen(saved) }
                    .accessibilityIdentifier("planner.savedOpen")
            }
        }
        .padding(ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(ArchColor.stone)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planner.savedCard")
    }
}

/// Who a plan can be shared with: the people in Messages, and nobody else.
///
/// The person you planned with is first and says so; anyone else you are talking
/// to is below. One tap sends -- the plan is already written, and a second
/// confirmation would be a step between deciding and doing that adds nothing.
struct ShareWithSheet: View {
    let candidates: [PlannerCandidate]
    let plannedWith: String
    let onPick: (PlannerCandidate) -> Void
    let onCancel: () -> Void

    private var ordered: [PlannerCandidate] {
        candidates.filter { $0.id == plannedWith } + candidates.filter { $0.id != plannedWith }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Share this plan")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.xl)
            Text("Only with people you are talking to. It goes into your conversation.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.xs)
                .padding(.bottom, ArchSpacing.m)

            ScrollView {
                VStack(spacing: ArchSpacing.xs) {
                    ForEach(ordered) { candidate in
                        Button { onPick(candidate) } label: {
                            HStack(spacing: ArchSpacing.s) {
                                PhotoPlaceholder(toneIndex: candidate.person.avatarToneIndex,
                                                 url: candidate.person.mainPhoto?.url,
                                                 data: candidate.person.mainPhoto?.local)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: ArchRadius.control,
                                                                style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.person.name)
                                        .archText(.subhead)
                                        .foregroundStyle(ArchColor.limestone)
                                    if candidate.id == plannedWith {
                                        Text("You planned this with them")
                                            .archText(.footnote)
                                            .foregroundStyle(ArchColor.mortar)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(ArchSpacing.s)
                            .background(
                                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                                    .fill(ArchColor.stone)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.99))
                        .accessibilityLabel("Share with \(candidate.person.name)")
                    }
                }
            }
            .scrollIndicators(.hidden)

            ArchTextButton(title: "Cancel", action: onCancel)
                .padding(.top, ArchSpacing.xs)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .archSheetBackground()
    }
}

/// Choosing the day of the date: the system calendar, from tomorrow to three
/// months ahead, in the app's accent. The choice takes effect as it is made,
/// so the plan behind the sheet is already for the new day when it closes.
struct PlanDatePicker: View {
    @Binding var selection: PlanDay
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            Text("When is the date?")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.xl)

            DatePicker(
                "Date",
                selection: Binding(
                    get: { selection.date },
                    set: { selection = PlanDay($0) }
                ),
                in: PlanDay.earliest().date...PlanDay.latest().date,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(ArchColor.lamp)
            .accessibilityIdentifier("planner.calendar")

            ArchButton(title: "Done", action: onDone)
                .accessibilityIdentifier("planner.dateDone")
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .archSheetBackground()
    }
}

#Preview("Date planner") {
    DatePlannerView(
        you: {
            var you = MockData.you
            you.datePreferences = DatePreferences(style: .doing, timeOfDay: .either,
                                                  drinks: .sometimes, budget: .middle,
                                                  distance: .walkable)
            return you
        }(),
        candidates: MockData.conversations.map { PlannerCandidate(person: $0.person, conversation: $0) }
    )
    .preferredColorScheme(.dark)
}

#Preview("Get started") {
    DatePlannerView(you: MockData.you, candidates: [])
        .preferredColorScheme(.dark)
}

#Preview("Nobody yet") {
    DatePlannerView(
        you: {
            var you = MockData.you
            you.datePreferences = DatePreferences(style: .talk, timeOfDay: .afternoon,
                                                  drinks: .yes, budget: .any, distance: .ride)
            return you
        }(),
        candidates: []
    )
}
