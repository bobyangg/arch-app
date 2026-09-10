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
struct PhotoGrid: View {
    let photos: [Photo]
    var canAdd: Bool
    var canRemove: Bool
    let onMove: (String, Int) -> Void
    let onAdd: () -> Void
    let onRemove: (String) -> Void

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
        PhotoPlaceholder(toneIndex: photo.toneIndex)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if canRemove {
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
            .draggable(photo.id)
            .dropDestination(for: String.self) { ids, _ in
                guard let dragged = ids.first else { return false }
                onMove(dragged, index)
                return true
            }
            .accessibilityLabel(index == 0 ? "Photo 1, shown first" : "Photo \(index + 1)")
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

/// The line under the grid.
///
/// Two jobs: say what the first slot means, and — when you are sitting exactly on
/// the four-photo floor and every × has therefore disappeared — say why.
struct PhotoGridCaption: View {
    let count: Int

    var body: some View {
        Text(text)
            .archText(.footnote)
            .foregroundStyle(ArchColor.mortar)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var text: String {
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

private struct PhotoGridPreview: View {
    @State private var store = ProfileStore(person: MockData.you)

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            PhotoGrid(
                photos: store.person.photos,
                canAdd: store.canAddPhoto,
                canRemove: store.canRemovePhoto,
                onMove: { store.movePhoto(id: $0, to: $1) },
                onAdd: { store.addPhoto() },
                onRemove: { store.removePhoto(id: $0) }
            )
            PhotoGridCaption(count: store.person.photos.count)
        }
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
    }
}
