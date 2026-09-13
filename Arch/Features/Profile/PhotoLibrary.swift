import PhotosUI
import SwiftUI
import UIKit

/// Choosing photographs from the phone, and turning one into the square the rest
/// of the app draws.
///
/// **`PhotosPicker` rather than a grid of our own, and the reason is not effort.**
/// It runs out of process, so it needs no photo-library permission at all: Arch
/// never sees the library, only the images somebody hands over. A custom grid would
/// need full access to every photograph on the phone to show a thumbnail of six of
/// them, which is a strange thing for a dating app to ask for and a worse thing to
/// hold. `.ordered` also gives the numbered tap-order marks natively, which was the
/// one thing the bespoke grid did that mattered.
///
/// What is lost is the bespoke header and the "Arch can see some of your photos"
/// line — the limited-library case Apple's picker makes irrelevant by not asking.
struct PhotoLibraryPicker: View {
    let slotsLeft: Int
    /// Cropped, encoded and ready to upload, in the order they were chosen.
    let onPicked: ([PickedPhoto]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPresenting = false
    @State private var selection: [PhotosPickerItem] = []
    @State private var loaded: [LibraryPhoto] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if !ArchConfig.isConfigured {
                // A design build has no library to open and no permission to ask
                // for. The mock camera roll goes straight into the crop pager, so
                // the whole flow is walkable without a backend or a device.
                PhotoPickerView(slotsLeft: slotsLeft) { picked in
                    onPicked(picked)
                    dismiss()
                }
            } else if loaded.isEmpty {
                chooser
            } else {
                // Straight into the crop pager, which is where the real decision is
                // made — Apple's picker chooses *which*, this chooses *what of it*.
                PhotoPickerView(slotsLeft: slotsLeft, library: loaded) { picked in
                    onPicked(picked)
                    dismiss()
                }
            }
        }
    }

    private var chooser: some View {
        VStack(spacing: ArchSpacing.m) {
            Text(slotsLeft == 1
                 ? "Choose a photo"
                 : "Choose up to \(ArchCopy.word(slotsLeft)) photos")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            Text("You pick which ones Arch sees. It has no access to the rest of your library.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Presented by the modifier rather than built as a `PhotosPicker`
            // label, so the control is the app's own button at the app's own height
            // instead of a second thing that has to be kept looking like one.
            ArchButton(title: isLoading ? "Opening" : "Open my photos",
                       isEnabled: !isLoading) {
                isPresenting = true
            }

            ArchTextButton(title: "Not now") { dismiss() }
        }
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchColor.night)
        .photosPicker(
            isPresented: $isPresenting,
            selection: $selection,
            maxSelectionCount: slotsLeft,
            // Numbered in the order they were tapped, which is the order they end
            // up in on the profile — and slot one is what the roster shows.
            selectionBehavior: .ordered,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            Task { await load(items) }
        }
    }

    /// Pulls the bytes out of what was chosen.
    ///
    /// Sequentially rather than in parallel: six full-resolution photographs
    /// decoded at once on an older phone is how a picker gets itself terminated for
    /// memory, and the wait here is a second at most.
    private func load(_ items: [PhotosPickerItem]) async {
        isLoading = true
        defer { isLoading = false }

        var out: [LibraryPhoto] = []
        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            out.append(
                LibraryPhoto(
                    id: item.itemIdentifier ?? "picked-\(index)",
                    // The tone shown while the full image loads later. Taken from
                    // the photograph itself so the placeholder looks like the
                    // picture rather than like a swatch.
                    toneIndex: PhotoExport.tone(of: image),
                    aspect: image.size.height > 0 ? image.size.width / image.size.height : 1,
                    image: data
                )
            )
        }
        loaded = out
    }
}

/// Turning a chosen photograph and a crop into the bytes that get uploaded.
enum PhotoExport {

    /// What the profile is drawn at.
    ///
    /// 1080 square, because `PhotoCard.aspect` is 1 and a lead photo fills the
    /// width of the largest phone at roughly 3x. Larger would be bytes nobody sees.
    static let side: CGFloat = 1080
    static let quality: CGFloat = 0.85

    /// Render the kept part of a photograph, at the size the app draws it.
    ///
    /// **Re-encoded rather than passed through, and that is deliberate.** A JPEG
    /// straight off a phone carries EXIF, and EXIF carries GPS. `profiles` coarsens
    /// location to a kilometre grid with CHECK constraints that refuse anything
    /// finer; shipping the exact coordinates inside the photograph would undo every
    /// one of them while the database still looked compliant. Drawing into a fresh
    /// context keeps the pixels and nothing else.
    static func jpeg(from photo: LibraryPhoto, crop: PhotoCrop) -> Data? {
        guard let data = photo.image, let source = UIImage(data: data) else { return nil }

        // `UIImage.size` is already in the oriented space, so a photograph taken
        // sideways crops the way it looked rather than the way it was stored.
        let full = source.size
        let rect = CGRect(
            x: crop.origin.x * full.width,
            y: crop.origin.y * full.height,
            width: crop.size.width * full.width,
            height: crop.size.height * full.height
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: side, height: side), format: format
        )
        let output = renderer.image { _ in
            // Draw the whole image, shifted and scaled so the kept rect lands on
            // the canvas. Simpler and safer than `cgImage(forProposedRect:)`, which
            // has to be told about orientation separately.
            let scale = side / max(rect.width, 1)
            source.draw(in: CGRect(
                x: -rect.origin.x * scale,
                y: -rect.origin.y * scale,
                width: full.width * scale,
                height: full.height * scale
            ))
        }
        return output.jpegData(compressionQuality: quality)
    }

    /// The palette tone closest to a photograph's average colour.
    ///
    /// So the placeholder under a loading image is that image's own shade. A fixed
    /// tone would make a grid mid-load look like six unrelated swatches.
    static func tone(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        // One pixel, which is what averaging is: let the resampler do it.
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let brightness = (Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / 3
        let count = max(ArchColor.materials.count, 1)
        return min(count - 1, brightness * count / 256)
    }
}
