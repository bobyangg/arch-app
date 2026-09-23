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

    // MARK: Signing in

    /// Exchange Apple's identity token for a session.
    ///
    /// Supabase verifies it against Apple's own keys — signature, issuer, audience
    /// and expiry — so the client is never trusted to say who it is, and none of
    /// that work is repeated in an edge function.
    @discardableResult
    static func signInWithApple(identityToken: String, nonce: String? = nil) async throws -> Session {
        try await SupabaseClient.shared.signInWithApple(
            identityToken: identityToken, nonce: nonce
        )
    }

    /// Send a six-digit code to an email address.
    static func sendEmailCode(to email: String) async throws {
        try await SupabaseClient.shared.sendEmailCode(to: email)
    }

    /// Exchange that code for a session.
    @discardableResult
    static func signInWithEmail(_ email: String, code: String) async throws -> Session {
        try await SupabaseClient.shared.verifyEmailCode(email: email, code: code)
    }

    enum Registration {
        case ok(isNewAccount: Bool, needsOnboarding: Bool, attested: Bool)
        case removed
    }

    /// Everything Supabase Auth does not do: attestation, and the ban check.
    ///
    /// Also the one and only place `apple_email` and `apple_name` can be captured.
    /// Apple sends those on the **first** authorization only; if they are not
    /// persisted here they are gone for good.
    ///
    /// Attestation is attempted and not required. `Attestation.isSupported` is
    /// false on a simulator, and the server decides whether to enforce — a client
    /// deciding whether it needs to prove itself is not a security control.
    static func register(identity: AppleIdentity) async throws -> Registration {
        let deviceToken = (try? await DeviceIdentity.token())?.base64EncodedString()

        // **Attestation is off the path the reader waits on.**
        //
        // It used to run first: fetch a challenge from us, hand it to Apple, wait
        // for Apple, then register. Three sequential round trips, two of them
        // before anything could happen on screen -- the edge logs put the pair at
        // about two and a half seconds of a button that looked stuck.
        //
        // Nothing is given up by moving it. The server already treats attestation
        // as a signal rather than a gate unless `ATTEST_ENFORCED` is on -- and if
        // it is on, the unattested call below is refused and the full exchange
        // runs properly, exactly as it always did. Enforcement still enforces; it
        // just costs the two seconds only where it is actually required.
        var reply = try await post(
            RegisterBody(challenge: nil, keyId: nil, attestation: nil,
                         deviceToken: deviceToken,
                         name: identity.name, email: identity.email)
        )

        if reply.status != "ok", reply.error != nil, Attestation.isSupported,
           let material = await attestationMaterial() {
            reply = try await post(
                RegisterBody(challenge: material.challenge, keyId: material.keyID,
                             attestation: material.attestation,
                             deviceToken: deviceToken,
                             name: identity.name, email: identity.email)
            )
        }

        guard reply.status == "ok" else { return .removed }

        // Proved afterwards, so the account still records a verified device and
        // `account_devices` still gets its key: a second call, on nobody's
        // critical path, whose answer nothing is waiting for.
        if Attestation.isSupported, reply.attested != true {
            let name = identity.name, email = identity.email
            Task.detached(priority: .background) {
                guard let material = await attestationMaterial() else { return }
                _ = try? await post(
                    RegisterBody(challenge: material.challenge,
                                 keyId: material.keyID,
                                 attestation: material.attestation,
                                 deviceToken: deviceToken, name: name, email: email)
                )
            }
        }

        return .ok(isNewAccount: reply.isNewAccount ?? true,
                   needsOnboarding: reply.needsOnboarding ?? true,
                   attested: reply.attested ?? false)
    }

    private static func post(_ body: RegisterBody) async throws -> RegisterReply {
        try await SupabaseClient.shared.callFunction(
            "register", body, returning: RegisterReply.self,
            // So a refused account is read rather than thrown. Without it the
            // `.removed` branch above is unreachable, and a banned reader is told
            // the network is down.
            readingRefusals: true
        )
    }

    /// A challenge from us and Apple's answer to it, or nil if either step failed.
    ///
    /// A failure here is not fatal and never has been: the server logs it and,
    /// until `ATTEST_ENFORCED` is on, lets the signup through. Turning attestation
    /// on and enforcing it in the same change would make the first failure
    /// indistinguishable from every real user being locked out.
    private static func attestationMaterial()
        async -> (challenge: String, keyID: String, attestation: String)? {
        guard let challenge = try? await self.challenge(),
              let bytes = Data(base64Encoded: challenge),
              let result = try? await Attestation.attest(challenge: bytes)
        else { return nil }
        return (challenge, result.keyID, result.attestation.base64EncodedString())
    }

    /// A one-time value for the device to attest over. Without it, a captured
    /// attestation would be replayable for every fake account after it.
    private static func challenge() async throws -> String {
        struct Empty: Encodable {}
        struct Reply: Decodable { let challenge: String }
        let reply: Reply = try await SupabaseClient.shared.callFunction(
            "challenge", Empty(), returning: Reply.self
        )
        return reply.challenge
    }

    // MARK: Account

    /// The signed-in account, or nil if there is no session.
    ///
    /// This is also the removal check: a removed account still has a valid session,
    /// because being removed is not the same as being signed out, and the screen
    /// that says so needs to know who it is talking to.
    /// **Nil means there is no row, and only that.** It used to mean that *or*
    /// "there is no session", and the caller signed the reader out and cleared
    /// the keychain for either -- so the two were worth telling apart, because
    /// one of them is recoverable and the other is what it says.
    static func account() async throws -> AccountRow? {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
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

    /// Asking a person to look at a refused photograph again.
    ///
    /// `photo_reviews` mirrors `appeals` in shape and in its unique constraint —
    /// one ask per photograph, because a second is not a second chance. The table
    /// was in the database with nothing in the app able to write to it.
    static func askForPhotoReview(id: String, note: String) async throws {
        struct NewPhotoReview: Encodable {
            let photoId: String
            let body: String
        }
        try await SupabaseClient.shared.insert(
            "photo_reviews", NewPhotoReview(photoId: id, body: note)
        )
    }

    /// Everything Arch holds about you, as JSON.
    ///
    /// The server function takes no account id — there is nothing to point at
    /// anybody else — and it already withholds what the app promises never to
    /// reveal: who dismissed whom, who blocked whom, the pairing scores, the
    /// reports. So this is a fetch and nothing more; the careful part is on the
    /// other side of the wire where it can be tested.
    static func myData() async throws -> Data {
        struct NoArguments: Encodable {}
        return try await SupabaseClient.shared.rpcRaw("my_data", NoArguments())
    }

    // MARK: Your own profile

    /// Notes on your profile, from the reviewer.
    ///
    /// The words go up; the photographs do not. The function reads those from the
    /// bucket itself, so what the reviewer sees is what the profile shows and not
    /// whatever the client chose to send. The answer comes back in the shape
    /// `ProfileNotes` decodes, and the server keeps a copy against a digest of the
    /// profile so the same profile is not reviewed twice.
    static func reviewProfile(_ person: Person, fresh: Bool = false) async throws -> ProfileNotes {
        struct Body: Encodable {
            struct Prompt: Encodable {
                let question: String
                let answer: String
            }
            let name: String
            let age: Int
            let work: String?
            let prompts: [Prompt]
            let interests: [String]
            let fresh: Bool
        }
        struct Reply: Decodable {
            let status: String
            let notes: ProfileNotes
        }

        let reply: Reply = try await SupabaseClient.shared.callFunction(
            "review",
            Body(
                name: person.name,
                age: person.age,
                work: person.work.isEmpty ? nil : person.work,
                prompts: person.answeredPrompts.map {
                    Body.Prompt(question: $0.question, answer: $0.answer)
                },
                interests: person.interests.map(\.text),
                fresh: fresh
            ),
            returning: Reply.self
        )
        return reply.notes
    }

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

        // Signed in one batch. A photograph with no URL keeps its tone, which is
        // also what it looks like while one is still loading.
        let urls = (try? await photoURLs(for: photoRows)) ?? [:]

        return Person(
            id: row.accountId,
            name: row.name,
            age: ArchUnits.age(fromBirthdate: row.birthdate),
            // Your own row carries the date. Nobody else's does, and nobody
            // else's ever will -- `visible_profiles` publishes an age.
            birthday: Birthday(iso: row.birthdate),
            place: PlaceLibrary.place(matching: row.placeId),
            coordinate: Coordinate(latitude: row.coarseLat, longitude: row.coarseLon),
            height: ArchUnits.height(fromCentimetres: row.heightCm),
            work: row.work ?? "",
            gender: ArchUnits.gender(fromColumn: row.gender),
            pronouns: row.pronouns ?? "",
            photos: photoRows.enumerated().map {
                Photo(id: $1.id, toneIndex: $0, url: urls[$1.id],
                      state: PhotoState(rawValue: $1.state) ?? .approved)
            },
            prompts: promptRows.map {
                Prompt(id: $0.id,
                       question: PromptLibrary.text(forID: $0.promptKey),
                       answer: $0.answer)
            },
            interests: interestRows.map { Interest(id: $0.id, text: $0.text) }
        )
    }

    /// The profile row, written once at the end of onboarding.
    ///
    /// An insert rather than the update `saveDetails` does, because there is
    /// nothing there yet -- and every other table references this row, so it goes
    /// first.
    static func createProfile(_ details: PersonDetails, coordinate: Coordinate?) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        guard let gender = details.gender, let place = details.place else {
            throw ArchAPIError.conflict
        }
        struct NewProfile: Encodable {
            let accountId: String
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
        // The device fix wins when there is one, and the centre of the picked place
        // otherwise. Either way it is coarsened before it leaves the phone -- the
        // CHECK constraint on the column refuses anything finer, so this is belt
        // and braces.
        //
        // Both can be absent, now that a place can be one rebuilt from a stored id
        // rather than one just picked. On this path it means the picker was never
        // opened, and a profile with no position at all would be invisible to the
        // distance filter in both directions -- so it is refused rather than
        // written with a zero.
        guard let centre = (coordinate ?? place.centre)?.coarsened else {
            throw ArchAPIError.conflict
        }
        try await SupabaseClient.shared.insert(
            "profiles",
            NewProfile(
                accountId: session.userID,
                name: details.name,
                // The date the reader gave, not one computed backwards from an
                // age. The fallback cannot be reached -- onboarding will not let
                // you past the first screen without a date -- and is here so a
                // future caller that forgets one still creates a profile rather
                // than failing at the last step of signing up.
                birthdate: details.birthday?.iso
                    ?? ArchUnits.birthdate(fromAge: details.age),
                gender: ArchUnits.genderColumn(gender),
                pronouns: details.pronouns.isEmpty ? nil : details.pronouns,
                placeId: place.id,
                coarseLat: centre.latitude,
                coarseLon: centre.longitude,
                heightCm: ArchUnits.centimetres(fromHeight: details.height),
                work: details.work.isEmpty ? nil : details.work
            )
        )
    }

    /// The discovery row, with the defaults every new account gets.
    ///
    /// Only `seeking` comes from onboarding; the rest are the sliders' own defaults
    /// and are changed in Settings. Asking somebody to pick a radius before they
    /// have seen a single person would be asking a question they cannot answer yet.
    static func createDiscovery(
        seeking: [String],
        distanceMiles: Int,
        minAge: Int,
        maxAge: Int,
        notifyMessages: Bool
    ) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        try await SupabaseClient.shared.upsert(
            "discovery_settings",
            DiscoveryRow(
                accountId: session.userID,
                seeking: seeking,
                distanceMiles: distanceMiles, minAge: minAge, maxAge: maxAge,
                paused: false, notifyMessages: notifyMessages
            )
        )
    }

    /// Saves the fields the details sheet edits.
    ///
    /// Age becomes a birthdate on the way down, because the database stores the
    /// date and derives the age — otherwise everybody's age would be whatever it
    /// was on the day they typed it.
    /// `settingHeight` is for a profile that has none, and only that.
    ///
    /// **Filling a blank is not changing a value.** Every round height was lost
    /// to the conversion bug above, so there are profiles with no height at all,
    /// and freezing the field would freeze them empty forever. A height that is
    /// already there still cannot be edited.
    static func saveDetails(_ details: PersonDetails,
                            settingHeight: Bool = false) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        // Gender is not read here any more: it is settled at signup and is not
        // in the payload below, so requiring one would refuse a legitimate save
        // over a field this function no longer writes.
        guard let place = details.place else { throw ArchAPIError.conflict }

        /// **The position is written only when there is a new one.**
        ///
        /// A place loaded back from the server carries no coordinate — the id
        /// holds the words and nothing else, by design. So editing your work or
        /// your height, without touching where you live, arrives here with
        /// `place.centre == nil`, and the right thing is to leave the stored
        /// position exactly as it is.
        ///
        /// That is not only a nil-check dodge: it is also what stops a routine
        /// edit from overwriting a precise device fix with the centre of a city.
        /// Somebody who tapped "Use my location" in Calgary is placed to a
        /// kilometre; re-saving their job title should not move them to downtown.
        ///
        /// Hand-written rather than an optional field because PostgREST reads a
        /// `null` as "set this column to null", and the column is `not null` —
        /// the key has to be absent, not empty.
        /// **No `birthdate` and no `height_cm`: both are settled at signup.**
        ///
        /// Leaving them out is the enforcement, not a convenience. `birthdate`
        /// used to be recomputed here from the displayed age, so saving an edit
        /// to your job title moved your birthday by however much the year had
        /// turned -- a column that drifted every time an unrelated field was
        /// touched. Height had no such bug and is frozen for the product reason:
        /// an age and a height that can be edited are two things people quietly
        /// revise, and the profile is supposed to be the same one somebody read
        /// yesterday.
        ///
        /// A genuine mistake is a support question, not a settings screen.
        struct Update: Encodable {
            let pronouns: String?
            let placeId: String
            /// Coarsened before it leaves the phone, not after it arrives. The
            /// CHECK constraint on the column refuses anything finer, so this is
            /// belt and braces on purpose.
            let centre: Coordinate?
            let work: String?
            /// Written only when there was nothing there. See `settingHeight`.
            let heightCm: Int?

            enum CodingKeys: String, CodingKey {
                case pronouns, placeId
                case coarseLat, coarseLon, work, heightCm
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(pronouns, forKey: .pronouns)
                try container.encode(placeId, forKey: .placeId)
                try container.encode(work, forKey: .work)
                if let centre {
                    try container.encode(centre.latitude, forKey: .coarseLat)
                    try container.encode(centre.longitude, forKey: .coarseLon)
                }
                if let heightCm {
                    try container.encode(heightCm, forKey: .heightCm)
                }
            }
        }

        try await SupabaseClient.shared.update(
            "profiles",
            Update(
                pronouns: details.pronouns.isEmpty ? nil : details.pronouns,
                placeId: place.id,
                centre: place.centre?.coarsened,
                work: details.work.isEmpty ? nil : details.work,
                heightCm: settingHeight
                    ? ArchUnits.centimetres(fromHeight: details.height) : nil
            ),
            filters: ["account_id": "eq.\(session.userID)"]
        )
    }

    // MARK: Photographs

    /// The row goes first, then the bytes.
    ///
    /// That order is the whole design. The storage policy is a lookup against the
    /// `photos` row, so an upload with no row behind it is refused — which means a
    /// path cannot be written by anybody who has not already claimed it. It also
    /// gives a failed upload a durable meaning: a row with `uploaded_at` still
    /// null, which survives the app being closed, where the current in-memory
    /// `uploads` dictionary does not.
    ///
    /// The id is minted here rather than by the server because the client needs it
    /// to build the path before either write.
    static func addPhoto(id: String, position: Int, jpeg: Data) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        let path = "\(session.userID)/\(id).jpg"

        struct NewPhoto: Encodable {
            let id: String
            let accountId: String
            let position: Int
            let storagePath: String
        }
        try await SupabaseClient.shared.insert(
            "photos",
            NewPhoto(id: id, accountId: session.userID,
                     position: position, storagePath: path)
        )

        do {
            try await SupabaseClient.shared.upload(path: path, data: jpeg)
        } catch {
            // The row is the record that this upload was attempted, and the grid
            // reads it to offer "Again". Deleting it here would make a failed
            // upload vanish instead, which is how somebody ends up with four
            // photos and no idea why the fifth never appeared.
            throw error
        }

        struct Uploaded: Encodable { let uploadedAt: String }
        try await SupabaseClient.shared.update(
            "photos",
            Uploaded(uploadedAt: ISO8601DateFormatter().string(from: Date())),
            filters: ["id": "eq.\(id)"]
        )
    }

    static func removePhoto(id: String) async throws {
        try await SupabaseClient.shared.delete("photos", filters: ["id": "eq.\(id)"])
    }

    /// The whole order, not a move.
    ///
    /// Positions are unique per account, so writing them one at a time collides
    /// with itself partway through a permutation. The server function takes the
    /// same shape and defers the constraint to commit.
    static func reorderPhotos(_ ids: [String]) async throws {
        struct Arguments: Encodable { let ids: [String] }
        // `reorder_photos` returns void, and PostgREST answers that with 204 and an
        // empty body. There is nothing there to decode into `Empty`, so asking for
        // one threw on every successful reorder.
        _ = try await SupabaseClient.shared.rpcRaw("reorder_photos", Arguments(ids: ids))
    }

    /// Signed URLs for a set of photographs, in one round trip.
    ///
    /// Returned keyed by photo id rather than by path, because that is what the
    /// views hold. A photograph the policy refused simply has no URL, and the
    /// placeholder tone stands in — which is also what happens while one loads.
    static func photoURLs(for photos: [PhotoRow]) async throws -> [String: URL] {
        let byPath = Dictionary(uniqueKeysWithValues: photos.map { ($0.storagePath, $0.id) })
        let signed = try await SupabaseClient.shared.signedURLs(paths: Array(byPath.keys))
        var out: [String: URL] = [:]
        for (path, url) in signed {
            if let id = byPath[path] { out[id] = url }
        }
        return out
    }

    /// The three prompts, as the whole set.
    ///
    /// Whole-set rather than per-prompt, for the reason the photo order is: the
    /// position column is unique per account, so writing them one at a time
    /// collides with itself when two of them swap.
    static func savePrompts(_ prompts: [Prompt]) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        /// **No `id`, and sending one is what lost every answer ever written.**
        /// The column is a `uuid` with a default; the client's ids are view
        /// identities, and the ones onboarding mints are `"you-q1"`, `"you-q2"`,
        /// `"you-q3"`. Postgres refused the whole insert as invalid uuid syntax,
        /// `commit()` wraps this call in `try?`, and three answers went quietly
        /// nowhere. Letting the default do it removes the class of mistake rather
        /// than the instance: these rows are deleted and rewritten on every save,
        /// so a client-side id was never stable enough to be worth keeping.
        struct PromptWrite: Encodable {
            let accountId: String
            let position: Int
            let promptKey: String
            let answer: String
        }
        try await SupabaseClient.shared.delete(
            "profile_prompts", filters: ["account_id": "eq.\(session.userID)"]
        )
        // **Only the ones actually written.** `answer` is
        // `check (length(trim(answer)) between 1 and 280)`, and onboarding starts
        // with three empty slots so that `updatePrompt` has somewhere to write --
        // so sending the whole set meant one unanswered slot failing the insert
        // and taking the two real answers down with it. Filtered here rather than
        // at each call site, because both callers had the same bug and a third
        // would have had it too.
        let written = prompts.filter {
            !$0.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let rows = written.enumerated().map { index, prompt in
            PromptWrite(
                accountId: session.userID,
                position: index,
                // Stored by id, not by its words: rewording a prompt is an ordinary
                // copy edit, and rows holding the old text would keep asking the old
                // question forever.
                promptKey: PromptLibrary.question(matching: prompt.question)?.id
                    ?? prompt.question,
                answer: prompt.answer
            )
        }
        // An empty set is a legitimate state -- three questions chosen and none
        // answered yet -- and PostgREST refuses an empty insert body.
        guard !rows.isEmpty else { return }
        try await SupabaseClient.shared.insert("profile_prompts", rows)
    }

    /// The interests, as the whole set, for the same reason.
    static func saveInterests(_ interests: [Interest]) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        /// Same as `PromptWrite`: no `id`. Onboarding's were `"draft-0"`,
        /// `"draft-1"`, `"draft-2"`, and a `uuid` column refused all three.
        struct InterestWrite: Encodable {
            let accountId: String
            let position: Int
            let text: String
        }
        try await SupabaseClient.shared.delete(
            "profile_interests", filters: ["account_id": "eq.\(session.userID)"]
        )
        // `text` carries the same kind of length check, so a blank chip would
        // refuse the whole set the way an unanswered prompt did.
        let filled = interests.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let rows = filled.enumerated().map { index, interest in
            InterestWrite(accountId: session.userID,
                          position: index, text: interest.text)
        }
        guard !rows.isEmpty else { return }
        try await SupabaseClient.shared.insert("profile_interests", rows)
    }

    /// The sixteen answers, written once at the end of onboarding.
    ///
    /// Sent as one upsert rather than sixteen inserts so that a connection dropping
    /// halfway cannot leave somebody with a half-answered questionnaire that the
    /// matcher would then score against everybody.
    ///
    /// Written again, whole, when somebody answers again from Settings. The
    /// time is sent rather than left to the column's default, because on an
    /// upsert the default only applies to a row being made -- and the row is
    /// already there. It is what "when did you last answer" is read from.
    static func saveAnswers(_ answers: [String: Int], at time: Date = .now) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        struct AnswerWrite: Encodable {
            let accountId: String
            let questionId: String
            let optionIndex: Int
            let answeredAt: Date
        }
        let rows = answers.sorted { $0.key < $1.key }.map {
            AnswerWrite(accountId: session.userID, questionId: $0.key,
                        optionIndex: $0.value, answeredAt: time)
        }
        try await SupabaseClient.shared.upsert("questionnaire_answers", rows)
    }

    /// Your own answers, and only yours: the policy on the table admits nobody
    /// else, and this is the one read of it the app makes. Settings uses it to
    /// start the questions from what you said rather than from nothing, and to
    /// know when you last said it.
    static func answers() async throws -> [AnswerRow] {
        guard let session = await SupabaseClient.shared.restore() else { return [] }
        return try await SupabaseClient.shared.select(
            "questionnaire_answers",
            columns: "question_id,option_index,answered_at",
            filters: ["account_id": "eq.\(session.userID)"]
        )
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

        let window = ArchClock.nightFilter()
        let rows: [PairingRow] = try await SupabaseClient.shared.select(
            "pairings",
            columns: "id,night,lo_account,hi_account",
            filters: ["night": window],
            order: "night.desc,created_at.asc"
        )
        guard !rows.isEmpty else { return [] }

        // Anybody this person has already dismissed is gone from their own roster
        // and nobody else's. The other side is never told.
        //
        // Matched to the pairing it cancels, night and all, because that is how
        // `match_population` reads it: a dismissal frees the slot held by the
        // pairing on *that* night and says nothing about any other. Comparing on
        // the person alone would hide somebody handed to you again tonight
        // because you passed on them yesterday.
        let dismissed: [DismissalRow] = try await SupabaseClient.shared.select(
            "dismissals",
            columns: "night,other_account_id",
            filters: ["account_id": "eq.\(me)", "night": window]
        )
        let hidden = Set(dismissed.map { "\($0.night)|\($0.otherAccountId)" })

        // Newest night first, and each person once: two nights of pairings can
        // name the same person twice, and a roster showing somebody in two slots
        // would spend two of five on one person.
        var others: [String] = []
        for row in rows {
            let other = row.other(than: me)
            guard !hidden.contains("\(row.night)|\(other)") else { continue }
            guard !others.contains(other) else { continue }
            others.append(other)
        }
        return try await people(ids: others)
    }

    /// Profiles for a set of accounts, with everything a card needs.
    static func people(ids: [String]) async throws -> [Person] {
        guard !ids.isEmpty else { return [] }
        let list = "in.(\(ids.joined(separator: ",")))"

        async let profiles: [VisibleProfileRow] = SupabaseClient.shared.select(
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
        let photoRows = try await photos
        let urls = (try? await photoURLs(for: photoRows)) ?? [:]
        let photosBy = Dictionary(grouping: photoRows, by: \.accountId)
        let promptsBy = Dictionary(grouping: try await prompts, by: \.accountId)
        let interestsBy = Dictionary(grouping: try await interests, by: \.accountId)

        // Ordered as asked, not as the database felt like returning them.
        let byID = Dictionary(uniqueKeysWithValues: profileRows.map { ($0.accountId, $0) })
        return ids.compactMap { id in
            byID[id]?.person(
                photos: photosBy[id] ?? [],
                prompts: promptsBy[id] ?? [],
                interests: interestsBy[id] ?? [],
                urls: urls
            )
        }
    }

    /// One-sided, and silent. The slot opens for you; their roster does not change.
    ///
    /// Written against the night of the pairing being dismissed, and not against
    /// tonight. `match_population` frees a slot only when the dismissal and the
    /// pairing agree on the night, so a dismissal stamped with the wrong one frees
    /// nothing: the person leaves the screen, the slot stays held, and they are
    /// back tomorrow. Both nights, if you are holding them on both.
    ///
    /// `upsert` rather than `insert` because the key is (you, them, night) and
    /// `start_conversation` writes the same row itself, on both sides, when you
    /// write to somebody. Two routes to one row is fine; a duplicate-key error
    /// reported to the reader as a failure, after a message that was sent, is not.
    static func dismiss(_ person: Person) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        let me = session.userID
        let rows: [PairingRow] = try await SupabaseClient.shared.select(
            "pairings",
            columns: "id,night,lo_account,hi_account",
            filters: ["night": ArchClock.nightFilter()]
        )
        let nights = rows.filter { $0.other(than: me) == person.id }.map(\.night)
        guard !nights.isEmpty else { return }

        struct Dismissal: Encodable {
            let accountId: String
            let otherAccountId: String
            let night: String
        }
        try await SupabaseClient.shared.upsert(
            "dismissals",
            nights.map { Dismissal(accountId: me, otherAccountId: person.id, night: $0) }
        )
    }

    // MARK: Conversations

    static func conversations() async throws -> [Conversation] {
        guard let session = await SupabaseClient.shared.restore() else { return [] }
        let me = session.userID

        let rows: [ThreadRow] = try await SupabaseClient.shared.select(
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
            // A profile that will not load is somebody who has deleted their
            // account. The thread stays, because the words they said are still
            // yours to read; it simply has nowhere to go.
            //
            // This used to `return nil`, which made the thread vanish from the
            // list — the exact opposite of the sentence above it, and of what
            // `delete_account` goes to trouble to guarantee. It is also why the
            // placeholder has to look like every other ended thread: leaving,
            // blocking and deleting are required to be indistinguishable from this
            // side, and a thread that disappeared only on deletion would say which
            // of the three had happened.
            let person = byID[row.other(than: me)]
                ?? Person.departed(id: row.other(than: me))
            return row.conversation(with: person,
                                    messages: messagesBy[row.id] ?? [],
                                    me: me)
        }
    }

    /// Writing to somebody. This is the positive action in Arch: there are no
    /// likes, and sending spends a slot at both ends.
    static func startConversation(with person: Person, body: String) async throws -> String {
        // Only that there *is* a session. Unlike the calls that read `session`
        // themselves, this one goes through `rpc`, which takes its token from
        // `validToken()` -- so binding it here would be a second and staler copy of
        // something nothing reads.
        guard await SupabaseClient.shared.restore() != nil else {
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

    // MARK: Notifications

    /// Where to send the one notification Arch sends.
    ///
    /// Upserted on the token, not the account: one person can have several phones,
    /// and a token that moves between them should land on the right row rather
    /// than making a second.
    static func savePushToken(_ token: String, environment: String) async throws {
        guard let session = await SupabaseClient.shared.restore() else {
            throw ArchAPIError.notSignedIn
        }
        struct TokenRow: Encodable {
            let accountId: String
            let token: String
            let environment: String
            let updatedAt: String
        }
        try await SupabaseClient.shared.upsert(
            "push_tokens",
            TokenRow(accountId: session.userID, token: token, environment: environment,
                     updatedAt: ISO8601DateFormatter().string(from: Date()))
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
    let night: String
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

    /// Tonight's date in New York, which is what `private.arch_night()` computes
    /// on the server. The same instant for everybody, by the same rule at both
    /// ends.
    static func night(_ now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }

    /// The nights a roster spans, newest first.
    ///
    /// **Two, because two is what the server holds.** `match_population` keeps a
    /// slot occupied for any pairing on a night later than `arch_night() - 2` that
    /// you have not dismissed, and `start_conversation` will only let you write to
    /// somebody inside that same window.
    ///
    /// Reading one night was the bug: somebody handed to you yesterday, who you
    /// never dismissed and never wrote to, left the screen at nine this morning
    /// while the server went on counting their slot as full. They did not go
    /// anywhere -- the pairing is still there, undismissed -- and because the slot
    /// was still held you were not offered anyone in their place either. A roster
    /// of five could lose people and gain nothing on the same morning.
    ///
    /// Anchored on the plain New York date rather than stepping back before nine.
    /// Yesterday is in the window either way, so the roster on screen at eight is
    /// still last night's batch, and the anchor now matches `arch_night()` exactly
    /// instead of approximately.
    static func nights(_ now: Date = Date()) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return [night(now), night(yesterday)]
    }

    /// The window as PostgREST wants it.
    static func nightFilter(_ now: Date = Date()) -> String {
        "in.(\(nights(now).joined(separator: ",")))"
    }
}

// MARK: - Registration wire shapes

/// What `register` is sent, and what it answers.
///
/// At file scope rather than inside `register` so the background attestation can
/// build one without capturing anything out of a function body.
private struct RegisterBody: Encodable {
    let challenge: String?
    let keyId: String?
    let attestation: String?
    let deviceToken: String?
    let name: String?
    let email: String?
}

private struct RegisterReply: Decodable {
    /// Absent on a refusal, which answers with `error` instead.
    let status: String?
    let isNewAccount: Bool?
    let needsOnboarding: Bool?
    let attested: Bool?
    let error: String?
}
