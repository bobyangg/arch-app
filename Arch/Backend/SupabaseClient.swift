import Foundation

/// Talking to Supabase over plain HTTP.
///
/// Hand-written rather than taking the official SDK, for the same reason the rest
/// of Arch has no third-party dependencies: the surface actually used here is four
/// verbs against PostgREST and two auth endpoints, and a dependency that ships its
/// own networking, its own realtime client and its own storage layer is a lot of
/// other people's code to inherit for that.
///
/// An `actor` because the session is mutable shared state. Two screens loading at
/// once must not both notice an expired token and both refresh it — the refresh is
/// serialised here, and a refresh token that is used twice is a refresh token the
/// server is entitled to revoke.
actor SupabaseClient {

    static let shared = SupabaseClient()

    private let session = URLSession(configuration: .default)
    private var current: Session?
    private var refreshTask: Task<Session, Error>?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: Session

    /// Restored at launch. A `nil` return means nobody is signed in — not an error.
    func restore() -> Session? {
        if let current { return current }
        guard let raw = Keychain.get(Session.keychainKey),
              let data = raw.data(using: .utf8),
              let saved = try? decoder.decode(Session.self, from: data) else { return nil }
        current = saved
        return saved
    }

    func store(_ new: Session) {
        current = new
        if let data = try? encoder.encode(new), let raw = String(data: data, encoding: .utf8) {
            try? Keychain.set(raw, for: Session.keychainKey)
        }
    }

    /// Signing out is local. The account, the profile, the conversations and the
    /// roster are all untouched — signing back in with Apple lands straight back on
    /// them.
    func clearSession() {
        current = nil
        refreshTask = nil
        Keychain.remove(Session.keychainKey)
    }

    var isSignedIn: Bool { restore() != nil }

    /// A valid access token, refreshing first if the one held has expired.
    ///
    /// Refreshes a minute early: a token that expires while a request is in flight
    /// fails in a way that looks like a server error to everything upstream.
    func validToken() async throws -> String {
        guard let held = restore() else { throw ArchAPIError.notSignedIn }
        if held.expiresAt.timeIntervalSinceNow > 60 { return held.accessToken }

        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task<Session, Error> { [held] in
            // No `await`: both tasks are made in an actor-isolated context and
            // inherit this actor's executor, so `finishRefresh` is already running
            // on it. The `await` that used to be here suspended nothing and only
            // suggested a hop that does not happen.
            defer { Task { self.finishRefresh() } }
            return try await self.performRefresh(held.refreshToken)
        }
        refreshTask = task
        return try await task.value.accessToken
    }

    private func finishRefresh() { refreshTask = nil }

    private func performRefresh(_ refreshToken: String) async throws -> Session {
        var request = URLRequest(url: ArchConfig.authURL
            .appendingPathComponent("token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")]))
        request.httpMethod = "POST"
        request.setValue(ArchConfig.key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["refresh_token": refreshToken]
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ArchAPIError.transport }
        guard http.statusCode == 200 else {
            // A refused refresh means the session is gone for good — revoked,
            // expired, or the account removed. Clear it so the app asks for Apple
            // again instead of retrying a credential that will never work.
            clearSession()
            throw ArchAPIError.notSignedIn
        }
        let token = try decoder.decode(TokenResponse.self, from: data)
        let fresh = token.session
        store(fresh)
        return fresh
    }

    // MARK: Requests

    /// The one place a request is built, so the headers cannot drift apart.
    private func request(
        url: URL,
        method: String,
        body: Data? = nil,
        prefer: String? = nil,
        authenticated: Bool = true,
        /// Status codes whose *body* is the answer rather than an error.
        ///
        /// Only the edge functions need this, and only because they refuse with
        /// something worth reading. `register` answers a banned account with
        /// 403 and a body saying which kind of ban it was — and throwing on the
        /// status threw that away, so a removed account surfaced as
        /// `ArchAPIError.notPermitted` and was reported to the reader as "Arch
        /// could not reach the network just now". The `.removed` branch that
        /// was supposed to handle it could never be reached.
        readingBodyOn: Set<Int> = []
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(ArchConfig.key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if authenticated {
            request.setValue("Bearer \(try await validToken())",
                             forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(ArchConfig.key)",
                             forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw ArchAPIError.offline
        } catch {
            throw ArchAPIError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw ArchAPIError.transport }
        switch http.statusCode {
        case 200...299:
            return data
        case let code where readingBodyOn.contains(code):
            return data
        case 401, 403:
            // **Not necessarily an auth failure.** Row-level security answers a
            // forbidden read the same way it answers a missing row, so this is also
            // what being blocked, or reading a profile you are no longer paired
            // with, looks like from here. Treat it as "not yours", not as "sign in
            // again" — the session may be perfectly good.
            throw ArchAPIError.notPermitted
        case 404:
            throw ArchAPIError.notFound
        case 409:
            throw ArchAPIError.conflict
        case 429:
            throw ArchAPIError.rateLimited
        default:
            let message = (try? decoder.decode(PostgrestError.self, from: data))?.message
            throw ArchAPIError.server(status: http.statusCode, message: message)
        }
    }

    // MARK: PostgREST

    func select<T: Decodable>(
        _ table: String,
        columns: String = "*",
        filters: [String: String] = [:],
        order: String? = nil,
        limit: Int? = nil
    ) async throws -> [T] {
        var items = [URLQueryItem(name: "select", value: columns)]
        for (key, value) in filters.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: key, value: value))
        }
        if let order { items.append(URLQueryItem(name: "order", value: order)) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }

        let url = ArchConfig.restURL.appendingPathComponent(table).appending(queryItems: items)
        let data = try await request(url: url, method: "GET")
        return try decoder.decode([T].self, from: data)
    }

    func selectOne<T: Decodable>(
        _ table: String,
        columns: String = "*",
        filters: [String: String] = [:]
    ) async throws -> T? {
        let rows: [T] = try await select(table, columns: columns, filters: filters, limit: 1)
        return rows.first
    }

    @discardableResult
    func insert<Body: Encodable, T: Decodable>(
        _ table: String,
        _ value: Body,
        returning: T.Type
    ) async throws -> T {
        let url = ArchConfig.restURL.appendingPathComponent(table)
        let data = try await request(
            url: url, method: "POST",
            body: try encoder.encode(value),
            prefer: "return=representation"
        )
        let rows = try decoder.decode([T].self, from: data)
        guard let first = rows.first else { throw ArchAPIError.notFound }
        return first
    }

    func insert<Body: Encodable>(_ table: String, _ value: Body) async throws {
        let url = ArchConfig.restURL.appendingPathComponent(table)
        _ = try await request(url: url, method: "POST",
                              body: try encoder.encode(value),
                              prefer: "return=minimal")
    }

    /// Insert, or update what is already there. Used wherever a screen saves
    /// something the reader may be editing for the second time.
    func upsert<Body: Encodable>(_ table: String, _ value: Body) async throws {
        let url = ArchConfig.restURL.appendingPathComponent(table)
        _ = try await request(url: url, method: "POST",
                              body: try encoder.encode(value),
                              prefer: "resolution=merge-duplicates,return=minimal")
    }

    func update<Body: Encodable>(
        _ table: String,
        _ value: Body,
        filters: [String: String]
    ) async throws {
        let items = filters.sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        let url = ArchConfig.restURL.appendingPathComponent(table).appending(queryItems: items)
        _ = try await request(url: url, method: "PATCH",
                              body: try encoder.encode(value),
                              prefer: "return=minimal")
    }

    func delete(_ table: String, filters: [String: String]) async throws {
        let items = filters.sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        let url = ArchConfig.restURL.appendingPathComponent(table).appending(queryItems: items)
        _ = try await request(url: url, method: "DELETE", prefer: "return=minimal")
    }

    /// A Postgres function, for the things that must happen in one transaction.
    @discardableResult
    func rpc<Body: Encodable, T: Decodable>(
        _ name: String,
        _ arguments: Body,
        returning: T.Type
    ) async throws -> T {
        let url = ArchConfig.restURL.appendingPathComponent("rpc").appendingPathComponent(name)
        let data = try await request(url: url, method: "POST",
                                     body: try encoder.encode(arguments))
        return try decoder.decode(T.self, from: data)
    }

    /// An RPC whose answer is kept as bytes rather than decoded.
    ///
    /// `my_data` returns the whole export, and the point of it is to hand a person
    /// a file. Decoding that into Swift types and encoding it back would be work
    /// done to arrive where it started, and every round trip is a chance to drop a
    /// field nobody notices is missing.
    func rpcRaw<Body: Encodable>(_ name: String, _ arguments: Body) async throws -> Data {
        let url = ArchConfig.restURL.appendingPathComponent("rpc").appendingPathComponent(name)
        return try await request(url: url, method: "POST",
                                 body: try encoder.encode(arguments))
    }

    // MARK: Auth and functions

    /// Exchange Apple's identity token for a Supabase session.
    ///
    /// Supabase verifies the token with Apple itself — signature, issuer, audience
    /// and expiry — so the client is not trusted to say who it is, and there is no
    /// need to re-do that work in an edge function.
    func signInWithApple(identityToken: String, nonce: String?) async throws -> Session {
        var payload: [String: Any] = ["provider": "apple", "id_token": identityToken]
        if let nonce { payload["nonce"] = nonce }

        let url = ArchConfig.authURL.appendingPathComponent("token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "id_token")])
        let data = try await request(
            url: url, method: "POST",
            body: try JSONSerialization.data(withJSONObject: payload),
            authenticated: false
        )
        let token = try decoder.decode(TokenResponse.self, from: data)
        let new = token.session
        store(new)
        return new
    }

    /// Send a six-digit code to an email address.
    ///
    /// `shouldCreateUser` is on: Arch has one door, and an address that has not
    /// been here before is a new account rather than an error. The alternative is
    /// a sign-up screen and a sign-in screen that differ only in which one refuses
    /// you, and people do not remember which they used.
    ///
    /// Nothing comes back but success. Whether the address is already an account is
    /// deliberately not said — answering that question is an account-enumeration
    /// oracle, and anybody could ask it about anybody.
    func sendEmailCode(to email: String) async throws {
        let url = ArchConfig.authURL.appendingPathComponent("otp")
        _ = try await request(
            url: url, method: "POST",
            body: try JSONSerialization.data(
                withJSONObject: ["email": email, "create_user": true]
            ),
            authenticated: false
        )
    }

    /// Exchange the code for a session.
    ///
    /// `type: "email"` is the one-time-code grant rather than the magic-link one.
    /// Supabase checks the code against what it sent and how long ago, so the
    /// client is not trusted to say the code was right.
    func verifyEmailCode(email: String, code: String) async throws -> Session {
        let url = ArchConfig.authURL.appendingPathComponent("verify")
        let data = try await request(
            url: url, method: "POST",
            body: try JSONSerialization.data(
                withJSONObject: ["email": email, "token": code, "type": "email"]
            ),
            authenticated: false
        )
        let token = try decoder.decode(TokenResponse.self, from: data)
        let new = token.session
        store(new)
        return new
    }

    // MARK: Storage

    /// Put an image in the bucket.
    ///
    /// `URLSession.upload` rather than a body on a data task, so a slow connection
    /// reports progress and a cancelled one actually stops sending. The row in
    /// `photos` is written first: the storage policy is a lookup against that row,
    /// so an upload with no row behind it is refused rather than orphaned.
    func upload(path: String, data: Data, contentType: String = "image/jpeg") async throws {
        var request = URLRequest(
            url: ArchConfig.storageURL
                .appendingPathComponent("object")
                .appendingPathComponent("photos")
                .appendingPathComponent(path)
        )
        request.httpMethod = "POST"
        request.setValue(ArchConfig.key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        // The bucket refuses an overwrite, and so does the absence of an update
        // policy. Saying so here turns a silent 400 into the right error.
        request.setValue("false", forHTTPHeaderField: "x-upsert")

        let (body, response): (Data, URLResponse)
        do {
            (body, response) = try await session.upload(for: request, from: data)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw ArchAPIError.offline
        } catch {
            throw ArchAPIError.transport
        }
        guard let http = response as? HTTPURLResponse else { throw ArchAPIError.transport }
        guard (200...299).contains(http.statusCode) else {
            throw ArchAPIError.server(
                status: http.statusCode,
                message: String(data: body, encoding: .utf8)
            )
        }
    }

    /// Short-lived URLs for a set of stored objects.
    ///
    /// Batched, because a roster is up to seven people with six photographs each
    /// and signing them one at a time would be forty-two round trips on a phone.
    /// `ArchBackend.roster()` went to the same trouble for the same reason.
    ///
    /// **Never persisted.** A signed URL that outlives a block keeps serving a
    /// photograph to somebody who has been blocked, which is precisely what the
    /// private bucket exists to prevent. An hour is already the compromise.
    func signedURLs(paths: [String], expiresIn seconds: Int = 3600) async throws -> [String: URL] {
        guard !paths.isEmpty else { return [:] }
        struct Request: Encodable {
            let expiresIn: Int
            let paths: [String]
        }
        struct Signed: Decodable {
            let path: String?
            let signedURL: String?
            enum CodingKeys: String, CodingKey {
                case path
                case signedURL = "signedURL"
            }
        }

        var request = URLRequest(
            url: ArchConfig.storageURL
                .appendingPathComponent("object")
                .appendingPathComponent("sign")
                .appendingPathComponent("photos")
        )
        request.httpMethod = "POST"
        request.setValue(ArchConfig.key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            Request(expiresIn: seconds, paths: paths)
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ArchAPIError.notPermitted
        }
        let signed = try JSONDecoder().decode([Signed].self, from: data)

        var out: [String: URL] = [:]
        for item in signed {
            // A path the policy refused comes back with a null URL rather than as
            // an error, so a blocked photograph simply has none — which is what
            // the placeholder tone is for.
            guard let path = item.path, let relative = item.signedURL else { continue }
            out[path] = URL(string: relative, relativeTo: ArchConfig.storageURL)?.absoluteURL
        }
        return out
    }

    /// Call an edge function. Used for the one flow that cannot be a table write.
    func callFunction<Body: Encodable, T: Decodable>(
        _ name: String,
        _ body: Body,
        returning: T.Type,
        /// Decode a 403 body instead of throwing. See `readingBodyOn`.
        readingRefusals: Bool = false
    ) async throws -> T {
        let url = ArchConfig.functionsURL.appendingPathComponent(name)
        let data = try await request(url: url, method: "POST",
                                     body: try encoder.encode(body),
                                     readingBodyOn: readingRefusals ? [403] : [])
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Supporting types

struct Session: Codable, Hashable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: String

    static let keychainKey = "session"
}

/// Supabase's token response. `expires_in` is seconds from now, which is not a
/// thing worth storing — it is turned into an instant here, once.
private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User

    struct User: Decodable { let id: String }

    var session: Session {
        Session(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            userID: user.id
        )
    }
}

private struct PostgrestError: Decodable {
    let message: String?
    let code: String?
}

enum ArchAPIError: Error, Equatable {
    case notSignedIn
    /// The row exists or does not; either way it is not yours to read. Row-level
    /// security does not distinguish, and neither should anything above it.
    case notPermitted
    case notFound
    case conflict
    case rateLimited
    case offline
    case transport
    case server(status: Int, message: String?)

    /// What a reader is shown. Deliberately plain, and never blaming them.
    var readerFacing: String {
        switch self {
        case .offline, .transport:
            return "Arch cannot reach the network just now."
        case .notSignedIn:
            return "Sign in to continue."
        case .rateLimited:
            return "Too much at once. Try again in a moment."
        default:
            return "Something did not work. Nothing was lost."
        }
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    /// Postgres hands back `2026-09-13T09:00:00.123456+00:00`. The stock `.iso8601`
    /// strategy rejects fractional seconds, which is a surprising way to lose a
    /// whole response.
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: raw) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Bad date: \(raw)")
            )
        }
    }
}
