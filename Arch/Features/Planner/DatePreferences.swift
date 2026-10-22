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
            case .doing:    return [.studio, .museum, .shop, .show, .play, .attraction]
            case .outside:  return [.walk, .park]
            case .nightOut: return [.bar, .listening, .show, .food, .cinema, .play]
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
    /// How far you would travel for a date, in miles, from the slider. Nil for
    /// an answer from before the slider, which `distance` stands in for: a
    /// walk is a mile, a ride six. `distance` is still written beside it, for
    /// builds from before the slider (`backend/040`).
    var reachMiles: Int?

    /// Your distance in miles, however you answered.
    var miles: Int { reachMiles ?? (distance == .walkable ? 1 : 6) }

    static let milesRange = 1...15
    /// Where the slider sits before it is moved.
    static let startingMiles = 3

    static func milesText(_ miles: Int) -> String {
        "Up to \(miles) mile\(miles == 1 ? "" : "s") away"
    }

    /// What that distance means for the plan.
    static func milesHint(_ miles: Int) -> String {
        miles <= 1 ? "Walking distance. Every stop stays on foot."
            : miles <= 5 ? "A short ride. Stops can be a few minutes apart."
            : "Across town is fine."
    }

    // MARK: The questions

    /// One screen of the five. Options are listed in the order of the answer's
    /// `allCases`, so an answer is its option's index and back.
    struct Question: Identifiable {
        let id: Int
        let text: String
        let options: [String]
        /// Answered with a number of miles on a slider, not an option.
        var isMiles = false
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
        // A distance, not a choice. It used to be "Keep it walkable" or "A
        // short ride is fine".
        Question(id: 4, text: "How far would you travel for a date?", options: [], isMiles: true),
    ]

    /// From five answers, one per question: an option index each, and for the
    /// last a number of miles. Nil unless all five are answered with something
    /// that exists.
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
              let miles = answers[4], Self.milesRange.contains(miles)
        else { return nil }
        self.init(style: style, timeOfDay: time, drinks: drinks, budget: budget,
                  distance: miles <= 1 ? .walkable : .ride, reachMiles: miles)
    }

    init(style: Style, timeOfDay: Time, drinks: Drinks, budget: Budget, distance: Distance,
         reachMiles: Int? = nil) {
        self.style = style
        self.timeOfDay = timeOfDay
        self.drinks = drinks
        self.budget = budget
        self.distance = distance
        self.reachMiles = reachMiles
    }

    /// The five answers, to start the questions again from what you said.
    var answers: [Int?] {
        [Style.allCases.firstIndex(of: style),
         Time.allCases.firstIndex(of: timeOfDay),
         Drinks.allCases.firstIndex(of: drinks),
         Budget.allCases.firstIndex(of: budget),
         miles]
    }

    /// Your own answers in a line, for the planner's "Your preferences" row.
    /// Only ever built from your own: another person's are never put into words.
    var summary: String { summary(includingDistance: true) }

    /// The same, without the distance where its slider sits beside the line.
    func summary(includingDistance: Bool) -> String {
        var parts: [String] = []
        for (index, question) in Self.questions.enumerated() {
            if question.isMiles {
                if includingDistance { parts.append(Self.milesText(miles)) }
            } else if let answer = answers[index] {
                parts.append(question.options[answer])
            }
        }
        return parts.joined(separator: " \u{00B7} ")
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

    /// The stops either side of the main thing stay on foot from it: either
    /// of you would go a mile or less.
    var walkable: Bool { both.contains { $0.miles <= 1 } }

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
