import SwiftUI

/// A plan as it travels in a message, or an answer to one.
///
/// Stored in `messages.plan` beside the message's words, which stay readable on
/// their own -- see `backend/024`. A plan is what the planner laid out, frozen:
/// names, times and the way between, never a coordinate.
struct SharedPlan: Codable, Hashable {

    struct Stop: Codable, Hashable {
        /// Minutes after midnight.
        let start: Int
        let name: String
        let kind: String
        let neighbourhood: String
        /// How you get here from the stop before. Nil for the first.
        let travel: String?
        /// Why this one, in words both people can read. Nil when the plan was
        /// shared with somebody other than the person it was made with -- see
        /// `init(_:sharedWith:plannedWith:)`.
        let reason: String?
        /// The block it was given, in minutes, and what kind of item it was:
        /// so the card can say how long, and "Change it" can start from the
        /// same shape of date. Nil on plans sent before items had either.
        var minutes: Int? = nil
        var category: String? = nil
    }

    /// "afternoon" or "evening", on a plan.
    var time: String?
    /// "2026-10-10", on a plan made with a day. Optional, so plans sent before
    /// there was a day still read, and builds from before ignore it.
    var day: String?
    var stops: [Stop]?
    /// On an answer: the id of the message whose plan it answers.
    var answering: String?

    var isPlan: Bool { !(stops ?? []).isEmpty }
    var timeOfDay: DatePlan.TimeOfDay? { time.flatMap(DatePlan.TimeOfDay.init(rawValue:)) }
    var planDay: PlanDay? { day.flatMap(PlanDay.init(iso:)) }

    /// The plan's shape, as items the planner can start again from: each
    /// stop's kind and hours, and no place -- the planner finds those afresh.
    var planItems: [PlanItem]? {
        let items = (stops ?? []).compactMap { stop -> PlanItem? in
            guard let category = stop.category.flatMap(DatePlan.Category.init(rawValue:)) else { return nil }
            let hours = min(max((stop.minutes ?? 60) / 60, 1), 3)
            return PlanItem(category: category, hours: hours)
        }
        return items.isEmpty ? nil : items
    }

    /// A plan, frozen for sending.
    ///
    /// **The reasons go only to the person it was made for.** They quote what
    /// that person wrote -- "Yusuf wrote 'Walking at night'" -- and "Share this
    /// plan" can send it to anybody in Messages. Sent to Nadia, that would show
    /// her Yusuf's interests and that you are planning a date with him. So to
    /// anybody else the stops go and the reasons stay behind.
    init(_ plan: DatePlan, sharedWith recipient: Person, plannedWith: Person) {
        let keepReasons = recipient.id == plannedWith.id
        self.time = plan.time.rawValue
        self.day = plan.day?.iso
        self.stops = plan.stops.map { stop in
            Stop(start: stop.start,
                 name: stop.venue.name,
                 kind: stop.venue.kind.label,
                 neighbourhood: stop.venue.neighbourhood,
                 travel: stop.travel?.label,
                 reason: keepReasons ? stop.sharedReason : nil,
                 minutes: stop.minutes,
                 category: stop.category.rawValue)
        }
        self.answering = nil
    }

    /// "I'm in", to the plan in a given message.
    init(answering messageID: String) {
        self.time = nil
        self.day = nil
        self.stops = nil
        self.answering = messageID
    }

    /// For fixtures, written by hand.
    init(time: DatePlan.TimeOfDay, day: PlanDay? = nil, stops: [Stop]) {
        self.time = time.rawValue
        self.day = day?.iso
        self.stops = stops
        self.answering = nil
    }
}

/// What a thread can do with a plan, handed down from the app shell through the
/// environment rather than through every view between them -- a thread is built
/// in two places, and neither has any other business knowing about plans.
struct PlanActions {
    /// Send words and a plan (or an answer to one) into a conversation.
    var send: (Conversation, String, SharedPlan) -> Void = { _, _, _ in }
    /// Open the Date planner on this person, from this plan: its day, its
    /// time of day and its items.
    var change: (Conversation, SharedPlan) -> Void = { _, _ in }
}

private struct PlanActionsKey: EnvironmentKey {
    static let defaultValue = PlanActions()
}

extension EnvironmentValues {
    var planActions: PlanActions {
        get { self[PlanActionsKey.self] }
        set { self[PlanActionsKey.self] = newValue }
    }
}

/// A plan in a conversation.
///
/// Wider than a message and on the card surface, because it is a thing you can
/// act on rather than something somebody said. Each stop opens to say why it was
/// chosen. Underneath, the one thing still open about it: whether the other
/// person is in.
///
/// - The person it was sent to sees **I'm in** and **Change it**. Saying yes
///   sends "I'm in." back, tied to this plan, and the card says so on both
///   phones. Changing it opens the planner on the two of you, at the same time
///   of day.
/// - The person who sent it sees who it is waiting on, and **Change it**.
struct PlanCard: View {
    let message: Message
    let plan: SharedPlan
    let theirName: String
    /// Who has said yes, if anybody has: true for them, false for you.
    let answeredByThem: Bool?
    /// False once the conversation can no longer be written in.
    let canAct: Bool
    let onYes: () -> Void
    let onChange: () -> Void

    @State private var open: Set<Int> = []

    /// "A plan for Saturday evening"; without a day, "A plan for the evening".
    private var title: String {
        let part = plan.timeOfDay == .evening ? "evening" : "afternoon"
        if let day = plan.planDay { return "A plan for \(day.weekdayName) \(part)" }
        return "A plan for the \(part)"
    }

    /// A plan for a day that has gone is history: nobody can say yes to it.
    private var isPast: Bool {
        plan.planDay.map { $0 < .today } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                if let day = plan.planDay {
                    Text(day.long)
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array((plan.stops ?? []).enumerated()), id: \.offset) { index, stop in
                    if let travel = stop.travel {
                        HStack(spacing: ArchSpacing.s) {
                            Rectangle()
                                .fill(ArchColor.quietBorder)
                                .frame(width: 2, height: 18)
                                .padding(.leading, 26)
                            Text(travel)
                                .archText(.footnote)
                                .foregroundStyle(ArchColor.mortar)
                        }
                        .padding(.vertical, 2)
                    }
                    stopRow(index, stop)
                }
            }

            status
        }
        .padding(ArchSpacing.m)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(message.isOutgoing ? ArchColor.stoneRaised : ArchColor.stone)
        )
        .frame(maxWidth: .infinity, alignment: message.isOutgoing ? .trailing : .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thread.plan")
    }

    private func stopRow(_ index: Int, _ stop: SharedPlan.Stop) -> some View {
        let isOpen = open.contains(index)
        return Button {
            guard stop.reason != nil else { return }
            withAnimation(ArchMotion.standard) {
                if isOpen { open.remove(index) } else { open.insert(index) }
            }
        } label: {
            HStack(alignment: .top, spacing: ArchSpacing.s) {
                Text(DatePlanner.clockTime(stop.start))
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.limestone)
                    .frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.name)
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(([stop.kind, stop.neighbourhood]
                          + (stop.minutes.map { [$0 == 60 ? "1 hr" : "\($0 / 60) hr"] } ?? []))
                        .joined(separator: " \u{00B7} "))
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                    if isOpen, let reason = stop.reason {
                        Text(reason)
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.limestone)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, ArchSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(stop.reason == nil ? "" : (isOpen ? "Hides why" : "Says why it was chosen"))
    }

    @ViewBuilder
    private var status: some View {
        if let byThem = answeredByThem {
            Text(byThem ? "\(theirName) is in." : "You are in.")
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.xxs)
        } else if isPast {
            Text("This day has been and gone.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
        } else if canAct {
            if message.isOutgoing {
                HStack {
                    Text("Waiting on \(theirName).")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                    Spacer(minLength: ArchSpacing.s)
                    ArchTextButton(title: "Change it", action: onChange)
                }
            } else {
                HStack(spacing: ArchSpacing.xs) {
                    ArchButton(title: "I\u{2019}m in", action: onYes)
                    ArchButton(title: "Change it", kind: .quiet, action: onChange)
                }
                .padding(.top, ArchSpacing.xxs)
            }
        }
    }
}
