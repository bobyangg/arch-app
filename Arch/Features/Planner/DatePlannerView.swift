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
    var onOpenDaily: () -> Void = {}
    /// Goes up when the popup after onboarding says "Get started": the planner
    /// opens straight onto the first question. A count, because it is an event.
    var startQuestions: Int = 0
    var onSavePreferences: (DatePreferences) -> Void = { _ in }

    @State private var chosenID: String?
    /// The time of day you chose with the toggle, or nil to use what your
    /// answers (and theirs) prefer. Picking another person goes back to nil.
    @State private var pickedTime: DatePlan.TimeOfDay?
    /// The day you chose, or nil for the first one offered (tomorrow).
    @State private var pickedDay: PlanDay?
    /// The question showing, while the questions are; nil otherwise.
    @State private var questionIndex: Int?
    @State private var draft: [Int?] = Array(repeating: nil, count: DatePreferences.questions.count)
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

    private var chosen: PlannerCandidate? {
        candidates.first { $0.id == chosenID } ?? candidates.first
    }

    /// The days on offer, worked out each time the screen is drawn so that a
    /// planner left open overnight moves on with the calendar.
    private var days: [PlanDay] { PlanDay.upcoming() }

    /// The day you picked, if it is still on offer; otherwise tomorrow.
    private var day: PlanDay? {
        if let pickedDay, days.contains(pickedDay) { return pickedDay }
        return days.first
    }

    /// What the rankings are built from that can change under you: your
    /// interests, and the interests of the person you are planning with.
    private struct PlanInputs: Equatable {
        let personID: String?
        let yours: [String]
        let theirs: [String]
    }

    private var inputs: PlanInputs {
        PlanInputs(personID: chosen?.id,
                   yours: you.interests.map(\.text),
                   theirs: chosen?.person.interests.map(\.text) ?? [])
    }

    /// The toggle's choice, or else the time your answers prefer.
    private func openingTime(with person: Person) -> DatePlan.TimeOfDay {
        pickedTime ?? DateFit(yours: you.datePreferences, theirs: person.datePreferences).time
    }

    var body: some View {
        TopBarScroll {
            VStack(alignment: .leading, spacing: 0) {
                masthead

                if questionIndex != nil {
                    DatePreferenceQuestions(index: $questionIndex, draft: $draft) { answers in
                        onSavePreferences(answers)
                        restartSwaps()
                        pickedTime = nil
                    }
                } else if you.datePreferences == nil {
                    PlannerGetStarted { startAsking() }
                } else if let chosen {
                    picker
                    if isLive && nearby[chosen.id] == nil {
                        looking(for: chosen)
                    } else {
                        // Apple Maps' places in a real build, the bundled ones
                        // in a design build. Everything after this line is the
                        // same either way.
                        let found = nearby[chosen.id]
                        let time = openingTime(with: chosen.person)
                        let plan = DatePlanner.plan(you: you, them: chosen.person, time: time,
                                                    day: day, venues: found?.venues ?? venues,
                                                    items: items,
                                                    theirCentre: found?.theirCentre,
                                                    halfwayName: found?.halfway)
                        if isLive && (found?.venues.isEmpty ?? true) {
                            preferencesRow
                            dayRow
                            timeToggle(time)
                            nowhereNearby
                        } else {
                            shared(plan, with: chosen.person)
                            preferencesRow
                            dayRow
                            timeToggle(time)
                            if let replanned {
                                Text(replanned)
                                    .archText(.footnote)
                                    .foregroundStyle(ArchColor.lamp)
                                    .padding(.bottom, ArchSpacing.s)
                                    .accessibilityIdentifier("planner.replanned")
                            }
                            itinerary(plan)
                            if !plan.stops.isEmpty {
                                footer(plan, with: chosen)
                            }
                        }
                    }
                } else {
                    preferencesRow
                    emptyState
                }
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.bottom, ArchSpacing.sectionGap)
        }
        .background(ArchColor.night)
        .task(id: "\(chosen?.id ?? "")#\(attempt)") { await findPlaces() }
        // Somebody else, another time or another day: the rankings underneath
        // have changed, so every item starts again from its best place. What
        // you added -- the kinds and the hours -- stays.
        .onChange(of: chosenID) { _, _ in
            restartSwaps()
            sentTo = nil
            replanned = nil
        }
        .onChange(of: pickedTime) { _, _ in
            restartSwaps()
            sentTo = nil
        }
        .onChange(of: pickedDay) { _, _ in
            restartSwaps()
            sentTo = nil
        }
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
            chosenID = preset.personID
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
    }

    /// Every item back to the best place in its ranking.
    private func restartSwaps() {
        items = items.map { item in
            var item = item
            item.skips = 0
            return item
        }
    }

    // MARK: Items

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
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        if items.isEmpty { items = [PlanItem()] }
        replanned = nil
        sentTo = nil
    }

    /// "Surprise me": an activity if there is none -- a date with nothing to
    /// do is a meal -- then something to eat if there is none, and after that
    /// the other kind from the item before it, so two dinners never sit
    /// back to back.
    private func surprise(for index: Int) -> DatePlan.Category {
        let kinds = items.compactMap(\.category)
        if !kinds.contains(.activity) { return .activity }
        if !kinds.contains(.food) { return .food }
        let before = items[..<min(index, items.count)].compactMap(\.category).last
        return before == .food ? .activity : .food
    }

    /// Into the questions, starting from what you said last time if you have
    /// said anything.
    private func startAsking() {
        draft = you.datePreferences?.answers
            ?? Array(repeating: nil, count: DatePreferences.questions.count)
        withAnimation(ArchMotion.standard) { questionIndex = 0 }
    }

    /// Asks Apple Maps about the person on screen, once.
    ///
    /// The person is read before the wait and checked after it: switching to
    /// somebody else cancels this, and a cancelled search must not mark the
    /// person it was for as unreachable.
    private func findPlaces() async {
        guard isLive, let candidate = chosen, nearby[candidate.id] == nil else { return }
        unreachable.remove(candidate.id)
        let found = await VenueSearch.nearby(you: you, them: candidate.person)
        guard !Task.isCancelled else { return }
        if let found {
            nearby[candidate.id] = found
        } else {
            unreachable.insert(candidate.id)
        }
    }

    // MARK: Pieces

    private var masthead: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Date planner")
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)
            Text("Somewhere you would both actually like, about halfway between you.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, ArchSpacing.xs)
        .padding(.bottom, ArchSpacing.l)
    }

    /// Your matches and the people you are talking to, in one row. Faces rather
    /// than names alone, because a row of names is a list you have to read.
    private var picker: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Plan with")
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)

            ScrollView(.horizontal) {
                HStack(spacing: ArchSpacing.m) {
                    ForEach(candidates) { candidate in
                        let isChosen = candidate.id == chosen?.id
                        Button {
                            chosenID = candidate.id
                            pickedTime = nil
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
                            }
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel(candidate.person.name)
                        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
                        // By id: a name is also on their row in Messages and
                        // their card in the Daily 5.
                        .accessibilityIdentifier("planner.with.\(candidate.id)")
                    }
                }
                .padding(.vertical, ArchSpacing.xxs)
                .padding(.horizontal, 3)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, ArchSpacing.l)
    }

    @ViewBuilder
    private func shared(_ plan: DatePlan, with person: Person) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("What you share")
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)

            if plan.shared.isEmpty {
                Text("Nothing in common yet in what you each wrote, so this leans on what \(person.name) wrote.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VitalsRow(vitals: plan.shared.map(\.label))
            }

            if !plan.sameWords.isEmpty {
                Text("You both wrote \(plan.sameWords.map { "\u{201C}\($0)\u{201D}" }.joined(separator: " and ")).")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }

            if let halfway = plan.halfway {
                Text("About halfway: \(halfway)")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }
        }
        .padding(.bottom, ArchSpacing.l)
    }

    /// Your own answers, in a line, and the way back into the questions. Only
    /// ever yours: the other person's answers shape the plan and are not shown.
    @ViewBuilder
    private var preferencesRow: some View {
        if let preferences = you.datePreferences {
            VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your date preferences")
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                    Spacer(minLength: ArchSpacing.s)
                    ArchTextButton(title: "Edit") { startAsking() }
                        .accessibilityLabel("Edit your date preferences")
                        .accessibilityIdentifier("planner.editPreferences")
                }
                Text(preferences.summary)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, ArchSpacing.l)
        }
    }

    /// The next seven days, tomorrow first. A row of their own rather than a
    /// calendar: a week is all the planner offers, and seven things fit on a
    /// phone without a second screen to choose between them.
    private var dayRow: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("When")
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)

            HStack(spacing: ArchSpacing.xxs) {
                ForEach(Array(days.enumerated()), id: \.element) { index, option in
                    let isOn = option == day
                    Button { pickedDay = option } label: {
                        VStack(spacing: 2) {
                            Text(option.shortWeekday)
                                .archText(.caption)
                                .foregroundStyle(isOn ? ArchColor.limestone : ArchColor.mortar)
                            Text(option.dayNumber)
                                .archText(.subhead)
                                .foregroundStyle(isOn ? ArchColor.limestone : ArchColor.mortar)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                                .fill(isOn ? ArchColor.stoneRaised : ArchColor.stone)
                        )
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                    .accessibilityLabel(index == 0 ? "Tomorrow, \(option.long)" : option.long)
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("planner.day.\(index)")
                }
            }
        }
        .padding(.bottom, ArchSpacing.s)
    }

    /// Two choices, so two buttons rather than a system segmented control: the
    /// app draws its own controls, and a stock one would be the only grey
    /// rectangle on the screen.
    private func timeToggle(_ time: DatePlan.TimeOfDay) -> some View {
        HStack(spacing: ArchSpacing.xs) {
            ForEach(DatePlan.TimeOfDay.allCases) { option in
                let isOn = option == time
                Button { pickedTime = option } label: {
                    Text(option.title)
                        .archText(.subhead)
                        .foregroundStyle(isOn ? ArchColor.limestone : ArchColor.mortar)
                        .frame(maxWidth: .infinity)
                        .frame(height: ArchSpacing.minimumTapTarget)
                        .background(
                            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                                .fill(isOn ? ArchColor.stoneRaised : ArchColor.stone)
                        )
                }
                .buttonStyle(PressScaleStyle(scale: 0.99))
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.bottom, ArchSpacing.l)
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
    }

    /// An item added and not yet told what it is.
    private func blankCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text(index == 0 ? "What should the date start with?" : "What next?")
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)
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
            HStack {
                ArchTextButton(title: "Surprise me") {
                    withAnimation(ArchMotion.standard) { fill(index, with: surprise(for: index)) }
                }
                .accessibilityIdentifier("planner.choose.surprise")
                Spacer(minLength: 0)
                if items.count > 1 {
                    ArchTextButton(title: "Remove") { withAnimation(ArchMotion.standard) { remove(index) } }
                        .accessibilityLabel("Remove this item")
                }
            }
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

    /// Another item, while there is room; the limit said in words once there
    /// is not. Hidden while a blank one is waiting to be chosen.
    @ViewBuilder
    private var addRow: some View {
        if !items.contains(where: { $0.category == nil }) {
            if items.count < PlanItem.maximum {
                ArchButton(title: "Add to the date", kind: .quiet) {
                    withAnimation(ArchMotion.standard) { add() }
                }
                .accessibilityIdentifier("planner.addItem")
                .padding(.top, ArchSpacing.m)
            } else {
                Text("Three is as many as a plan holds.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .frame(maxWidth: .infinity)
                    .padding(.top, ArchSpacing.m)
            }
        }
    }

    private func stopCard(_ stop: DatePlan.Stop, index: Int, in plan: DatePlan) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            HStack(alignment: .top, spacing: ArchSpacing.s) {
                Text(DatePlanner.clockTime(stop.start))
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                    .frame(width: 64, alignment: .leading)

                VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                    Text(stop.category.title)
                        .archText(.caption)
                        .foregroundStyle(ArchColor.mortar)
                    Text(stop.venue.name)
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(stop.venue.kind.label) \u{00B7} \(stop.venue.neighbourhood)")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                    // Its hours, and whether they are its own or what places
                    // like it usually keep. Said, because a guess shown as a
                    // fact is how two people end up at a locked door.
                    Text(hoursLine(stop))
                        .archText(.caption)
                        .foregroundStyle(stop.isOpenThroughout ? ArchColor.mortar : ArchColor.limestone)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(stop.reason)
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.limestone)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, ArchSpacing.xxs)
                    if !stop.canSwap {
                        Text(onlyFit(stop, in: plan))
                            .archText(.caption)
                            .foregroundStyle(ArchColor.mortar)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                // Only where there is somewhere else to go. A Swap that lands on
                // the same place looks like a button that does not work.
                if stop.canSwap {
                    ArchTextButton(title: "Swap") {
                        if items.indices.contains(index) { items[index].skips += 1 }
                        replanned = nil
                        sentTo = nil
                    }
                    .accessibilityLabel("Swap \(stop.venue.name)")
                }
            }

            // How long: one, two or three hours. Everything after it moves.
            HStack(spacing: ArchSpacing.xxs) {
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
                ArchTextButton(title: "Remove") { withAnimation(ArchMotion.standard) { remove(index) } }
                    .accessibilityLabel("Remove \(stop.venue.name)")
                    .accessibilityIdentifier("planner.remove.\(index)")
            }
            .padding(.leading, 64 + ArchSpacing.s)
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

    @ViewBuilder
    private func footer(_ plan: DatePlan, with candidate: PlannerCandidate) -> some View {

        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text(summary(plan))
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            ArchButton(title: "Share this plan") { sharing = plan }

            if let sentTo {
                Text("Sent to \(sentTo). It is in your conversation.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, ArchSpacing.l)
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            ShareWithSheet(
                candidates: candidates,
                plannedWith: candidate.id,
                onPick: { picked in
                    if let sharing {
                        onSend(picked.conversation,
                               DatePlanner.message(for: sharing),
                               SharedPlan(sharing, sharedWith: picked.person,
                                          plannedWith: candidate.person))
                    }
                    sentTo = picked.person.name
                    self.sharing = nil
                },
                onCancel: { sharing = nil }
            )
        }
    }

    private func summary(_ plan: DatePlan) -> String {
        var parts = ["Done by about \(DatePlanner.clockTime(plan.endsAt))."]
        if let day = plan.day { parts.insert("\(day.long).", at: 0) }
        if let km = plan.fromYou {
            parts.append(String(format: "The first stop is %.1f km from you.", km))
        }
        if let fairness = plan.fairness { parts.append(fairness) }
        // Apple Maps does not give an app opening hours, so the plan cannot
        // know them. Better said than discovered at a locked door.
        if isLive {
            parts.append("Places are from Apple Maps, which does not share opening hours, so the hours shown are what places like these usually keep. Check before you go.")
        }
        return parts.joined(separator: " ")
    }

    /// While Apple Maps is asked, and if it could not be.
    @ViewBuilder
    private func looking(for candidate: PlannerCandidate) -> some View {
        if unreachable.contains(candidate.id) {
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
            Text("Finding places near you both\u{2026}")
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
            Text("Apple Maps found no caf\u{00E9}s, parks or restaurants near the point halfway between you.")
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
