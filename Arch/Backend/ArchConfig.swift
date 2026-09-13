import Foundation

/// Where the server is.
///
/// Read from `Info.plist` rather than written here, so that pointing a build at a
/// local Supabase, a staging project or production is a build setting instead of a
/// code change.
///
/// **The anon key is not a secret.** It is designed to ship inside clients: it
/// identifies the project and nothing more, and every row it can reach is decided
/// by row-level security on the server. The key that *is* secret is the service
/// key, which bypasses RLS entirely — it belongs on the server, in the nightly
/// matcher and the edge functions, and must never appear in this target.
enum ArchConfig {

    /// e.g. `https://abcdefgh.supabase.co`
    static let supabaseURL: URL = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ARCH_SUPABASE_URL") as? String,
              let url = URL(string: raw), url.scheme == "https" else {
            fatalError("""
                ARCH_SUPABASE_URL is missing from Info.plist.

                Add it as a String, e.g. https://yourproject.supabase.co, and add \
                ARCH_SUPABASE_ANON_KEY alongside it. Both are in the Supabase \
                dashboard under Project Settings -> API.
                """)
        }
        return url
    }()

    static let anonKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "ARCH_SUPABASE_ANON_KEY") as? String,
              !key.isEmpty else {
            fatalError("ARCH_SUPABASE_ANON_KEY is missing from Info.plist.")
        }
        return key
    }()

    static var restURL: URL { supabaseURL.appendingPathComponent("rest/v1") }
    static var authURL: URL { supabaseURL.appendingPathComponent("auth/v1") }
    static var functionsURL: URL { supabaseURL.appendingPathComponent("functions/v1") }
    static var storageURL: URL { supabaseURL.appendingPathComponent("storage/v1") }
}
