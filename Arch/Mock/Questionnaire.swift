import Foundation

/// How the matching should read an answer.
///
/// Sixteen undifferentiated multiple-choice results are not a compatibility
/// system. Tagging each question says what its answer *means*, so whoever builds
/// the matching is not left guessing whether two different answers are a problem.
enum MatchingRule: String, Hashable {
    /// A mismatch here usually ends the relationship, whatever else lines up.
    /// Treat it as a requirement, not as points.
    case requirement
    /// Closer answers mean a better match. Distance is meaningful.
    case alignment
    /// Difference is not automatically bad here — a planner and an improviser can
    /// work. Which pairings work is a judgement, not a distance.
    case complement
}

/// One compatibility question.
///
/// The answers are never shown on a profile and never add up to a score — see the
/// questionnaire intro, which says so before it starts asking.
struct QuestionnaireQuestion: Identifiable, Hashable {
    let id: String
    let text: String
    let options: [String]
    /// What this measures. Two questions should not sit on the same axis.
    let axis: String
    let rule: MatchingRule
}

/// The sixteen questions that decide who reaches your five.
///
/// **Every option has to be a defensible way to be.** That is the whole design
/// constraint. If one choice reads as the right answer, everyone picks it and the
/// question returns nothing — so "I often hope it passes" became "I tend to let
/// small things go", and the drinking question has an option for not drinking that
/// does not sound like a confession.
///
/// They are ordered to warm up: temperament first, then how you handle each other,
/// then how you live, then the three that actually decide things, ending on where
/// you are going.
enum Questionnaire {

    static let questions: [QuestionnaireQuestion] = [

        // MARK: Temperament

        .init(id: "q1",
              text: "Someone cancels plans an hour before. What is your honest first reaction?",
              options: ["Relief", "Irritation", "Neither, genuinely"],
              axis: "sociability", rule: .alignment),

        .init(id: "q2",
              text: "What does a good Saturday look like?",
              options: ["Nothing in the diary", "One good thing", "Booked from the morning"],
              axis: "pace", rule: .alignment),

        .init(id: "q3",
              text: "How do you get your energy back?",
              options: ["On my own and quiet", "With one or two people", "In a room full of people"],
              axis: "recharge", rule: .alignment),

        .init(id: "q4",
              text: "What are you like first thing in the morning?",
              options: ["Up early and useful", "Slow but fine", "Do not talk to me"],
              axis: "rhythm", rule: .complement),

        .init(id: "q5",
              text: "How much of your week is planned in advance?",
              options: ["Most of it", "Some of it", "Almost none of it"],
              axis: "structure", rule: .complement),

        // MARK: How you handle each other

        .init(id: "q6",
              text: "When something is bothering you, do you want to talk it through or sit with it first?",
              options: ["Talk it through", "Sit with it first", "Genuinely depends"],
              axis: "processing", rule: .complement),

        .init(id: "q7",
              text: "How direct are you when something is wrong?",
              options: ["I say it straight away",
                        "I wait until I know what I think",
                        "I tend to let small things go"],
              axis: "directness", rule: .complement),

        .init(id: "q8",
              text: "After an argument, what do you need?",
              options: ["To finish it before sleeping",
                        "Some time apart first",
                        "To know we are fine, details later"],
              axis: "repair", rule: .alignment),

        .init(id: "q9",
              text: "How much reassurance do you want from someone?",
              options: ["A lot, and I will say so",
                        "Some, at the right moments",
                        "Not much, I assume things are fine"],
              axis: "reassurance", rule: .complement),

        // MARK: How you live

        .init(id: "q10",
              text: "Where does drinking sit in your life?",
              options: ["It is part of how I socialise", "Occasionally", "I do not drink"],
              axis: "drinking", rule: .alignment),

        .init(id: "q11",
              text: "How close are you to your family?",
              options: ["Very, we talk constantly",
                        "Close, but not in each other's days",
                        "It is complicated",
                        "Not close"],
              axis: "family", rule: .complement),

        .init(id: "q12",
              text: "What is money for?",
              options: ["Spending on things worth doing",
                        "Building something steady",
                        "I try not to think about it much"],
              axis: "money", rule: .alignment),

        .init(id: "q13",
              text: "How much does your work matter to you?",
              options: ["It is a large part of who I am",
                        "It pays for the rest of my life",
                        "Somewhere in between"],
              axis: "work", rule: .alignment),

        // MARK: The ones that decide things

        .init(id: "q14",
              text: "Do you want children?",
              options: ["Yes", "No", "Open to it", "Still working it out"],
              axis: "children", rule: .requirement),

        .init(id: "q15",
              text: "Do you see yourself with one person at a time?",
              options: ["Yes, one at a time",
                        "No, that is not how I do relationships",
                        "Still working it out"],
              axis: "exclusivity", rule: .requirement),

        .init(id: "q16",
              text: "Do you want to be living in this city in five years?",
              options: ["Yes", "No", "It depends who I am with"],
              axis: "location", rule: .requirement)
    ]

    static var count: Int { questions.count }

    /// The three that are requirements rather than preferences. Useful to a matching
    /// system, and a reasonable thing to let someone revisit later.
    static var requirements: [QuestionnaireQuestion] {
        questions.filter { $0.rule == .requirement }
    }
}
