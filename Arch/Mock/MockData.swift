import Foundation

// MARK: - Models
//
// Plain value types with no view or framework dependencies, so the whole app can
// be pointed at real models later by changing only what feeds `MockData`.

struct Prompt: Identifiable, Hashable {
    let id: String
    let question: String
    let answer: String
}

struct Photo: Identifiable, Hashable {
    let id: String
    /// Index into `ArchColor.materials`. Mock data carries no colours of its own.
    let toneIndex: Int
}

/// Three short, self-written tags. Free text rather than a fixed list, because a
/// fixed list produces "Travel" and "Coffee" and Arch is built on people being
/// specific about themselves.
struct Interest: Identifiable, Hashable {
    let id: String
    let text: String

    /// Short enough to sit on one chip without wrapping.
    static let characterLimit = 24
}

/// The things in a profile you can react to.
///
/// Interests are deliberately **not** in here. This is the type the message
/// composer quotes, and it should only ever hold something you can write *about*.
/// A two-word tag is not a statement you can respond to.
enum ProfileItem: Identifiable, Hashable {
    case photo(Photo)
    case prompt(Prompt)

    var id: String {
        switch self {
        case .photo(let photo): return photo.id
        case .prompt(let prompt): return prompt.id
        }
    }
}

/// One row of the profile scroll *below* the lead photo, which both profile
/// screens render separately at full bleed.
///
/// This exists so the interests block has somewhere to live in the sequence
/// without being a `ProfileItem` — see the note on `ProfileItem` above.
enum ProfileRow: Identifiable, Hashable {
    case item(ProfileItem)
    case interests

    var id: String {
        switch self {
        case .item(let item): return item.id
        case .interests:      return "interests"
        }
    }
}

struct Person: Identifiable, Hashable {
    // `var` throughout: your own profile is edited in place by `ProfileStore`.
    // Other people's copies are never mutated — nothing hands them to a store.
    let id: String
    var name: String
    var age: Int
    var neighbourhood: String
    var city: String
    var height: String
    var work: String

    /// Ordered. `photos[0]` is the main photo — the one the roster shows — and
    /// reordering is the only way to change which that is.
    var photos: [Photo]
    /// Ordered. Up to three answers.
    var prompts: [Prompt]
    /// Up to three.
    var interests: [Interest]

    // MARK: Requirements

    static let photoLimit = 6
    /// Four is the floor for a live profile. Onboarding, the You tab and
    /// arrange mode all read this rather than each deciding for themselves.
    static let requiredPhotos = 4
    static let requiredPrompts = 3
    static let requiredInterests = 3

    // MARK: Derived

    /// Built in one place so no view joins these two fields its own way.
    var location: String { "\(neighbourhood), \(city)" }

    /// Four facts, in reading order. Wraps to two rows more often than not, since
    /// "Crown Heights, Brooklyn" is a wide chip.
    var vitals: [String] {
        ["\(age)", location, height, work]
    }

    var mainPhoto: Photo? { photos.first }

    /// Tone used for the avatar wherever the person appears in a list.
    var avatarToneIndex: Int { mainPhoto?.toneIndex ?? 0 }

    /// The display order of the profile scroll, derived rather than authored:
    /// photos and answers alternate, photo first, with any leftover photos
    /// appended. No view builds its own interleave.
    var items: [ProfileItem] {
        var result: [ProfileItem] = []
        var photoIndex = 0
        var promptIndex = 0

        while photoIndex < photos.count || promptIndex < prompts.count {
            if photoIndex < photos.count {
                result.append(.photo(photos[photoIndex]))
                photoIndex += 1
            }
            if promptIndex < prompts.count {
                result.append(.prompt(prompts[promptIndex]))
                promptIndex += 1
            }
        }
        return result
    }

    /// Where the interests block is drawn: immediately after the second photo.
    /// With fewer than two photos it falls to the end rather than disappearing.
    var interestsIndex: Int {
        var photosSeen = 0
        for (index, item) in items.enumerated() {
            if case .photo = item {
                photosSeen += 1
                if photosSeen == 2 { return index + 1 }
            }
        }
        return items.count
    }

    /// The scroll below the lead photo: every item except the first, with the
    /// interests block dropped in after the second photo.
    ///
    /// Both your profile and other people's read this, so neither can drift into
    /// its own ordering.
    var scrollRows: [ProfileRow] {
        let all = items
        guard !all.isEmpty else { return [.interests] }

        var rows: [ProfileRow] = []
        for (index, item) in all.enumerated() {
            // Index 0 is the lead photo, drawn full bleed above the scroll.
            if index > 0 { rows.append(.item(item)) }
            if index + 1 == interestsIndex { rows.append(.interests) }
        }
        return rows
    }

    // MARK: Completeness

    /// What the profile still needs, in plain words. Empty when it is finished.
    ///
    /// Deliberately a list of things rather than a number. "60% complete" is a
    /// score, and Arch does not show scores.
    /// Answers that actually say something.
    ///
    /// Onboarding seeds three empty prompts so `ProfileStore.updateAnswer` has
    /// somewhere to write, so counting `prompts` would report an untouched profile
    /// as finished.
    var answeredPrompts: [Prompt] {
        prompts.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var missing: [String] {
        shortfall(Self.requiredPhotos - photos.count, "photo", "photos")
            + shortfall(Self.requiredInterests - interests.count, "interest", "interests")
            + shortfall(Self.requiredPrompts - answeredPrompts.count, "answer", "answers")
    }

    private func shortfall(_ count: Int, _ singular: String, _ plural: String) -> [String] {
        guard count > 0 else { return [] }
        return [count == 1 ? "one more \(singular)" : "\(spelled(count)) more \(plural)"]
    }

    var isComplete: Bool { missing.isEmpty }

    /// Where onboarding starts. The three prompts are seeded empty so there is
    /// something to write answers into; `answeredPrompts` is what decides whether
    /// they count.
    static var empty: Person {
        Person(
            id: "you",
            name: "",
            age: 0,
            neighbourhood: "",
            city: "",
            height: "",
            work: "",
            photos: [],
            prompts: MockData.startingPrompts,
            interests: []
        )
    }

    private func spelled(_ value: Int) -> String {
        switch value {
        case 1: return "one"
        case 2: return "two"
        case 3: return "three"
        default: return "\(value)"
        }
    }
}

/// One of the five slots. There are always exactly five: a slot is either holding
/// someone or waiting for tomorrow. Nothing is ever "finished".
///
/// A slot says nothing about *why* it is empty. You dismissing someone and someone
/// dismissing you produce the identical state, because the app never tells you
/// which happened.
enum RosterSlot: Identifiable, Hashable {
    case filled(Person)
    case empty(id: String, refillsAt: Date)

    var id: String {
        switch self {
        case .filled(let person): return person.id
        case .empty(let id, _):   return id
        }
    }

    var person: Person? {
        if case .filled(let person) = self { return person }
        return nil
    }

    var refillsAt: Date? {
        if case .empty(_, let date) = self { return date }
        return nil
    }
}

/// The five slots. The roster is always five long; the screen draws the people
/// first and groups the open slots underneath.
struct Roster: Hashable {
    var slots: [RosterSlot]

    var people: [Person] { slots.compactMap(\.person) }
    var openSlots: [RosterSlot] { slots.filter { $0.person == nil } }
    var filledCount: Int { people.count }
    var capacity: Int { slots.count }
}

struct Message: Identifiable, Hashable {
    let id: String
    let text: String
    let isOutgoing: Bool
    let timestamp: String
}

struct Conversation: Identifiable, Hashable {
    let id: String
    let person: Person
    /// The photo or prompt the first message quoted, if it quoted one. Pinned to
    /// the top of the thread so neither person has to remember why they started.
    let opening: ProfileItem?
    let messages: [Message]
    let unreadCount: Int
    /// Pre-formatted for the list; a real build would format a Date here.
    let lastActivity: String

    var preview: String { messages.last?.text ?? "" }
}

struct PremiumBenefit: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
}

struct PremiumPlan: Identifiable, Hashable {
    let id: String
    let duration: String
    let total: String
    let perMonth: String
    let isRecommended: Bool
}

struct SettingsRow: Identifiable, Hashable {
    let id: String
    let title: String
    var detail: String?
    var control: SettingsControl = .push
}

struct SettingsSection: Identifiable, Hashable {
    let id: String
    let title: String
    let rows: [SettingsRow]
}

// MARK: - Content

enum MockData {

    // MARK: People

    static let people: [Person] = [nadia, teo, priya, marcus, lena, ines, dev]

    static let nadia = Person(
        id: "nadia",
        name: "Nadia",
        age: 29,
        neighbourhood: "Gowanus",
        city: "Brooklyn",
        height: "5 ft 7",
        work: "Structural engineer",
        photos: [
            Photo(id: "nadia-p1", toneIndex: 0),
            Photo(id: "nadia-p2", toneIndex: 3),
            Photo(id: "nadia-p3", toneIndex: 1),
            Photo(id: "nadia-p4", toneIndex: 5)
        ],
        prompts: [
            Prompt(
                id: "nadia-q1",
                question: "The last thing I read twice",
                answer: "A field guide to bridges I found in my grandad's garage. Half of it is tables of load limits and I still went back to the beginning."
            ),
            Prompt(
                id: "nadia-q2",
                question: "Where I go when I need to think",
                answer: "The walkway on the Manhattan Bridge, heading the unpopular direction so nobody is walking at me."
            ),
            Prompt(
                id: "nadia-q3",
                question: "Something I am slower at than everyone else",
                answer: "Ordering. I will read the entire menu twice and then get whatever you got."
            )
        ],
        interests: [
            Interest(id: "nadia-i1", text: "Bridge inspections"),
            Interest(id: "nadia-i2", text: "Long-distance walking"),
            Interest(id: "nadia-i3", text: "Brutalist car parks")
        ]
    )

    static let teo = Person(
        id: "teo",
        name: "Teo",
        age: 33,
        neighbourhood: "Ridgewood",
        city: "Queens",
        height: "6 ft",
        work: "Pastry cook",
        photos: [
            Photo(id: "teo-p1", toneIndex: 4),
            Photo(id: "teo-p2", toneIndex: 2),
            Photo(id: "teo-p3", toneIndex: 0),
            Photo(id: "teo-p4", toneIndex: 3)
        ],
        prompts: [
            Prompt(
                id: "teo-q1",
                question: "A thing I have changed my mind about",
                answer: "That working nights was temporary. It has been four years and I have stopped apologising for being awake at three."
            ),
            Prompt(
                id: "teo-q2",
                question: "The best argument I have lost",
                answer: "My sister spent an entire drive to Hudson convincing me that sourdough is mostly theatre. She is right. I have kept doing it anyway."
            ),
            Prompt(
                id: "teo-q3",
                question: "Where I go when I need to think",
                answer: "The all-night laundromat on Fresh Pond. Warm, and loud in a way that is not people talking to you."
            )
        ],
        interests: [
            Interest(id: "teo-i1", text: "Night baking"),
            Interest(id: "teo-i2", text: "Laundromats"),
            Interest(id: "teo-i3", text: "Dulce de leche")
        ]
    )

    static let priya = Person(
        id: "priya",
        name: "Priya",
        age: 27,
        neighbourhood: "Crown Heights",
        city: "Brooklyn",
        height: "5 ft 4",
        work: "Restores film cameras",
        photos: [
            Photo(id: "priya-p1", toneIndex: 2),
            Photo(id: "priya-p2", toneIndex: 5),
            Photo(id: "priya-p3", toneIndex: 1),
            Photo(id: "priya-p4", toneIndex: 4)
        ],
        prompts: [
            Prompt(
                id: "priya-q1",
                question: "Something I am slower at than everyone else",
                answer: "Replying. It is not avoidance. I write the message, put the phone down, and find it three days later still sitting there."
            ),
            Prompt(
                id: "priya-q2",
                question: "The last thing I read twice",
                answer: "The service manual for a Rolleiflex, in German, which I do not read. The exploded diagrams are enough."
            ),
            Prompt(
                id: "priya-q3",
                question: "A thing I have changed my mind about",
                answer: "Digital. I was insufferable about it for about six years. Now I mostly want the picture."
            )
        ],
        interests: [
            Interest(id: "priya-i1", text: "Rolleiflex repair"),
            Interest(id: "priya-i2", text: "Darkroom printing"),
            Interest(id: "priya-i3", text: "German manuals")
        ]
    )

    static let marcus = Person(
        id: "marcus",
        name: "Marcus",
        age: 31,
        neighbourhood: "Bed-Stuy",
        city: "Brooklyn",
        height: "5 ft 11",
        work: "Nurse, emergency",
        photos: [
            Photo(id: "marcus-p1", toneIndex: 1),
            Photo(id: "marcus-p2", toneIndex: 4),
            Photo(id: "marcus-p3", toneIndex: 3),
            Photo(id: "marcus-p4", toneIndex: 0)
        ],
        prompts: [
            Prompt(
                id: "marcus-q1",
                question: "Where I go when I need to think",
                answer: "Prospect Park at eight in the morning after a shift, when it is only dog people and me, all of us quiet."
            ),
            Prompt(
                id: "marcus-q2",
                question: "A thing I have changed my mind about",
                answer: "That I would get used to it. You do not. You get better at leaving it at the door, which is a different skill."
            ),
            Prompt(
                id: "marcus-q3",
                question: "The best argument I have lost",
                answer: "A patient's grandmother explained that I was holding a mop wrong. She had cleaned offices for forty years. I hold it her way now."
            )
        ],
        interests: [
            Interest(id: "marcus-i1", text: "Dawn in Prospect Park"),
            Interest(id: "marcus-i2", text: "Mop technique"),
            Interest(id: "marcus-i3", text: "Sleeping through noise")
        ]
    )

    static let lena = Person(
        id: "lena",
        name: "Lena",
        age: 30,
        neighbourhood: "Bushwick",
        city: "Brooklyn",
        height: "5 ft 9",
        work: "Translator",
        photos: [
            Photo(id: "lena-p1", toneIndex: 5),
            Photo(id: "lena-p2", toneIndex: 0),
            Photo(id: "lena-p3", toneIndex: 2),
            Photo(id: "lena-p4", toneIndex: 1)
        ],
        prompts: [
            Prompt(
                id: "lena-q1",
                question: "Something I am slower at than everyone else",
                answer: "Jokes in English. I get there, about four seconds after the table has moved on to something else."
            ),
            Prompt(
                id: "lena-q2",
                question: "The last thing I read twice",
                answer: "A translation of a poem I already knew in Portuguese, to see what the translator gave up. Quite a lot, it turns out."
            ),
            Prompt(
                id: "lena-q3",
                question: "Where I go when I need to think",
                answer: "The Q platform at Kings Highway. It is above ground, so you can watch weather arrive from a long way off."
            )
        ],
        interests: [
            Interest(id: "lena-i1", text: "Untranslatable tenses"),
            Interest(id: "lena-i2", text: "Above-ground platforms"),
            Interest(id: "lena-i3", text: "Portuguese poetry")
        ]
    )

    static let hana = Person(
        id: "hana",
        name: "Hana",
        age: 28,
        neighbourhood: "Greenpoint",
        city: "Brooklyn",
        height: "5 ft 6",
        work: "Landscape architect",
        photos: [Photo(id: "hana-p1", toneIndex: 2)],
        prompts: [
            Prompt(
                id: "hana-q1",
                question: "A thing I have changed my mind about",
                answer: "Lawns. I spent a degree learning to hate them and now I just think about who has to mow it."
            )
        ],
        interests: [
            Interest(id: "hana-i1", text: "Street trees"),
            Interest(id: "hana-i2", text: "Drainage"),
            Interest(id: "hana-i3", text: "Chairs outdoors")
        ]
    )


    static let ines = Person(
        id: "ines",
        name: "Ines",
        age: 32,
        neighbourhood: "Sunset Park",
        city: "Brooklyn",
        height: "5 ft 5",
        work: "Bookbinder",
        photos: [
            Photo(id: "ines-p1", toneIndex: 1),
            Photo(id: "ines-p2", toneIndex: 4),
            Photo(id: "ines-p3", toneIndex: 0),
            Photo(id: "ines-p4", toneIndex: 2)
        ],
        prompts: [
            Prompt(
                id: "ines-q1",
                question: "The last thing I made with my hands",
                answer: "A slipcase for a book that did not deserve one. Nine hours, and I would do it again."
            ),
            Prompt(
                id: "ines-q2",
                question: "Something I do that takes far too long",
                answer: "Choosing paper. I have stood in the same aisle for forty minutes and left with nothing."
            ),
            Prompt(
                id: "ines-q3",
                question: "A thing I am probably wrong about",
                answer: "That anything worth keeping should be physical. I say it constantly and my phone is always in my hand."
            )
        ],
        interests: [
            Interest(id: "ines-i1", text: "Japanese paper"),
            Interest(id: "ines-i2", text: "Cloth spines"),
            Interest(id: "ines-i3", text: "Repairs that take months")
        ]
    )

    static let dev = Person(
        id: "dev",
        name: "Dev",
        age: 29,
        neighbourhood: "Astoria",
        city: "Queens",
        height: "6 ft 1",
        work: "Bus mechanic",
        photos: [
            Photo(id: "dev-p1", toneIndex: 3),
            Photo(id: "dev-p2", toneIndex: 5),
            Photo(id: "dev-p3", toneIndex: 2),
            Photo(id: "dev-p4", toneIndex: 1)
        ],
        prompts: [
            Prompt(
                id: "dev-q1",
                question: "What I would happily explain for an hour",
                answer: "Why the articulated buses bend where they do, and why almost everyone guesses it wrong."
            ),
            Prompt(
                id: "dev-q2",
                question: "Where I go when I need to think",
                answer: "The depot at four in the morning, before anyone is in. Sixty buses and no noise at all."
            ),
            Prompt(
                id: "dev-q3",
                question: "A risk that worked out",
                answer: "Turning down the desk job my parents wanted for me. It took about six years to stop being an argument."
            )
        ],
        interests: [
            Interest(id: "dev-i1", text: "Articulated buses"),
            Interest(id: "dev-i2", text: "Four in the morning"),
            Interest(id: "dev-i3", text: "Engine noise")
        ]
    )

    // MARK: Your own profile

    /// A finished profile: six photos, three answers, three interests.
    static let you = Person(
        id: "you",
        name: "Sam",
        age: 30,
        neighbourhood: "Fort Greene",
        city: "Brooklyn",
        height: "5 ft 10",
        work: "Sound engineer",
        photos: [
            Photo(id: "you-p1", toneIndex: 3),
            Photo(id: "you-p2", toneIndex: 1),
            Photo(id: "you-p3", toneIndex: 4),
            Photo(id: "you-p4", toneIndex: 0),
            Photo(id: "you-p5", toneIndex: 2),
            Photo(id: "you-p6", toneIndex: 5)
        ],
        prompts: [
            Prompt(
                id: "you-q1",
                question: "Where I go when I need to think",
                answer: "The bench at the top of the hill in Fort Greene Park, early, before the tennis courts start up."
            ),
            Prompt(
                id: "you-q2",
                question: "Something I am slower at than everyone else",
                answer: "Leaving. I will say goodbye at the door and still be there twenty minutes later, coat on."
            ),
            Prompt(
                id: "you-q3",
                question: "The best argument I have lost",
                answer: "A drummer once explained why the click track was not the problem. It was me. It was me for about a year."
            )
        ],
        interests: [
            Interest(id: "you-i1", text: "Room tone"),
            Interest(id: "you-i2", text: "Click tracks"),
            Interest(id: "you-i3", text: "Fort Greene Park")
        ]
    )

    /// The same profile part-way through being filled in — four photos, two
    /// answers, two interests. Drives the incomplete state of the You tab.
    static let youIncomplete = Person(
        id: "you",
        name: "Sam",
        age: 30,
        neighbourhood: "Fort Greene",
        city: "Brooklyn",
        height: "5 ft 10",
        work: "Sound engineer",
        photos: Array(you.photos.prefix(3)),
        prompts: Array(you.prompts.prefix(2)),
        interests: Array(you.interests.prefix(2))
    )

    // MARK: Roster states

    // Refill times are relative so the previews always read sensibly. A real build
    // would take these from the server.
    private static func hours(_ count: Double) -> Date {
        Date().addingTimeInterval(count * 3600)
    }

    /// Five people, no gaps. The arch holds.
    ///
    /// Nobody here is somebody you have written to — writing to someone is what
    /// takes them out of your five. Hana is the exception that shows the rule:
    /// she wrote first, so your slot is untouched and she is still in it.
    static let rosterFull = Roster(slots: [
        .filled(priya), .filled(marcus), .filled(hana), .filled(ines), .filled(dev)
    ])

    /// A subscriber's roster: six slots rather than five. The arch draws six
    /// voussoirs, so the indicator generalises without a second design.
    static let rosterPremium = Roster(slots: [
        .filled(priya), .filled(marcus), .filled(hana),
        .filled(ines), .filled(dev),
        .empty(id: "slot-6", refillsAt: hours(14))
    ])

    /// Three people and two open slots, refilling at different times.
    static let rosterPartial = Roster(slots: [
        .filled(priya),
        .filled(ines),
        .filled(dev),
        .empty(id: "slot-4", refillsAt: hours(14)),
        .empty(id: "slot-5", refillsAt: hours(38))
    ])

    /// One person, four open slots. The state that has to look intentional rather
    /// than broken — the outlined stones keep the arch legible, and the open slots
    /// are quieter than the person, not louder.
    static let rosterNearlyEmpty = Roster(slots: [
        .filled(dev),
        .empty(id: "slot-2", refillsAt: hours(14)),
        .empty(id: "slot-3", refillsAt: hours(14)),
        .empty(id: "slot-4", refillsAt: hours(38)),
        .empty(id: "slot-5", refillsAt: hours(62))
    ])

    // MARK: Messages

    static let conversations: [Conversation] = [
        Conversation(
            id: "c-nadia",
            person: nadia,
            opening: .prompt(nadia.prompts[0]),
            messages: [
                Message(id: "m1", text: "The load limit tables. That is the part that got you back to the start?", isOutgoing: true, timestamp: "Tuesday"),
                Message(id: "m2", text: "It is the only honest writing in the whole book. Everything else is a photograph of a bridge with a paragraph telling you it is beautiful.", isOutgoing: false, timestamp: "Tuesday"),
                Message(id: "m3", text: "Fair. Do you have a favourite one in the city or is that like asking about children", isOutgoing: true, timestamp: "Tuesday"),
                Message(id: "m4", text: "Hell Gate. Nobody walks it, nobody photographs it, it just quietly holds up trains. I will take you to look at it from underneath if you want, which is a sentence I hear as I type it.", isOutgoing: false, timestamp: "9:14")
            ],
            unreadCount: 1,
            lastActivity: "9:14"
        ),
        Conversation(
            id: "c-teo",
            person: teo,
            opening: .prompt(teo.prompts[2]),
            messages: [
                Message(id: "m5", text: "A laundromat is a genuinely good answer and I am annoyed I did not think of it", isOutgoing: true, timestamp: "Monday"),
                Message(id: "m6", text: "It is the last indoor place you can sit for an hour without buying anything.", isOutgoing: false, timestamp: "Monday"),
                Message(id: "m7", text: "Well now I want to know your second-best one", isOutgoing: true, timestamp: "Monday")
            ],
            unreadCount: 0,
            lastActivity: "Monday"
        ),
        Conversation(
            id: "c-lena",
            person: lena,
            opening: .prompt(lena.prompts[1]),
            messages: [
                Message(id: "m8", text: "What did the translator give up", isOutgoing: true, timestamp: "Sunday"),
                Message(id: "m9", text: "The tense. Portuguese has one that means something happened and is still happening to you. English makes you pick.", isOutgoing: false, timestamp: "Sunday"),
                Message(id: "m10", text: "That is going to bother me all week", isOutgoing: true, timestamp: "Sunday"),
                Message(id: "m11", text: "Good.", isOutgoing: false, timestamp: "Sunday")
            ],
            unreadCount: 0,
            lastActivity: "Sunday"
        ),
        Conversation(
            id: "c-hana",
            person: hana,
            opening: .prompt(hana.prompts[0]),
            messages: [
                Message(id: "m12", text: "Thursday still good?", isOutgoing: false, timestamp: "Last week"),
                Message(id: "m13", text: "Thursday is good. I will find somewhere with chairs outside.", isOutgoing: true, timestamp: "Last week")
            ],
            unreadCount: 0,
            lastActivity: "Last week"
        )
    ]

    static var unreadCount: Int {
        conversations.reduce(0) { $0 + $1.unreadCount }
    }

    // MARK: Premium

    // Premium changes what you can do with your slots and what you can say about
    // yourself. It does not buy you scores, rankings, or anything about who has
    // looked at you — none of which exist in Arch.
    static let premiumBenefits: [PremiumBenefit] = [
        PremiumBenefit(
            id: "b1",
            title: "Refill a slot today",
            detail: "Fill an open slot straight away instead of waiting for tomorrow."
        ),
        PremiumBenefit(
            id: "b2",
            title: "A sixth slot",
            detail: "Hold six people at once instead of five."
        ),
        PremiumBenefit(
            id: "b3",
            title: "Tips for your profile",
            detail: "Specific notes on your photos and answers, and what to change."
        ),
        PremiumBenefit(
            id: "b4",
            title: "Six prompts instead of three",
            detail: "More room to be specific about yourself."
        ),
        PremiumBenefit(
            id: "b5",
            title: "Finer preferences",
            detail: "Choose who reaches you on the things you actually care about, not only distance and age."
        )
    ]

    static let premiumPlans: [PremiumPlan] = [
        PremiumPlan(id: "p1", duration: "One month", total: "$24.99", perMonth: "$24.99 a month", isRecommended: false),
        PremiumPlan(id: "p3", duration: "Three months", total: "$53.97", perMonth: "$17.99 a month", isRecommended: true),
        PremiumPlan(id: "p12", duration: "Twelve months", total: "$143.88", perMonth: "$11.99 a month", isRecommended: false)
    ]

    static let premiumFootnote = "Payment is charged to your Apple account. Renews until you cancel, which you can do in Settings."

    // MARK: Onboarding

    /// The three a new profile starts on. They are a starting point, not an
    /// assignment — every one can be swapped during onboarding or afterwards.
    static let startingPrompts: [Prompt] = PromptLibrary.starting.enumerated().map { index, question in
        Prompt(id: "you-q\(index + 1)", question: question.text, answer: "")
    }

    static let onboardingHeadline = "Five people a day"
    static let onboardingBody = "Every morning Arch picks five people it thinks you would actually like. You read them properly, you decide, and then you are done until tomorrow."
}
