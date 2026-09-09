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

/// A profile is a single vertical scroll of alternating photos and written prompts.
/// You react to one of these, not to the person as a whole.
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

struct Person: Identifiable, Hashable {
    let id: String
    let name: String
    let age: Int
    let neighbourhood: String
    let height: String
    let work: String
    let items: [ProfileItem]

    /// Small chips near the top of the profile, in reading order.
    var vitals: [String] {
        ["\(age)", neighbourhood, height, work]
    }

    var photos: [Photo] {
        items.compactMap { if case .photo(let photo) = $0 { return photo } else { return nil } }
    }

    var prompts: [Prompt] {
        items.compactMap { if case .prompt(let prompt) = $0 { return prompt } else { return nil } }
    }

    /// Tone used for the avatar wherever the person appears in a list.
    var avatarToneIndex: Int { photos.first?.toneIndex ?? 0 }
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
    /// The photo or prompt the first like landed on. Pinned to the top of the
    /// thread so neither person has to remember why they are talking.
    let opening: ProfileItem
    let messages: [Message]
    let unreadCount: Int
    /// Pre-formatted for the list; a real build would format a Date here.
    let lastActivity: String

    var isNew: Bool { messages.isEmpty }
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
    let detail: String?
}

struct SettingsSection: Identifiable, Hashable {
    let id: String
    let title: String
    let rows: [SettingsRow]
}

// MARK: - Content

enum MockData {

    // MARK: Today's five

    static let people: [Person] = [nadia, teo, priya, marcus, lena]

    static let nadia = Person(
        id: "nadia",
        name: "Nadia",
        age: 29,
        neighbourhood: "Gowanus",
        height: "5 ft 7",
        work: "Structural engineer",
        items: [
            .photo(Photo(id: "nadia-p1", toneIndex: 0)),
            .prompt(Prompt(
                id: "nadia-q1",
                question: "The last thing I read twice",
                answer: "A field guide to bridges I found in my grandad's garage. Half of it is tables of load limits and I still went back to the beginning."
            )),
            .photo(Photo(id: "nadia-p2", toneIndex: 3)),
            .prompt(Prompt(
                id: "nadia-q2",
                question: "Where I go when I need to think",
                answer: "The walkway on the Manhattan Bridge, heading the unpopular direction so nobody is walking at me."
            )),
            .photo(Photo(id: "nadia-p3", toneIndex: 1)),
            .prompt(Prompt(
                id: "nadia-q3",
                question: "Something I am slower at than everyone else",
                answer: "Ordering. I will read the entire menu twice and then get whatever you got."
            )),
            .photo(Photo(id: "nadia-p4", toneIndex: 5))
        ]
    )

    static let teo = Person(
        id: "teo",
        name: "Teo",
        age: 33,
        neighbourhood: "Ridgewood",
        height: "6 ft",
        work: "Pastry cook",
        items: [
            .photo(Photo(id: "teo-p1", toneIndex: 4)),
            .prompt(Prompt(
                id: "teo-q1",
                question: "A thing I have changed my mind about",
                answer: "That working nights was temporary. It has been four years and I have stopped apologising for being awake at three."
            )),
            .photo(Photo(id: "teo-p2", toneIndex: 2)),
            .prompt(Prompt(
                id: "teo-q2",
                question: "The best argument I have lost",
                answer: "My sister spent an entire drive to Hudson convincing me that sourdough is mostly theatre. She is right. I have kept doing it anyway."
            )),
            .photo(Photo(id: "teo-p3", toneIndex: 0)),
            .prompt(Prompt(
                id: "teo-q3",
                question: "Where I go when I need to think",
                answer: "The all-night laundromat on Fresh Pond. Warm, and loud in a way that is not people talking to you."
            )),
            .photo(Photo(id: "teo-p4", toneIndex: 3))
        ]
    )

    static let priya = Person(
        id: "priya",
        name: "Priya",
        age: 27,
        neighbourhood: "Crown Heights",
        height: "5 ft 4",
        work: "Restores film cameras",
        items: [
            .photo(Photo(id: "priya-p1", toneIndex: 2)),
            .prompt(Prompt(
                id: "priya-q1",
                question: "Something I am slower at than everyone else",
                answer: "Replying. It is not avoidance. I write the message, put the phone down, and find it three days later still sitting there."
            )),
            .photo(Photo(id: "priya-p2", toneIndex: 5)),
            .prompt(Prompt(
                id: "priya-q2",
                question: "The last thing I read twice",
                answer: "The service manual for a Rolleiflex, in German, which I do not read. The exploded diagrams are enough."
            )),
            .photo(Photo(id: "priya-p3", toneIndex: 1)),
            .prompt(Prompt(
                id: "priya-q3",
                question: "A thing I have changed my mind about",
                answer: "Digital. I was insufferable about it for about six years. Now I mostly want the picture."
            )),
            .photo(Photo(id: "priya-p4", toneIndex: 4))
        ]
    )

    static let marcus = Person(
        id: "marcus",
        name: "Marcus",
        age: 31,
        neighbourhood: "Bed-Stuy",
        height: "5 ft 11",
        work: "Nurse, emergency",
        items: [
            .photo(Photo(id: "marcus-p1", toneIndex: 1)),
            .prompt(Prompt(
                id: "marcus-q1",
                question: "Where I go when I need to think",
                answer: "Prospect Park at eight in the morning after a shift, when it is only dog people and me, all of us quiet."
            )),
            .photo(Photo(id: "marcus-p2", toneIndex: 4)),
            .prompt(Prompt(
                id: "marcus-q2",
                question: "A thing I have changed my mind about",
                answer: "That I would get used to it. You do not. You get better at leaving it at the door, which is a different skill."
            )),
            .photo(Photo(id: "marcus-p3", toneIndex: 3)),
            .prompt(Prompt(
                id: "marcus-q3",
                question: "The best argument I have lost",
                answer: "A patient's grandmother explained that I was holding a mop wrong. She had cleaned offices for forty years. I hold it her way now."
            )),
            .photo(Photo(id: "marcus-p4", toneIndex: 0))
        ]
    )

    static let lena = Person(
        id: "lena",
        name: "Lena",
        age: 30,
        neighbourhood: "Bushwick",
        height: "5 ft 9",
        work: "Translator",
        items: [
            .photo(Photo(id: "lena-p1", toneIndex: 5)),
            .prompt(Prompt(
                id: "lena-q1",
                question: "Something I am slower at than everyone else",
                answer: "Jokes in English. I get there, about four seconds after the table has moved on to something else."
            )),
            .photo(Photo(id: "lena-p2", toneIndex: 0)),
            .prompt(Prompt(
                id: "lena-q2",
                question: "The last thing I read twice",
                answer: "A translation of a poem I already knew in Portuguese, to see what the translator gave up. Quite a lot, it turns out."
            )),
            .photo(Photo(id: "lena-p3", toneIndex: 2)),
            .prompt(Prompt(
                id: "lena-q3",
                question: "Where I go when I need to think",
                answer: "The Q platform at Kings Highway. It is above ground, so you can watch weather arrive from a long way off."
            )),
            .photo(Photo(id: "lena-p4", toneIndex: 1))
        ]
    )

    // MARK: Your own profile

    static let you = Person(
        id: "you",
        name: "Sam",
        age: 30,
        neighbourhood: "Fort Greene",
        height: "5 ft 10",
        work: "Sound engineer",
        items: [
            .photo(Photo(id: "you-p1", toneIndex: 3)),
            .prompt(Prompt(
                id: "you-q1",
                question: "Where I go when I need to think",
                answer: "The bench at the top of the hill in Fort Greene Park, early, before the tennis courts start up."
            )),
            .photo(Photo(id: "you-p2", toneIndex: 1)),
            .prompt(Prompt(
                id: "you-q2",
                question: "Something I am slower at than everyone else",
                answer: "Leaving. I will say goodbye at the door and still be there twenty minutes later, coat on."
            )),
            .photo(Photo(id: "you-p3", toneIndex: 4)),
            .prompt(Prompt(
                id: "you-q3",
                question: "The best argument I have lost",
                answer: "A drummer once explained why the click track was not the problem. It was me. It was me for about a year."
            )),
            .photo(Photo(id: "you-p4", toneIndex: 0))
        ]
    )

    // MARK: Connections and messages

    /// People you have connected with but not yet written to.
    static let newConnections: [Conversation] = [
        Conversation(
            id: "c-priya",
            person: priya,
            opening: priya.items[3],
            messages: [],
            unreadCount: 0,
            lastActivity: "Connected today"
        ),
        Conversation(
            id: "c-marcus",
            person: marcus,
            opening: marcus.items[1],
            messages: [],
            unreadCount: 0,
            lastActivity: "Connected yesterday"
        )
    ]

    static let conversations: [Conversation] = [
        Conversation(
            id: "c-nadia",
            person: nadia,
            opening: nadia.items[1],
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
            opening: teo.items[5],
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
            opening: lena.items[3],
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
            id: "c-old",
            person: Person(
                id: "hana",
                name: "Hana",
                age: 28,
                neighbourhood: "Greenpoint",
                height: "5 ft 6",
                work: "Landscape architect",
                items: [
                    .photo(Photo(id: "hana-p1", toneIndex: 2)),
                    .prompt(Prompt(
                        id: "hana-q1",
                        question: "A thing I have changed my mind about",
                        answer: "Lawns. I spent a degree learning to hate them and now I just think about who has to mow it."
                    ))
                ]
            ),
            opening: .prompt(Prompt(
                id: "hana-q1",
                question: "A thing I have changed my mind about",
                answer: "Lawns. I spent a degree learning to hate them and now I just think about who has to mow it."
            )),
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

    static let premiumBenefits: [PremiumBenefit] = [
        PremiumBenefit(
            id: "b1",
            title: "See who liked you",
            detail: "The people who set a stone on your profile, before they come up in your day."
        ),
        PremiumBenefit(
            id: "b2",
            title: "Reopen yesterday",
            detail: "Go back through yesterday's five once, for the one you moved past too quickly."
        ),
        PremiumBenefit(
            id: "b3",
            title: "Six prompts instead of three",
            detail: "More room to be specific about yourself."
        ),
        PremiumBenefit(
            id: "b4",
            title: "Finer preferences",
            detail: "Choose your five on the things you actually care about, not only distance and age."
        )
    ]

    static let premiumPlans: [PremiumPlan] = [
        PremiumPlan(id: "p1", duration: "One month", total: "$24.99", perMonth: "$24.99 a month", isRecommended: false),
        PremiumPlan(id: "p3", duration: "Three months", total: "$53.97", perMonth: "$17.99 a month", isRecommended: true),
        PremiumPlan(id: "p12", duration: "Twelve months", total: "$143.88", perMonth: "$11.99 a month", isRecommended: false)
    ]

    static let premiumFootnote = "Payment is charged to your Apple account. Renews until you cancel, which you can do in Settings."

    // MARK: Settings

    static let settingsSections: [SettingsSection] = [
        SettingsSection(id: "s1", title: "Account", rows: [
            SettingsRow(id: "s1r1", title: "Phone number", detail: "+1 (917) 555 0142"),
            SettingsRow(id: "s1r2", title: "Email", detail: "sam@example.com"),
            SettingsRow(id: "s1r3", title: "Arch Premium", detail: "Not subscribed")
        ]),
        SettingsSection(id: "s2", title: "Notifications", rows: [
            SettingsRow(id: "s2r1", title: "Your daily five", detail: "9:00"),
            SettingsRow(id: "s2r2", title: "New connections", detail: "On"),
            SettingsRow(id: "s2r3", title: "Messages", detail: "On")
        ]),
        SettingsSection(id: "s3", title: "Discovery", rows: [
            SettingsRow(id: "s3r1", title: "Distance", detail: "Within 10 miles"),
            SettingsRow(id: "s3r2", title: "Age range", detail: "26 to 36"),
            SettingsRow(id: "s3r3", title: "Looking for", detail: "Something serious"),
            SettingsRow(id: "s3r4", title: "Pause my profile", detail: nil)
        ]),
        SettingsSection(id: "s4", title: "Privacy", rows: [
            SettingsRow(id: "s4r1", title: "Who can see me", detail: nil),
            SettingsRow(id: "s4r2", title: "Blocked people", detail: "None"),
            SettingsRow(id: "s4r3", title: "Download your data", detail: nil)
        ]),
        SettingsSection(id: "s5", title: "Help", rows: [
            SettingsRow(id: "s5r1", title: "How Arch works", detail: nil),
            SettingsRow(id: "s5r2", title: "Safety", detail: nil),
            SettingsRow(id: "s5r3", title: "Contact us", detail: nil)
        ])
    ]

    // MARK: Onboarding

    static let onboardingHeadline = "Five people a day"
    static let onboardingBody = "Every morning Arch picks five people it thinks you would actually like. You read them properly, you decide, and then you are done until tomorrow."
}
