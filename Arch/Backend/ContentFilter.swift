import Foundation

/// Words Arch does not allow, and where.
///
/// **The phone says no first, and the server is the one that decides.** The
/// list is `Resources/BlockedTerms.json`; backend/043 loads the same file into
/// `private.blocked_terms`, and a trigger refuses any profile field or message
/// that uses one. The check here exists so nobody ever meets that refusal:
/// onboarding saves everything at the end with `try?`, so a name the server
/// turned down would have been a profile that silently never existed. Instead
/// the button that would save it waits, with a line saying why.
///
/// **Two strengths.** Slurs are refused everywhere, messages included. Explicit
/// sexual words and selling (OnlyFans, sugar daddy) are refused only on a
/// profile: a profile is what strangers are shown, and a conversation between
/// two adults who chose to have it is not policed word by word.
///
/// The rules match backend/043 exactly, so the two never disagree:
/// whole words only, look-alike digits and symbols read as letters, a letter
/// written more times than in the list still counting, and single letters
/// spaced out read as one word.
enum ContentFilter {

    enum Scope {
        /// Name, work, prompt answers, interests.
        case profile
        /// A message, request or reply.
        case message
    }

    /// Whether every one of these may be saved.
    static func allows(_ texts: [String], in scope: Scope) -> Bool {
        texts.allSatisfy { firstBlocked(in: $0, scope: scope) == nil }
    }

    static func allows(_ text: String, in scope: Scope) -> Bool {
        allows([text], in: scope)
    }

    /// The line shown under a field while it holds a word Arch does not allow,
    /// or nil. It never repeats the word back.
    static func note(for texts: [String], in scope: Scope) -> String? {
        guard !allows(texts, in: scope) else { return nil }
        switch scope {
        case .profile: return "This has a word Arch does not allow. Take it out to continue."
        case .message: return "This has a word Arch does not allow. Take it out to send."
        }
    }

    static func note(for text: String, in scope: Scope) -> String? {
        note(for: [text], in: scope)
    }

    // MARK: Matching

    /// The first listed term in `text`, or nil.
    static func firstBlocked(in text: String, scope: Scope) -> String? {
        let tokens = words(in: text)
        guard !tokens.isEmpty else { return nil }
        let terms = scope == .profile ? lists.everywhere + lists.profile : lists.everywhere
        for term in terms {
            let parts = term.split(separator: " ").map(String.init)
            guard !parts.isEmpty, parts.count <= tokens.count else { continue }
            for start in 0...(tokens.count - parts.count) {
                var all = true
                for offset in 0..<parts.count where !stretches(tokens[start + offset], parts[offset]) {
                    all = false
                    break
                }
                if all { return term }
            }
        }
        return nil
    }

    /// Lower case, look-alikes read as letters, split on anything that is not
    /// a to z, and runs of single letters joined into one word.
    static func words(in text: String) -> [String] {
        let lookalikes: [Character: Character] = [
            "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t",
            "@": "a", "$": "s", "!": "i"
        ]
        var tokens: [String] = []
        var current = ""
        for raw in text.lowercased() {
            let character = lookalikes[raw] ?? raw
            if character >= "a" && character <= "z" {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var words: [String] = []
        var run = ""
        for token in tokens {
            if token.count == 1 {
                run += token
            } else {
                if !run.isEmpty { words.append(run); run = "" }
                words.append(token)
            }
        }
        if !run.isEmpty { words.append(run) }
        return words
    }

    /// Whether `token` is `word` with any of its letters written more times.
    /// "niiice" stretches "nice"; "con" does not stretch "coon", because a
    /// letter written fewer times than in the list is a different word.
    static func stretches(_ token: String, _ word: String) -> Bool {
        let have = runs(token), want = runs(word)
        guard have.count == want.count else { return false }
        for (a, b) in zip(have, want) where a.letter != b.letter || a.count < b.count {
            return false
        }
        return true
    }

    private static func runs(_ text: String) -> [(letter: Character, count: Int)] {
        var out: [(letter: Character, count: Int)] = []
        for character in text {
            if let last = out.last, last.letter == character {
                out[out.count - 1].count += 1
            } else {
                out.append((character, 1))
            }
        }
        return out
    }

    // MARK: The list

    private struct Lists: Decodable {
        let everywhere: [String]
        let profile: [String]
    }

    /// Read once. A build without the file allows everything here, and the
    /// server still refuses what it should.
    private static let lists: Lists = {
        guard let url = Bundle.main.url(forResource: "BlockedTerms", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Lists.self, from: data) else {
            return Lists(everywhere: [], profile: [])
        }
        return decoded
    }()
}
