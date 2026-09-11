import SwiftUI

/// Your photos as a six-slot grid: drag to reorder, tap the empty slot to add, tap
/// the × to remove.
///
/// Pulled out of `ArrangeProfileView` so onboarding and arrange mode are literally
/// the same control rather than two grids that drift apart.
///
/// The × sits on the thumbnail here, which is the opposite of the rule on
/// `RosterCard` — there, a destructive control on top of the photo is a trap,
/// because the photo is something you are trying to look at and tap. This is a
/// management surface, and an × per thumbnail is what an editor is supposed to look
/// like.
/// What is happening to a photo you just added.
enum PhotoUpload: Hashable {
    case uploading
    case failed
}

struct PhotoGrid: View {
    let photos: [Photo]
    var canAdd: Bool
    var canRemove: Bool
    /// Keyed by photo id. Empty for every photo that is simply there.
    var uploads: [String: PhotoUpload] = [:]
    let onMove: (String, Int) -> Void
    let onAdd: () -> Void
    let onRemove: (String) -> Void
    /// Called by the tile once its bar has run, which is the design build's stand-in
    /// for the upload finishing.
    var onFinishUpload: (String) -> Void = { _ in }
    var onRetryUpload: (String) -> Void = { _ in }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: ArchSpacing.xs),
        count: 3
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: ArchSpacing.xs) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                slot(photo, at: index)
            }
            if canAdd {
                addSlot
            }
        }
    }

    private func slot(_ photo: Photo, at index: Int) -> some View {
        let upload = uploads[photo.id]

        return PhotoPlaceholder(toneIndex: photo.toneIndex)
            .aspectRatio(1, contentMode: .fit)
            .overlay { if upload == .failed { failedFace(photo) } }
            .overlay(alignment: .bottom) {
                if upload == .uploading {
                    UploadBar { onFinishUpload(photo.id) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous))
            .overlay(alignment: .topTrailing) {
                // Nothing to remove while it is still going up, and nothing to
                // reorder either — the × and the drag both come back when it lands.
                if canRemove && upload == nil {
                    Button { onRemove(photo.id) } label: {
                        Image(systemName: "xmark")
                            .archText(.caption)
                            .foregroundStyle(ArchColor.limestone)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(ArchColor.night.opacity(0.75)))
                            .padding(ArchSpacing.xxs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Remove photo \(index + 1)")
                }
            }
            .opacity(upload == .uploading ? 0.55 : 1)
            .draggable(upload == nil ? photo.id : "")
            .dropDestination(for: String.self) { ids, _ in
                guard let dragged = ids.first, !dragged.isEmpty else { return false }
                onMove(dragged, index)
                return true
            }
            .accessibilityLabel(slotLabel(index: index, upload: upload))
    }

    /// A failed upload is not an error the reader caused, so it gets no red, no
    /// exclamation mark and no alert — a flat stone tile and the word "Again".
    private func failedFace(_ photo: Photo) -> some View {
        Button { onRetryUpload(photo.id) } label: {
            VStack(spacing: ArchSpacing.xxs) {
                Image(systemName: "arrow.clockwise")
                    .archText(.footnote)
                Text("Again")
                    .archText(.badge)
            }
            .foregroundStyle(ArchColor.mortar)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ArchColor.stone)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityLabel("This photo did not upload. Try again.")
    }

    private func slotLabel(index: Int, upload: PhotoUpload?) -> String {
        let position = index == 0 ? "Photo 1, shown first" : "Photo \(index + 1)"
        switch upload {
        case .uploading: return "\(position), uploading"
        case .failed:    return "\(position), did not upload"
        case nil:        return position
        }
    }

    /// No dashed border. A dashed outline reads as an error to be fixed, and a
    /// half-filled grid is not an error.
    private var addSlot: some View {
        Button(action: onAdd) {
            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                .fill(ArchColor.stone)
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(systemName: "plus")
                        .archText(.body)
                        .foregroundStyle(ArchColor.mortar)
                )
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityLabel("Add a photo")
    }
}

/// The upload, drawn as a rule filling along the bottom edge of the tile.
///
/// Not a spinner. Uploading is a wait rather than an event, and a spinning circle
/// parked on top of a photograph is a piece of machinery sitting on the thing you
/// are trying to look at. Two points: thick enough to see, thin enough to read as a
/// rule rather than as a component.
private struct UploadBar: View {
    let onFinish: () -> Void

    @State private var progress: CGFloat = 0

    /// What a design build pretends an upload costs.
    private static let duration: Double = 1.4

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(ArchColor.lamp)
                .frame(width: geo.size.width * progress)
        }
        .frame(height: 2)
        .background(ArchColor.night.opacity(0.45))
        .onAppear {
            withAnimation(.linear(duration: Self.duration)) { progress = 1 }
        }
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            onFinish()
        }
        .accessibilityHidden(true)
    }
}

/// The line under the grid.
///
/// Three jobs: say what the first slot means; say why every × has disappeared when
/// you are sitting exactly on the four-photo floor; and say what a failed upload
/// means, since a photo that did not arrive is not on your profile whatever the
/// grid looks like.
struct PhotoGridCaption: View {
    let count: Int
    var failed: Int = 0

    var body: some View {
        Text(text)
            .archText(.footnote)
            .foregroundStyle(ArchColor.mortar)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var text: String {
        if failed > 0 {
            return failed == 1
                ? "One photo did not upload. It is not on your profile until it does."
                : "\(ArchCopy.capitalisedWord(failed)) photos did not upload. They are not on your profile until they do."
        }
        if count <= Person.requiredPhotos {
            return "The first photo is what people see in their five. "
                + "You need at least \(Person.requiredPhotos) photos, so add one before removing another."
        }
        return "The first photo is what people see in their five. Drag to reorder."
    }
}

#Preview("Photo grid") {
    PhotoGridPreview()
}

/// The tile mid-upload: dimmed, no ×, a rule filling along its bottom edge. It
/// lands on its own after a beat, which is the whole of the state.
#Preview("Uploading") {
    PhotoGridPreview(person: MockData.youIncomplete, adding: 1)
}

/// The one that did not arrive. No red, no alert, and the caption says the thing
/// that actually matters — it is not on your profile yet.
#Preview("One did not upload") {
    PhotoGridPreview(person: MockData.youIncomplete, adding: 1, failing: true)
}

private struct PhotoGridPreview: View {
    var person: Person = MockData.you
    /// Photos to add on appear, so the upload states have something to show.
    var adding: Int = 0
    var failing: Bool = false

    @State private var store = ProfileStore(person: MockData.you)
    @State private var isReady = false

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            PhotoGrid(
                photos: store.person.photos,
                canAdd: store.canAddPhoto,
                canRemove: store.canRemovePhoto,
                uploads: store.uploads,
                onMove: { store.movePhoto(id: $0, to: $1) },
                onAdd: { store.addPhotos([MockData.photoLibrary[0]]) },
                onRemove: { store.removePhoto(id: $0) },
                onFinishUpload: { store.finishUpload(id: $0) },
                onRetryUpload: { store.retryUpload(id: $0) }
            )
            PhotoGridCaption(count: store.person.photos.count, failed: store.failedUploads)
        }
        .onAppear {
            guard !isReady else { return }
            isReady = true
            store = ProfileStore(person: person)
            guard adding > 0 else { return }
            store.addPhotos(Array(MockData.photoLibrary.prefix(adding)))
            if failing {
                for photo in store.person.photos.suffix(adding) {
                    store.failUpload(id: photo.id)
                }
            }
        }
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
    }
}
