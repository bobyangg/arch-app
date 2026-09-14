import Foundation
import Observation

/// What the reviewer said about your profile.
///
/// One note per photograph, one per answer, and a paragraph on the whole. Flat on
/// purpose: each note names what it is about, so the screen lays it beside the
/// thing it describes rather than the reader matching numbers to cards.
///
/// There is no score anywhere in this type, and the shape is what keeps it that
/// way — the server's schema has no field for one, so the model has nowhere to
/// put it. A verdict is a word, and the strongest word it has is "change".
struct ProfileNotes: Codable, Hashable {
    var overall: String
    var items: [ProfileNote]

    func note(for kind: ProfileNote.Kind, position: Int) -> ProfileNote? {
        items.first { $0.kind == kind && $0.position == position }
    }
}

struct ProfileNote: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, Hashable {
        case photo
        case answer
    }

    enum Verdict: String, Codable, Hashable {
        /// Working as it is.
        case keep
        /// Fine, and here is a thought.
        case consider
        /// This one is costing you something.
        case change

        var word: String {
            switch self {
            case .keep:     return "Keep"
            case .consider: return "Consider"
            case .change:   return "Change"
            }
        }
    }

    var kind: Kind
    /// 1-based. Photo 1 is the one people see first.
    var position: Int
    var verdict: Verdict
    var note: String

    var id: String { "\(kind.rawValue)-\(position)" }
}

/// Asking for, and holding, the notes.
///
/// The review screen owns one of these. It asks once when the screen opens and
/// keeps the answer for as long as the screen is up, so scrolling up and down does
/// not ask again; the server keeps its own copy against a digest of the profile,
/// so opening the screen tomorrow does not ask again either.
@Observable
final class ProfileReviewStore {

    enum State: Equatable {
        case idle
        case loading
        case ready(ProfileNotes)
        /// A sentence the reader can be shown. Never the raw error.
        case failed(String)
    }

    private(set) var state: State = .idle

    var notes: ProfileNotes? {
        if case .ready(let notes) = state { return notes }
        return nil
    }

    var isLoading: Bool { state == .loading }

    /// Ask, unless an answer is already here.
    ///
    /// `fresh` asks the server for a new opinion even if it has one for this
    /// exact profile. Capped there, not here — the app does not get to decide how
    /// many the server will run.
    func load(_ person: Person, fresh: Bool = false) async {
        if !fresh, notes != nil { return }
        state = .loading

        guard ArchConfig.isConfigured else {
            // A design build has no reviewer. The mock notes arrive after the
            // pause a real call would take, so the loading state is walkable and
            // the screen is not designed around an answer that is simply there.
            try? await Task.sleep(for: .milliseconds(900))
            state = .ready(MockData.profileNotes)
            return
        }

        do {
            let notes = try await ArchBackend.reviewProfile(person, fresh: fresh)
            state = .ready(notes)
        } catch let error as ArchAPIError {
            state = .failed(Self.sentence(for: error))
        } catch {
            state = .failed(ArchAPIError.transport.readerFacing)
        }
    }

    /// The function's own refusals, in the reader's language. Anything else falls
    /// through to the plain sentence every other failure gets.
    private static func sentence(for error: ArchAPIError) -> String {
        switch error {
        case .server(let status, _):
            switch status {
            case 402: return "Notes are part of Arch Premium."
            case 422: return "The reviewer could not say anything useful about this profile. Add a photo or an answer and try again."
            case 503: return "Notes are not available yet."
            default:  return error.readerFacing
            }
        case .rateLimited:
            return "That is enough reviews for now. Come back tomorrow."
        default:
            return error.readerFacing
        }
    }
}
