import Foundation

/// Pictures for the made-up people, so a recording of the design build shows
/// faces instead of quarry tones.
///
/// **Nothing here is in the repository's history of real people.** The design
/// build has never shown a photograph: every `Photo` in `MockData` is a tone, and
/// that is still the default. A picture appears only when a file named after the
/// photo's id is in `Arch/Resources/MockPhotos` -- `nadia-p1.jpg` for
/// `Photo(id: "nadia-p1", ...)` -- so the folder can be empty, half full or full
/// and every screen, preview and UI test still draws.
///
/// Use generated faces or stock photographs licensed for advertising, never a
/// real member of Arch. About 1000 pixels square is plenty: they are held in
/// memory for the life of the process, like your own photographs are.
///
/// Release leaves the folder out (`EXCLUDED_SOURCE_FILE_NAMES` in `project.yml`),
/// and a real build never reads `MockData` people anyway.
enum MockPhotos {

    /// The same photos, with a picture attached to each one that has a file.
    static func attach(_ photos: [Photo]) -> [Photo] {
        photos.map { photo in
            var photo = photo
            if photo.local == nil { photo.local = data(for: photo.id) }
            return photo
        }
    }

    static func data(for id: String) -> Data? {
        for type in ["jpg", "jpeg", "png"] {
            if let url = Bundle.main.url(forResource: id, withExtension: type),
               let data = try? Data(contentsOf: url) {
                return data
            }
        }
        return nil
    }
}
