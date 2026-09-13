import Foundation

/// What the sixteen answers are worth when two people are put side by side.
///
/// `MatchingRule` on each question says what *shape* its scoring has. This is where
/// the numbers live. Nothing here is derivable from the questions — every value is
/// a claim about what makes two people work, and the ones tagged `.complement` are
/// judgement all the way down.
///
/// **Scale.** Every cell is 0…1, where 1 is "these two answers are good together"
/// and 0 is "these two answers are a problem". Not a distance: higher is better, and
/// the word "distance" in Arch means miles.
///
/// **Symmetric.** `grid[a][b] == grid[b][a]`, always. The matcher builds one edge
/// per pair and spends a slot from each end, so a pair has to have one score.
/// `isConsistent` checks it.
///
/// **Requirements are not in here.** Children, exclusivity and location are filters,
/// and live in `Requirement` below. A high score must never buy its way past "does
/// not want children" — the moment it can, those questions stop meaning anything.
///
/// The weights sum to 13, so a perfect pair scores 13.0 and the number is readable
/// without a calculator.
///
/// ## Where to argue
///
/// The alignment questions are close to mechanical: same answer 1.0, adjacent 0.75,
/// opposite 0.25, deviating only where there is a reason, and the reason is written
/// next to it. The complement questions are where the opinions are, and three cells
/// are worth your attention before anything ships:
///
/// - **q5, `Most of it` × `Almost none of it` (0.5).** A planner and somebody who
///   will not commit to a Tuesday. I have it as friction, not disqualifying.
/// - **q6, `Talk it through` × `Sit with it first` (0.45).** Tagged complement,
///   scored almost like alignment — see the note on that table.
/// - **q9, `A lot` × `Not much` (0.3).** Among the lowest in the set, and the one I
///   am most confident about.
///
/// **The usable range is about 5.4 to 13, not 0 to 13.** No single mismatch zeroes
/// a question, so two people who clash on everything still floor around 5.35. It
/// does not affect the ranking, which is all the matcher uses — but when you read a
/// log, 8 is a poor pairing rather than a middling one.
struct CompatibilityTable {
    let questionID: String
    /// How much this question counts, relative to the others.
    let weight: Double
    /// Square, symmetric, indexed by position in the question's `options`.
    let grid: [[Double]]

    func score(_ a: Int, _ b: Int) -> Double {
        guard grid.indices.contains(a), grid[a].indices.contains(b) else { return 0 }
        return grid[a][b]
    }
}

enum Compatibility {

    // MARK: Temperament

    /// Relief / Irritation / Neither, genuinely.
    ///
    /// Not an ordinal scale — "Neither" is off the axis rather than between the
    /// other two, so this one gets a hand-built grid instead of the standard
    /// fall-off. Relief and Irritation are the poles: one of you is quietly glad
    /// when an evening dies and the other minded. Over years that is the same
    /// argument on a loop.
    static let sociability = CompatibilityTable(questionID: "q1", weight: 0.8, grid: [
        //        Relief  Irritation  Neither
        /* Relief     */ [1.00, 0.40, 0.80],
        /* Irritation */ [0.40, 0.90, 0.80],
        /* Neither    */ [0.80, 0.80, 0.90]
    ])

    /// Nothing in the diary / One good thing / Booked from the morning.
    ///
    /// Clean ordinal, so clean fall-off. How full a weekend is turns out to be how
    /// full a life is, and the two ends want genuinely different ones.
    static let pace = CompatibilityTable(questionID: "q2", weight: 1.0, grid: [
        [1.00, 0.75, 0.25],
        [0.75, 1.00, 0.75],
        [0.25, 0.75, 1.00]
    ])

    /// On my own and quiet / With one or two people / In a room full of people.
    ///
    /// The heaviest of the temperament three, because it decides what an ordinary
    /// Tuesday evening looks like for the rest of your life.
    ///
    /// I was tempted to drop the bottom-right cell to 0.9 — two people who both
    /// recharge in a crowd may rarely be alone together — and left it at 1.0
    /// because that is a guess about their life rather than about their fit.
    static let recharge = CompatibilityTable(questionID: "q3", weight: 1.2, grid: [
        [1.00, 0.75, 0.25],
        [0.75, 1.00, 0.75],
        [0.25, 0.75, 1.00]
    ])

    /// Up early and useful / Slow but fine / Do not talk to me.
    ///
    /// The lightest question in the set, and scored generously on purpose. Mornings
    /// are the part of a day two people most easily run in parallel — neither is
    /// asking the other to participate. One gets a quiet hour, the other is left
    /// alone until they surface.
    ///
    /// **The argument against, if you want to flip it:** it is a daily, repeated
    /// mismatch, and small frictions repeated every morning for years are exactly
    /// the kind that wear through. Drop `Up early × Do not talk` to about 0.5 if
    /// you believe that more than I do.
    static let rhythm = CompatibilityTable(questionID: "q4", weight: 0.6, grid: [
        [1.00, 0.90, 0.70],
        [0.90, 1.00, 0.90],
        [0.70, 0.90, 1.00]
    ])

    // MARK: How you handle each other

    /// Most of it / Some of it / Almost none of it.
    ///
    /// **The best cell is off the diagonal**, which is the clearest example in the
    /// set of why `.complement` exists. A planner with somebody a bit looser is
    /// better than two planners (efficient, airless) and much better than two
    /// improvisers, where nothing is ever actually booked and both quietly wonder
    /// why they never go anywhere.
    static let structure = CompatibilityTable(questionID: "q5", weight: 0.9, grid: [
        //            Most  Some  None
        /* Most */ [0.90, 1.00, 0.50],
        /* Some */ [1.00, 1.00, 0.90],
        /* None */ [0.50, 0.90, 0.70]
    ])

    /// Talk it through / Sit with it first / Genuinely depends.
    ///
    /// **Tagged complement, scored almost like alignment, and that is deliberate.**
    /// Talk-it-through paired with sit-with-it-first is the demand-withdraw loop:
    /// one presses because the silence is unbearable, the other retreats further
    /// because the pressing is, and each behaviour causes the other. It is one of
    /// the most-studied predictors of couples coming apart, and I do not think a
    /// compatibility system should call it complementary just because the answers
    /// differ.
    ///
    /// Two withdrawers score below two talkers for the opposite reason: nothing
    /// escalates, and nothing gets resolved either.
    ///
    /// **If you disagree** — and the honest counter is that a patient partner
    /// teaches an anxious one to wait — raise `Talk × Sit` to about 0.7.
    static let processing = CompatibilityTable(questionID: "q6", weight: 1.3, grid: [
        //            Talk  Sit   Depends
        /* Talk    */ [0.90, 0.45, 0.85],
        /* Sit     */ [0.45, 0.80, 0.85],
        /* Depends */ [0.85, 0.85, 0.90]
    ])

    /// I say it straight away / I wait until I know what I think / I tend to let
    /// small things go.
    ///
    /// Straight-away with a considerer is the best pairing here: one raises it while
    /// it is small, the other makes sure it is worth raising.
    ///
    /// **`Let go × Let go` at 0.40 is the only cell in the set where two people
    /// giving the *same* answer score worst of all.** Everywhere else agreement is
    /// safe; here it is the trap. Two people who both let small things go never have
    /// a row and never have a conversation either — it accumulates in silence for a
    /// decade and then arrives all at once. The rest of this file describes
    /// frictions. This one is a failure mode.
    static let directness = CompatibilityTable(questionID: "q7", weight: 1.2, grid: [
        //             Straight  Wait   Let go
        /* Straight */ [0.90, 1.00, 0.60],
        /* Wait     */ [1.00, 0.95, 0.70],
        /* Let go   */ [0.60, 0.70, 0.40]
    ])

    /// To finish it before sleeping / Some time apart first / To know we are fine,
    /// details later.
    ///
    /// Alignment, and sharply so. These are *needs* in the worst hour of a bad week,
    /// and the first two are directly opposed: one cannot sleep until it is settled,
    /// the other has to leave the room to think. Neither can give the other what
    /// they need at the moment they need it most.
    static let repair = CompatibilityTable(questionID: "q8", weight: 1.2, grid: [
        //           Finish  Apart  Fine later
        /* Finish */ [1.00, 0.35, 0.70],
        /* Apart  */ [0.35, 1.00, 0.80],
        /* Later  */ [0.70, 0.80, 0.95]
    ])

    /// A lot, and I will say so / Some, at the right moments / Not much, I assume
    /// things are fine.
    ///
    /// The heaviest question in the set, and `A lot × Not much` at 0.30 is the cell
    /// I am most sure of. One person needs to be told, the other genuinely believes
    /// that saying nothing *is* the reassurance — so the first reads silence as
    /// distance and asks again, and the second cannot understand why it keeps coming
    /// up. It is the most predictable unhappiness two otherwise well-matched people
    /// can walk into.
    ///
    /// Two people who both want a lot score below the middle: it can be mutually
    /// reassuring, or it can be two anxieties feeding each other.
    static let reassurance = CompatibilityTable(questionID: "q9", weight: 1.4, grid: [
        //            A lot  Some   Not much
        /* A lot   */ [0.85, 0.90, 0.30],
        /* Some    */ [0.90, 1.00, 0.85],
        /* Not much*/ [0.30, 0.85, 0.90]
    ])

    // MARK: How you live

    /// It is part of how I socialise / Occasionally / I do not drink.
    ///
    /// The bottom-left cell is low because those two lives are differently shaped,
    /// not because either is worse. An occasional drinker can comfortably not drink;
    /// somebody for whom it is the whole social mechanism mostly cannot.
    static let drinking = CompatibilityTable(questionID: "q10", weight: 1.0, grid: [
        //             Social  Occasional  Not at all
        /* Social   */ [1.00, 0.85, 0.35],
        /* Occasion */ [0.85, 1.00, 0.75],
        /* Not      */ [0.35, 0.75, 1.00]
    ])

    /// Very, we talk constantly / Close, but not in each other's days / It is
    /// complicated / Not close.
    ///
    /// The four-option one, so ten values rather than six.
    ///
    /// **Nothing here scores somebody down for their family.** "Complicated" and
    /// "Not close" pair perfectly well with almost everything; the only cells that
    /// dip are where one person's family is constantly present and the other's is a
    /// wound, which is a lot of weather to hold between two people rather than a
    /// mark against either.
    static let family = CompatibilityTable(questionID: "q11", weight: 0.7, grid: [
        //                Very  Close  Complicated  Not close
        /* Very        */ [1.00, 0.90, 0.70, 0.60],
        /* Close       */ [0.90, 1.00, 0.85, 0.80],
        /* Complicated */ [0.70, 0.85, 0.80, 0.85],
        /* Not close   */ [0.60, 0.80, 0.85, 0.90]
    ])

    /// Spending on things worth doing / Building something steady / I try not to
    /// think about it much.
    ///
    /// The spender-and-saver pair is the cliché because it is real. `Building ×
    /// Not think` is scored lower still: somebody planning carefully alongside
    /// somebody who will not open the account is worse than two people who simply
    /// want different things, because only one of them is doing the work.
    static let money = CompatibilityTable(questionID: "q12", weight: 0.9, grid: [
        //              Spend  Build  Avoid
        /* Spend */ [1.00, 0.60, 0.60],
        /* Build */ [0.60, 1.00, 0.50],
        /* Avoid */ [0.60, 0.50, 0.70]
    ])

    /// It is a large part of who I am / It pays for the rest of my life / Somewhere
    /// in between.
    ///
    /// Two absorbed people do well together — they understand the hours. The dip is
    /// between somebody whose work is their identity and somebody whose life starts
    /// at six, because they are answering a question about where the time goes.
    static let work = CompatibilityTable(questionID: "q13", weight: 0.8, grid: [
        //             Large  Pays  Between
        /* Large   */ [1.00, 0.60, 0.85],
        /* Pays    */ [0.60, 1.00, 0.90],
        /* Between */ [0.85, 0.90, 1.00]
    ])

    // MARK: The set

    static let tables: [CompatibilityTable] = [
        sociability, pace, recharge, rhythm,
        structure, processing, directness, repair, reassurance,
        drinking, family, money, work
    ]

    /// 13.0 — what the weights sum to.
    ///
    /// **Not what a pair can score.** `processing` has no 1.00 cell, because two
    /// people who both need to talk it through immediately are good for each other
    /// but not perfect, so every pair on earth gives up 0.13 and the real ceiling is
    /// `attainableMaximum`. Use that one for anything a reader will see; use this
    /// only to check the weights still sum to what they were meant to.
    static var maximumScore: Double { tables.reduce(0) { $0 + $1.weight } }

    /// 12.87 — the best score any two people can actually reach.
    ///
    /// Scores live between this and `attainableMinimum`, a range of about 7.5 points
    /// rather than 13. Reporting a pair as a percentage of `maximumScore` squashes
    /// every real pairing into a narrow band near 77% and makes the tables look like
    /// they separate nobody, which is the opposite of what they do.
    static var attainableMaximum: Double {
        tables.reduce(0) { total, table in
            let best = table.grid.flatMap { $0 }.max() ?? 0
            return total + table.weight * best
        }
    }

    /// 5.345 — the worst two people can do while still answering every question.
    static var attainableMinimum: Double {
        tables.reduce(0) { total, table in
            let worst = table.grid.flatMap { $0 }.min() ?? 0
            return total + table.weight * worst
        }
    }

    /// Two people's answers, as one number.
    ///
    /// A question either of them skipped contributes nothing rather than a default,
    /// so a half-finished questionnaire lowers the ceiling instead of inventing
    /// agreement. Onboarding does not let anybody through with one, but a question
    /// added later would leave every existing profile in exactly that state.
    static func score(_ a: [String: Int], _ b: [String: Int]) -> Double {
        tables.reduce(0) { total, table in
            guard let i = a[table.questionID], let j = b[table.questionID] else { return total }
            return total + table.weight * table.score(i, j)
        }
    }

    // MARK: Requirements

    /// The three that filter rather than score.
    ///
    /// Each is a square grid of *allowed*, and in every one of them only the flat
    /// contradiction is barred. "Still working it out" is compatible with everybody,
    /// which is the point of having the option at all.
    enum Requirement {
        /// Yes / No / Open to it / Still working it out. Only Yes-against-No is out.
        static let children = [
            [true,  false, true,  true],
            [false, true,  true,  true],
            [true,  true,  true,  true],
            [true,  true,  true,  true]
        ]

        /// Yes, one at a time / No, that is not how I do relationships / Still
        /// working it out.
        static let exclusivity = [
            [true,  false, true],
            [false, true,  true],
            [true,  true,  true]
        ]

        /// Yes / No / It depends who I am with.
        ///
        /// **The one I would most consider demoting to a weight.** "No" can mean
        /// emigrating or it can mean thirty minutes further out, and those are not
        /// the same obstacle. It is a hard filter here because the questionnaire
        /// calls it a requirement; if the candidate sets come back thin, this is the
        /// first place to look.
        static let location = [
            [true,  false, true],
            [false, true,  true],
            [true,  true,  true]
        ]

        static func allows(_ questionID: String, _ a: Int, _ b: Int) -> Bool {
            let grid: [[Bool]]
            switch questionID {
            case "q14": grid = children
            case "q15": grid = exclusivity
            case "q16": grid = location
            default:    return true
            }
            guard grid.indices.contains(a), grid[a].indices.contains(b) else { return true }
            return grid[a][b]
        }
    }

    /// Every requirement satisfied. The first thing the nightly job asks, before
    /// anything is scored.
    static func meetsRequirements(_ a: [String: Int], _ b: [String: Int]) -> Bool {
        Questionnaire.requirements.allSatisfy { question in
            guard let i = a[question.id], let j = b[question.id] else { return false }
            return Requirement.allows(question.id, i, j)
        }
    }

    // MARK: Checking

    /// Square, symmetric, in range, and the right size for its question.
    ///
    /// Cheap to run and worth running, because a transposed digit in a grid is
    /// invisible by eye and quietly wrong forever.
    static var isConsistent: Bool {
        for table in tables {
            guard let question = Questionnaire.questions.first(where: { $0.id == table.questionID })
            else { return false }
            let n = question.options.count
            guard table.grid.count == n else { return false }
            for row in table.grid where row.count != n { return false }
            for i in 0..<n {
                for j in 0..<n {
                    let value = table.grid[i][j]
                    guard value >= 0, value <= 1 else { return false }
                    guard table.grid[i][j] == table.grid[j][i] else { return false }
                }
            }
        }
        return true
    }
}
