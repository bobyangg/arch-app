import Foundation

struct PromptQuestion: Identifiable, Hashable {
    let id: String
    let text: String
}

struct PromptGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let questions: [PromptQuestion]
}

/// The questions you can answer.
///
/// These are the product's voice more than any other copy in the app, so the test
/// every one of them has to pass is: **can this be answered generically?** "What
/// are you passionate about" can — and the answer is always travel and food. "The
/// last thing I read twice" cannot; you either have one or you say so.
///
/// So: no questions with a correct answer, no questions fishing for a boast, and
/// nothing quirky-cute. A question that invites a joke gets jokes, and a profile
/// full of jokes tells you nothing about whether you would like the person.
enum PromptLibrary {

    static let groups: [PromptGroup] = [
        PromptGroup(id: "time", title: "How you spend your time", questions: [
            .init(id: "q-think", text: "Where I go when I need to think"),
            .init(id: "q-slower", text: "Something I am slower at than everyone else"),
            .init(id: "q-made", text: "The last thing I made with my hands"),
            .init(id: "q-week", text: "What my week actually looks like"),
            .init(id: "q-return", text: "A place in this city I keep going back to"),
            .init(id: "q-toolong", text: "Something I do that takes far too long")
        ]),
        PromptGroup(id: "think", title: "What you think", questions: [
            .init(id: "q-changed", text: "A thing I have changed my mind about"),
            .init(id: "q-lost", text: "The best argument I have lost"),
            .init(id: "q-unpopular", text: "Something everyone likes that I do not"),
            .init(id: "q-wrong", text: "A thing I am probably wrong about"),
            .init(id: "q-defend", text: "Something I will defend that I should not"),
            .init(id: "q-opinion", text: "The last strong opinion I formed")
        ]),
        PromptGroup(id: "notice", title: "What you notice", questions: [
            .init(id: "q-twice", text: "The last thing I read twice"),
            .init(id: "q-detail", text: "A detail I get unreasonably interested in"),
            .init(id: "q-surprised", text: "The last thing that genuinely surprised me"),
            .init(id: "q-explain", text: "What I would happily explain for an hour"),
            .init(id: "q-fell", text: "Something I looked up recently and fell into"),
            .init(id: "q-others", text: "Something I notice that other people do not")
        ]),
        PromptGroup(id: "direction", title: "Where you are headed", questions: [
            .init(id: "q-inherited", text: "Something I inherited that is not money"),
            .init(id: "q-miss", text: "What I miss about where I grew up"),
            .init(id: "q-risk", text: "A risk that worked out"),
            .init(id: "q-better", text: "What I am slowly getting better at"),
            .init(id: "q-impulse", text: "The best decision I made on impulse"),
            .init(id: "q-five", text: "Something I want to be doing in five years")
        ])
    ]

    static var all: [PromptQuestion] { groups.flatMap(\.questions) }

    /// Finds a question by its text, for a profile that stores the words rather
    /// than the id.
    static func question(matching text: String) -> PromptQuestion? {
        all.first { $0.text == text }
    }
}
