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
    let id = UUID()
}

struct DatePlannerView: View {
    let you: Person
    let candidates: [PlannerCandidate]
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
    /// The question showing, while the questions are; nil otherwise.
    @State private var questionIndex: Int?
    @State private var draft: [Int?] = Array(repeating: nil, count: DatePreferences.questions.count)
    /// How many times each stop has been swapped. Reset whenever the person or
    /// the time of day changes, because the rankings underneath have changed too.
    @State private var skips: [DatePlan.Role: Int] = [:]
    /// Who the plan last went to, by name, for the line under the button.
    @State private var sentTo: String?
    /// The plan being shared, while the list of people is open.
    @State private var sharing: DatePlan?

    private var chosen: PlannerCandidate? {
        candidates.first { $0.id == chosenID } ?? candidates.first
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
                        skips = [:]
                        pickedTime = nil
                    }
                } else if you.datePreferences == nil {
                    PlannerGetStarted { startAsking() }
                } else if let chosen {
                    let time = openingTime(with: chosen.person)
                    let plan = DatePlanner.plan(you: you, them: chosen.person, time: time,
                                                venues: venues, skips: skips)
                    picker
                    shared(plan, with: chosen.person)
                    preferencesRow
                    timeToggle(time)
                    itinerary(plan)
                    footer(plan, with: chosen)
                } else {
                    preferencesRow
                    emptyState
                }
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.bottom, ArchSpacing.sectionGap)
        }
        .background(ArchColor.night)
        .onChange(of: chosenID) { _, _ in
            skips = [:]
            sentTo = nil
        }
        .onChange(of: pickedTime) { _, _ in
            skips = [:]
            sentTo = nil
        }
        // What you wrote and what you answered are what the rankings are built
        // from. When either changes, a swap count from the old rankings would
        // point at an arbitrary place in the new ones, so start from the top.
        .onChange(of: you.interests) { _, _ in skips = [:] }
        .onChange(of: you.datePreferences) { _, _ in skips = [:] }
        // "Change it" on a plan in a thread lands here, on that person.
        .onChange(of: preset) { _, preset in
            guard let preset else { return }
            questionIndex = nil
            chosenID = preset.personID
            pickedTime = preset.time
            skips = [:]
            sentTo = nil
        }
        // "Get started" in the popup after onboarding.
        .onChange(of: startQuestions) { _, _ in startAsking() }
    }

    /// Into the questions, starting from what you said last time if you have
    /// said anything.
    private func startAsking() {
        draft = you.datePreferences?.answers
            ?? Array(repeating: nil, count: DatePreferences.questions.count)
        withAnimation(ArchMotion.standard) { questionIndex = 0 }
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

    private func itinerary(_ plan: DatePlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(plan.stops) { stop in
                if let travel = stop.travel {
                    travelLine(travel)
                }
                stopCard(stop)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planner.itinerary")
    }

    private func stopCard(_ stop: DatePlan.Stop) -> some View {
        HStack(alignment: .top, spacing: ArchSpacing.s) {
            Text(DatePlanner.clockTime(stop.start))
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)
                .frame(width: 64, alignment: .leading)

            VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                Text(stop.role.title)
                    .archText(.caption)
                    .foregroundStyle(ArchColor.mortar)
                Text(stop.venue.name)
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(stop.venue.kind.label) \u{00B7} \(stop.venue.neighbourhood)")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                Text(stop.reason)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ArchSpacing.xxs)
            }

            Spacer(minLength: 0)

            ArchTextButton(title: "Swap") { skips[stop.role, default: 0] += 1 }
                .accessibilityLabel("Swap \(stop.venue.name)")
        }
        .padding(ArchSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(ArchColor.stone)
        )
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
        if let km = plan.fromYou {
            parts.append(String(format: "The first stop is %.1f km from you.", km))
        }
        if let fairness = plan.fairness { parts.append(fairness) }
        return parts.joined(separator: " ")
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
