import Foundation

/// Everything the app asks the server for, in one place.
///
/// The stores talk to this and never to `SupabaseClient` directly. That keeps the
/// PostgREST filter syntax — `eq.`, `in.`, `select=a,b,c` — out of the feature code,
/// and it means the whole surface the app depends on is one file long, which is
/// what makes it reviewable.
///
/// Every method here is `async throws`. Nothing retries on its own: a failed load
/// is shown as a state the reader can act on, and a failed send is kept and offered
/// again. Silent retries make an app that seems to work and loses things.
enum ArchBackend {

    // MARK: Account

    /// The signed-in account, or nil if there is no session.
    ///
    /// This is also the removal check: a removed account still has a valid session,
    /// because being removed is not the same as being signed out, and the screen
    /// that says so needs to know who it is talking to.
    static func account() async throws -> AccountRow? {
        guard let session = await SupabaseClient.shared.restore() else { return nil }
        return try await SupabaseClient.shared.selectOne(
            "accounts",
            columns: "id,status,apple_email",
            filters: ["id": "eq.\(session.userID)"]
        )
    }

    static func removal() async throws -> RemovalRow? {
        let rows: [RemovalRow] = try await SupabaseClient.shared.select(
            "removals",
            columns: "id,kind,reason,until",
            order: "created_at.desc",
            limit: 1
        )
        return rows.first
    }

    static func appeal(removalID: String, body: String) async throws {
        struct NewAppeal: Encodable {
            let removalId: String
            let body: String
        }
        try await SupabaseClient.shared.insert(
            "appeals", NewAppeal(removalId: removalID, body: body)
        )
    }

    // MARK: Your own profile

    static func ownProfile() async throws -> Person? {
        guard let session = await SupabaseClient.shared.restore() else { return nil }
        let me = session.userID

        async let profile: OwnProfileRow? = SupabaseClient.shared.selectOne(
            "profiles", filters: ["account_id": "eq.\(me)"]
        )
        async let photos: [PhotoRow] = SupabaseClient.shared.select(
            "photos", filters: ["account_id": "eq.\(me)"], order: "position.asc"
        )
        async let prompts: [PromptRow] = SupabaseClient.shared.select(
            "profile_prompts", filters: ["account_id": "eq.\(me)"], order: "position.asc"
        )
        async let interests: [InterestRow] = SupabaseClient.shared.select(
            "profile_interests", filters: ["account_id": "eq.\(me)"], order: "position.asc"
        )

        // Each `async let` is awaited into its own binding first. Writing
        // `try await photos.map { ... }` inline reads as awaiting the *result of
        // the map* rather than the binding, which is not what is meant and not
        // reliably what it compiles to.
        guard let row = try await profile else { return nil }
        let photoRows = try await photos
        let promptRows = try await prompts
        let interestRows = try await interests

        return Person(
            id: row.accountId,
            name: row.name,
            age: ArchUnits.age(fromBirthdate: row.birthdate),
            place: PlaceLibrary.place(matching: row.placeId),
            coordinate: Coordinate(latitude: row.coarseLat, longitude: row.coarseLon),
            height: ArchUnits.height(fromCentimetres: row.heightCm),
            work: row.work ?? "",
            gender: ArchUnits.gender(fromColumn: row.gender),
            pronouns: row.pronouns ?? "",
            photos: photoRows.enumerated().map { Photo(id: $1.id, toneIndex: $0) },
            prompts: promptRows.map {
                Prompt(id: $0.id,
                       question: PromptLibrary.text(forID: $0.promptKey),
                       answer: $0.answer)
            },
            interests: interestRows.map { Interest(id: $0.id, text: $0.text) }
        )
    }

    /// Saves the fields the details sheet edits.
    ///
    /// Age becomes a birthdate on the way down, because the database stores the
    /// date and derives the age — otherwise everybody's age would be whatever it
    /// was on the day they typed it.
    static func saveDetails(_ details: PersonDetails) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        guard let gender = details.gender else { throw ArchAPIError.conflict }
        guard let place = details.place else { throw ArchAPIError.conflict }

        struct Update: Encodable {
            let name: String
            let birthdate: String
            let gender: String
            let pronouns: String?
            let placeId: String
            let coarseLat: Double
            let coarseLon: Double
            let heightCm: Int?
            let work: String?
        }

        // Coarsened before it leaves the phone, not after it arrives. The precise
        // fix is used to pick the square and is then gone; the CHECK constraint on
        // the column refuses anything finer, so this is belt and braces on purpose.
        let centre = place.centre.coarsened

        try await SupabaseClient.shared.update(
            "profiles",
            Update(
                name: details.name,
                birthdate: ArchUnits.birthdate(fromAge: details.age),
                gender: ArchUnits.genderColumn(gender),
                pronouns: details.pronouns.isEmpty ? nil : details.pronouns,
                placeId: place.id,
                coarseLat: centre.latitude,
                coarseLon: centre.longitude,
                heightCm: ArchUnits.centimetres(fromHeight: details.height),
                work: details.work.isEmpty ? nil : details.work
            ),
            filters: ["account_id": "eq.\(session.userID)"]
        )
    }

    /// The sixteen answers, written once at the end of onboarding.
    ///
    /// Sent as one upsert rather than sixteen inserts so that a connection dropping
    /// halfway cannot leave somebody with a half-answered questionnaire that the
    /// matcher would then score against everybody.
    static func saveAnswers(_ answers: [String: Int]) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        struct AnswerRow: Encodable {
            let accountId: String
            let questionId: String
            let optionIndex: Int
        }
        let rows = answers.sorted { $0.key < $1.key }.map {
            AnswerRow(accountId: session.userID, questionId: $0.key, optionIndex: $0.value)
        }
        try await SupabaseClient.shared.upsert("questionnaire_answers", rows)
    }

    // MARK: The roster

    /// Today's five, or seven.
    ///
    /// One request, with the profile, photos, prompts and interests embedded —
    /// PostgREST can follow the foreign keys, and a request per slot would be five
    /// round trips on a phone that may be on a train.
    ///
    /// **No score comes back.** `pairings.score` exists for tuning the matcher and
    /// is deliberately not selected: Arch shows no percentages and no ranking, and a
    /// number on the wire ends up on a screen eventually.
    static func roster() async throws -> [Person] {
        guard let session = await SupabaseClient.shared.restore() else { return [] }
        let me = session.userID

        let rows: [PairingRow] = try await SupabaseClient.shared.select(
            "pairings",
            columns: "id,night,lo_account,hi_account",
            filters: ["night": "eq.\(ArchClock.today())"],
            order: "created_at.asc"
        )
        let others = rows.map { $0.other(than: me) }
        guard !others.isEmpty else { return [] }

        // Anybody this person has already dismissed is gone from their own roster
        // and nobody else's. The other side is never told.
        let dismissed: [DismissalRow] = try await SupabaseClient.shared.select(
            "dismissals",
            columns: "other_account_id",
            filters: ["account_id": "eq.\(me)", "night": "eq.\(ArchClock.today())"]
        )
        let hidden = Set(dismissed.map(\.otherAccountId))

        return try await people(ids: others.filter { !hidden.contains($0) })
    }

    /// Profiles for a set of accounts, with everything a card needs.
    static func people(ids: [String]) async throws -> [Person] {
        guard !ids.isEmpty else { return [] }
        let list = "in.(\(ids.joined(separator: ",")))"

        async let profiles: [ProfileRow] = SupabaseClient.shared.select(
            "visible_profiles", filters: ["account_id": list]
        )
        async let photos: [PhotoRow] = SupabaseClient.shared.select(
            "photos", filters: ["account_id": list, "state": "eq.approved"],
            order: "position.asc"
        )
        async let prompts: [PromptRow] = SupabaseClient.shared.select(
            "profile_prompts", filters: ["account_id": list], order: "position.asc"
        )
        async let interests: [InterestRow] = SupabaseClient.shared.select(
            "profile_interests", filters: ["account_id": list], order: "position.asc"
        )

        let profileRows = try await profiles
        let photosBy = Dictionary(grouping: try await photos, by: \.accountId)
        let promptsBy = Dictionary(grouping: try await prompts, by: \.accountId)
        let interestsBy = Dictionary(grouping: try await interests, by: \.accountId)

        // Ordered as asked, not as the database felt like returning them.
        let byID = Dictionary(uniqueKeysWithValues: profileRows.map { ($0.accountId, $0) })
        return ids.compactMap { id in
            byID[id]?.person(
                photos: photosBy[id] ?? [],
                prompts: promptsBy[id] ?? [],
                interests: interestsBy[id] ?? []
            )
        }
    }

    /// One-sided, and silent. The slot opens for you; their roster does not change.
    static func dismiss(_ person: Person) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        struct Dismissal: Encodable {
            let accountId: String
            let otherAccountId: String
            let night: String
        }
        try await SupabaseClient.shared.insert(
            "dismissals",
            Dismissal(accountId: session.userID,
                      otherAccountId: person.id,
                      night: ArchClock.today())
        )
    }

    // MARK: Conversations

    static func conversations() async throws -> [Conversation] {
        guard let session = await SupabaseClient.shared.restore() else { return [] }
        let me = session.userID

        let rows: [ConversationRow] = try await SupabaseClient.shared.select(
            "conversations",
            columns: "id,lo_account,hi_account,state,opened_by,last_message_at",
            order: "last_message_at.desc.nullslast"
        )
        guard !rows.isEmpty else { return [] }

        let others = rows.map { $0.other(than: me) }
        let profiles = try await people(ids: others)
        let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        let ids = rows.map(\.id).joined(separator: ",")
        let messages: [MessageRow] = try await SupabaseClient.shared.select(
            "messages",
            filters: ["conversation_id": "in.(\(ids))"],
            order: "created_at.asc"
        )
        let messagesBy = Dictionary(grouping: messages, by: \.conversationId)

        return rows.compactMap { row in
            // A profile that will not load is a person who has deleted their
            // account. The thread stays, because the words they said are still
            // yours to read; it simply has nowhere to go.
            guard let person = byID[row.other(than: me)] else { return nil }
            return row.conversation(with: person,
                                    messages: messagesBy[row.id] ?? [],
                                    me: me)
        }
    }

    /// Writing to somebody. This is the positive action in Arch: there are no
    /// likes, and sending spends a slot at both ends.
    static func startConversation(with person: Person, body: String) async throws -> String {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        // One function call, because opening a conversation and sending its first
        // message have to happen together — a conversation with no message in it is
        // a request the other person cannot answer.
        struct Arguments: Encodable {
            let otherAccount: String
            let body: String
        }
        struct Created: Decodable { let id: String }

        let created: Created = try await SupabaseClient.shared.rpc(
            "start_conversation",
            Arguments(otherAccount: person.id, body: body),
            returning: Created.self
        )
        return created.id
    }

    static func send(_ body: String, to conversationID: String) async throws -> MessageRow {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        return try await SupabaseClient.shared.insert(
            "messages",
            NewMessage(conversationId: conversationID,
                       senderId: session.userID,
                       body: body),
            returning: MessageRow.self
        )
    }

    static func accept(_ conversationID: String) async throws {
        struct StateChange: Encodable { let state: String }
        try await SupabaseClient.shared.update(
            "conversations", StateChange(state: "open"),
            filters: ["id": "eq.\(conversationID)"]
        )
    }

    /// Leaving, and blocking, and deleting your account all end here.
    ///
    /// They must be indistinguishable from the other side, so they write the same
    /// state and nothing else distinguishes them. A block additionally writes a row
    /// the other person can never read.
    static func end(_ conversationID: String) async throws {
        struct StateChange: Encodable { let state: String }
        try await SupabaseClient.shared.update(
            "conversations", StateChange(state: "ended"),
            filters: ["id": "eq.\(conversationID)"]
        )
    }

    static func block(_ person: Person) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        struct Block: Encodable {
            let blockerId: String
            let blockedId: String
        }
        try await SupabaseClient.shared.insert(
            "blocks", Block(blockerId: session.userID, blockedId: person.id)
        )
    }

    static func report(_ person: Person, reason: String, note: String?) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        struct Report: Encodable {
            let reporterId: String
            let reportedId: String
            let reason: String
            let note: String?
        }
        try await SupabaseClient.shared.insert(
            "reports",
            Report(reporterId: session.userID, reportedId: person.id,
                   reason: reason, note: note)
        )
    }

    // MARK: Settings

    static func discovery() async throws -> DiscoveryRow? {
        guard let session = await SupabaseClient.shared.restore() else { return nil }
        return try await SupabaseClient.shared.selectOne(
            "discovery_settings", filters: ["account_id": "eq.\(session.userID)"]
        )
    }

    static func saveDiscovery(_ row: DiscoveryRow) async throws {
        try await SupabaseClient.shared.upsert("discovery_settings", row)
    }

    /// Immediate and permanent, as the screen says.
    ///
    /// A function rather than a delete, because it has to end every conversation on
    /// the way out: the people mid-conversation see exactly what they would see if
    /// you had blocked them or simply left, and never which it was.
    static func deleteAccount() async throws {
        struct Empty: Encodable {}
        struct Done: Decodable { let ok: Bool }
        _ = try await SupabaseClient.shared.rpc("delete_account", Empty(), returning: Done.self)
        await SupabaseClient.shared.clearSession()
    }

    static func signOut() async {
        await SupabaseClient.shared.clearSession()
    }
}

private struct DismissalRow: Decodable {
    let otherAccountId: String
}

/// The clock the rosters run on.
///
/// **One batch, on New York time, for everybody.** Not nine wherever you happen to
/// be: a pair is created for two people in the same instant, so rolling
/// per-timezone batches would have to hand one of them a roster hours after theirs
/// was already on screen.
enum ArchClock {

    static var zone: TimeZone { DailyFiveStore.refillZone }

    /// The date the current roster belongs to, as Postgres wants it.
    ///
    /// Before nine in the morning, that is still yesterday's batch — the roster on
    /// screen at eight is the one from the previous morning, and asking for today's
    /// would come back empty.
    static func today(_ now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var date = now
        let hour = calendar.component(.hour, from: now)
        if hour < DailyFiveStore.refillHour {
            date = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
