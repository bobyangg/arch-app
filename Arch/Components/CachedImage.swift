import SwiftUI
import UIKit

/// A photograph fetched once and kept for as long as the app is open.
///
/// **`AsyncImage` has no cache, and that is the whole reason this exists.** It
/// begins a fresh download every time its view is built, and a `LazyVGrid`
/// rebuilds its cells constantly — on scroll, and on every reorder, which
/// renumbers the slot each cell is drawing. So dragging one photograph into a
/// different position silently restarted the download for several others, and any
/// one of those that lost its race, or was cancelled by the next rebuild a frame
/// later, left a tile showing nothing but its tone. Sometimes, and not the same
/// one twice — which is exactly how it looked.
///
/// The signed URLs make it worse than a slow reload would be: they expire an hour
/// after the profile was loaded, so a refetch late in a session does not come back
/// at all. A decoded image in memory does not expire.
///
/// Deliberately small. No disk, no eviction policy beyond `NSCache`'s own, no
/// placeholder animation. Six photographs are the most this ever holds for one
/// profile, and the tone underneath is already the placeholder.
struct CachedImage: View {
    let url: URL?

    @State private var loaded: UIImage?

    /// Read straight from the cache while rendering, so a rebuilt cell draws its
    /// photograph on the first frame. Going through `@State` alone would show the
    /// bare tone for a frame every time the grid rebuilt, which is the flicker
    /// this is meant to remove.
    private var image: UIImage? {
        loaded ?? url.flatMap { ImageStore.shared.image(for: $0) }
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                // Not a spinner. The tone underneath is already doing the job, and
                // a spinner on top of it would be the app drawing attention to its
                // own latency.
                Color.clear
            }
        }
        // Keyed on the URL: a cell reused for a different photograph loads the
        // right one instead of keeping the last.
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            loaded = nil
            return
        }
        if let cached = ImageStore.shared.image(for: url) {
            loaded = cached
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let decoded = UIImage(data: data) else { return }
        ImageStore.shared.store(decoded, for: url)
        loaded = decoded
    }
}

/// Decoded photographs, by URL, for the life of the process.
///
/// `NSCache` rather than a dictionary because it empties itself under memory
/// pressure, which a dictionary of full-size images would not.
/// Not isolated to an actor, and `@unchecked Sendable` is an accurate claim
/// rather than a shortcut: the only stored property is an `NSCache`, which Apple
/// documents as safe to use from any thread. Isolating it to the main actor would
/// mean `CachedImage.image` — a plain computed property on a `View`, which is not
/// itself main-actor isolated — could not read it.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        // A profile holds six; a roster of five holds thirty. Sixty is a couple of
        // screens' worth and well inside the cost limit below.
        cache.countLimit = 60
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        let bytes = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: url as NSURL, cost: bytes)
    }
}
