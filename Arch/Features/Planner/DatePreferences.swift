import Foundation

/// What somebody wants a date to be like: five answers, asked the first time the
/// Date planner is opened.
///
/// **Not part of the onboarding questionnaire.** Those answers decide who reaches
/// your five and are never seen by anybody. These decide what a date with
/// somebody you are already talking to looks like, so the planner on their phone
/// needs yours -- see `backend/029`. Nothing in the app shows another person's
/// answers; a plan only reflects them.
///
/// Stored as raw values, which are the values the table's checks allow.
struct DatePreferences: Codable, Hashable {

    /// What a good first date sounds like.
    enum Style: String, Codable, CaseIterable {
        case talk, doing, outside
        case nightOut = "night_out"

        /// The kinds of place this sort of date is made of.
        var kinds: Set<Venue.Kind> {
            switch self {
            case .talk:     return [.coffee, .walk, .food]
            case .doing:    return [.studio, .museum, .shop, .show]
            case .outside:  return [.walk, .park]
            case .nightOut: return [.bar, .listening, .show, .food]
            }
        }
    }

    enum Time: String, Codable, CaseIterable {
        case afternoon, evening, either

        var timeOfDay: DatePlan.TimeOfDay? {
            switch self {
            case .afternoon: return .afternoon
            case .evening:   return .evening
            case .either:    return nil
            }
        }
    }

    enum Drinks: String, Codable, CaseIterable {
        case yes, sometimes, no
    }

    /// Ordered from the least spent to the most, which is what "the stricter of
    /// the two" compares.
    enum Budget: String, Codable, CaseIterable, Comparable {
        case low, middle, any

        static func < (a: Budget, b: Budget) -> Bool {
            allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
        }
    }

    enum Distance: String, Codable, CaseIterable {
        case walkable, ride
    }

    var style: Style
    var timeOfDay: Time
    var drinks: Drinks
    var budget: Budget
    var distance: Distance

    // MARK: The questions

    /// One screen of the five. Options are listed in the order of the answer's
    /// `allCases`, so an answer is its option's index and back.
    struct Question: Identifiable {
        let id: Int
        let text: String
        let options: [String]
    }

    static let questions: [Question] = [
        Question(id: 0, text: "What sounds like a good first date?",
                 options: ["Coffee and a long conversation",
                           "Doing something together",
                           "Getting outside",
                           "A proper night out"]),
        Question(id: 1, text: "When are you at your best?",
                 options: ["In the afternoon", "In the evening", "Either is fine"]),
        Question(id: 2, text: "How do you feel about drinks?",
                 options: ["Happy to have one", "Fine, but not the point", "I don\u{2019}t drink"]),
        Question(id: 3, text: "What would you like to spend?",
                 options: ["As little as possible", "A coffee and a meal", "Whatever makes it good"]),
        Question(id: 4, text: "How far would you go in one date?",
                 options: ["Keep it walkable", "A short ride is fine"]),
    ]

    /// From five option indices, one per question. Nil unless all five are
    /// answered with an option that exists.
    init?(answers: [Int?]) {
        guard answers.count == Self.questions.count else { return nil }
        func pick<T: CaseIterable>(_ index: Int?, _: T.Type) -> T? {
            guard let index, index >= 0, index < T.allCases.count else { return nil }
            return Array(T.allCases)[index]
        }
        guard let style = pick(answers[0], Style.self),
              let time = pick(answers[1], Time.self),
              let drinks = pick(answers[2], Drinks.self),
              let budget = pick(answers[3], Budget.self),
              let distance = pick(answers[4], Distance.self)
        else { return nil }
        self.init(style: style, timeOfDay: time, drinks: drinks, budget: budget, distance: distance)
    }

    init(style: Style, timeOfDay: Time, drinks: Drinks, budget: Budget, distance: Distance) {
        self.style = style
        self.timeOfDay = timeOfDay
        self.drinks = drinks
        self.budget = budget
        self.distance = distance
    }

    /// The five option indices, to start the questions again from what you said.
    var answers: [Int?] {
        [Style.allCases.firstIndex(of: style),
         Time.allCases.firstIndex(of: timeOfDay),
         Drinks.allCases.firstIndex(of: drinks),
         Budget.allCases.firstIndex(of: budget),
         Distance.allCases.firstIndex(of: distance)]
    }

    /// Your own answers in a line, for the planner's "Your preferences" row.
    /// Only ever built from your own: another person's are never put into words.
    var summary: String {
        Self.questions.enumerated()
            .compactMap { index, question in answers[index].map { question.options[$0] } }
            .joined(separator: " \u{00B7} ")
    }
}

/// Two people's answers, as the planner uses them.
///
/// **Rules take the stricter answer; everything else is blended.** If either of
/// you does not drink, nothing on the plan is a bar -- the person who would have
/// liked one loses a little, the person who does not drink would lose the date.
/// Walking and spending work the same way. What a good date *sounds like* is a
/// taste, not a limit, so both tastes count and neither overrules the other.
///
/// Either side may be nil: somebody who has not answered yet is planned for from
/// their interests alone, exactly as before the questions existed.
struct DateFit {
    let yours: DatePreferences?
    let theirs: DatePreferences?

    private var both: [DatePreferences] { [yours, theirs].compactMap { $0 } }

    /// Nothing drink-led on the plan at all.
    var noDrinks: Bool { both.contains { $0.drinks == .no } }

    /// The stops either side of the main thing stay on foot from it.
    var walkable: Bool { both.contains { $0.distance == .walkable } }

    /// The lower of the two budgets.
    var budget: DatePreferences.Budget { both.map(\.budget).min() ?? .any }

    /// The time of day to open on: yours if you have one, theirs if you said
    /// either, afternoon if neither of you did.
    var time: DatePlan.TimeOfDay {
        yours?.timeOfDay.timeOfDay ?? theirs?.timeOfDay.timeOfDay ?? .afternoon
    }

    /// May this place be on the plan at all.
    func allows(_ venue: Venue) -> Bool {
        !(noDrinks && venue.kind.isDrinkLed)
    }

    /// How much better or worse a place fits what the two of you said, in the
    /// same units as `DatePlanner`'s liking: a shared interest is worth three.
    func score(_ venue: Venue) -> Double {
        var score = 0.0
        // Each person whose kind of date this is.
        for answers in both where answers.style.kinds.contains(venue.kind) {
            score += 1.5
        }
        // Drinks, when neither of you has ruled them out.
        if venue.kind.isDrinkLed {
            for answers in both {
                switch answers.drinks {
                case .yes:       score += 0.5
                case .sometimes: score -= 0.5
                case .no:        break
                }
            }
        }
        // Spending, by the lower budget.
        switch budget {
        case .low:    score -= 1.5 * Double(venue.kind.price)
        case .middle: score -= 0.5 * Double(venue.kind.price)
        case .any:    break
        }
        return score
    }
}
