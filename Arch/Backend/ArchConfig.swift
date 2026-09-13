import Foundation

/// Where the server is, if there is one.
///
/// Read from `Info.plist` rather than written here, so that pointing a build at a
/// local Supabase, a staging project or production is a build setting instead of a
/// code change.
///
/// **`isConfigured` is false until those keys exist, and that is a supported
/// state, not a broken one.** Arch was built as a design build long before it had
/// a backend, and it still has to run that way: every `#Preview`, and anybody
/// opening the project before the keys are in, gets the app driven by `MockData`.
/// An earlier version of this file called `fatalError` when the keys were missing,
/// which would have turned "no backend yet" into a crash on launch.
///
/// **The anon key is not a secret.** It is designed to ship inside clients: it
/// identifies the project and nothing more, and every row it can reach is decided
/// by row-level security on the server. The key that *is* secret is the service
/// key, which bypasses RLS entirely — it belongs on the server, in the nightly
/// matcher and the edge functions, and must never appear in this target.
enum ArchConfig {

    /// e.g. `https://abcdefgh.supabase.co`
    static let supabaseURL: URL? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ARCH_SUPABASE_URL") as? String,
              let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }()

    static let anonKey: String? = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "ARCH_SUPABASE_ANON_KEY") as? String,
              !key.isEmpty else { return nil }
        return key
    }()

    /// Whether this build can talk to anything.
    ///
    /// Both keys or neither: half-configured is the state that produces requests
    /// to nowhere, which fail slowly and look like a network problem.
    static var isConfigured: Bool { supabaseURL != nil && anonKey != nil }

    /// The values, for code that has already checked `isConfigured`.
    ///
    /// These trap rather than return an optional, on purpose: reaching one of them
    /// unconfigured is a bug in the caller, and the message says which key to add.
    static var url: URL {
        guard let supabaseURL else {
            preconditionFailure(
                "ARCH_SUPABASE_URL is missing from Info.plist. Add it as a String, "
                + "e.g. https://yourproject.supabase.co, alongside "
                + "ARCH_SUPABASE_ANON_KEY. Both are in the Supabase dashboard under "
                + "Project Settings -> API. Check ArchConfig.isConfigured first."
            )
        }
        return supabaseURL
    }

    static var key: String {
        guard let anonKey else {
            preconditionFailure("ARCH_SUPABASE_ANON_KEY is missing from Info.plist.")
        }
        return anonKey
    }

    static var restURL: URL { url.appendingPathComponent("rest/v1") }
    static var authURL: URL { url.appendingPathComponent("auth/v1") }
    static var functionsURL: URL { url.appendingPathComponent("functions/v1") }
    static var storageURL: URL { url.appendingPathComponent("storage/v1") }
}
