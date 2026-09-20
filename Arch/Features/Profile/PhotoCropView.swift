import SwiftUI

/// Positioning one photo inside the square frame.
///
/// **One frame and one zoom.** No rotate, no flip, no thirds grid, no filters. The
/// only thing that matters here is which part of the photograph ends up in the
/// shape the rest of the app draws photos in, and every extra tool is a decision
/// nobody asked to make.
///
/// The photograph is drawn at full size with everything outside the frame dimmed
/// rather than cropped away, so you can see what you are leaving out — and so that
/// dragging has something visible to do even when the picture is a flat tone.
///
/// It has to exist at all because almost nothing on anybody's phone is already
/// square. The alternative is centre-cropping for people, which is how you get
/// profiles where the first photo is somebody's forehead.

/// Which part of a photograph somebody kept.
///
/// Normalised into the source image's own space, so it survives the image being
/// loaded at a different size than it was cropped at — which it always is. The
/// picker shows a thumbnail and the upload re-renders from the full-resolution
/// original, and a rect in points would mean something different to each of them.
struct PhotoCrop: Hashable {
    /// Top-left of the kept window, 0...1 of the source.
    var origin: CGPoint
    /// Its size, 0...1 of the source. Always the shape of `PhotoCard.aspect`.
    var size: CGSize

    /// The whole photograph, for a source that is already the right shape.
    static let full = PhotoCrop(origin: .zero, size: CGSize(width: 1, height: 1))
}

/// A photograph somebody chose, and the part of it they kept.
///
/// The two travel together from here to the upload because they are useless apart:
/// the library item says which image, the crop says which of it, and an upload
/// given only the first would centre-crop for people — which is how you get
/// profiles where the first photo is somebody's forehead.
struct PickedPhoto: Hashable {
    let photo: LibraryPhoto
    let crop: PhotoCrop
}

struct PhotoCropView: View {
    let photo: LibraryPhoto
    /// Which of the chosen photos this is, for the counter.
    var step: Int = 1
    var total: Int = 1
    /// Hands back what was framed. It used to hand back nothing, which meant the
    /// whole screen was a ceremony — somebody positioned their photograph and the
    /// app then centre-cropped it anyway.
    let onUse: (PhotoCrop) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Zoom as a percentage, so the slider the rest of the app uses fits it.
    @State private var zoom: Int = 100
    @State private var zoomBase: Int = 100
    @State private var offset: CGSize = .zero
    @State private var drag: CGSize = .zero
    /// The stage, captured so `crop()` can use the same geometry the view drew
    /// with. Everything else is derived inside the `GeometryReader` and thrown
    /// away, and re-deriving it from a guess would export an almost-right rect —
    /// faces slightly off, and nobody files a bug about slightly.
    @State private var stageSize: CGSize = .zero

    private static let zoomRange = 100...250
    /// The margin of visible, dimmed photograph around the frame.
    private static let inset: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            header
            stage
            controls
        }
        .background(ArchColor.night)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { footer }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: ArchSpacing.s) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                    .frame(width: ArchSpacing.minimumTapTarget, height: ArchSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Back")

            Text("Position")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            Spacer(minLength: 0)

            // Only when there is more than one, because "1 of 1" is a counter
            // counting nothing.
            if total > 1 {
                Text("\(step) of \(total)")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .monospacedDigit()
            }
        }
        .padding(.leading, ArchSpacing.xs)
        .padding(.trailing, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.xs)
    }

    private var stage: some View {
        GeometryReader { geo in
            let frame = frameSize(in: geo.size)
            let image = imageSize(covering: frame)
            let limit = limitSize(image: image, frame: frame)
            let placed = clamped(
                CGSize(
                    width: offset.width + drag.width,
                    height: offset.height + drag.height
                ),
                to: limit
            )
            ZStack {
                Color.clear
                    // The one piece of the stage geometry that has to outlive the
                    // closure, so `crop()` can rebuild the rest of it exactly.
                    .onAppear { stageSize = geo.size }
                    .onChange(of: geo.size) { _, size in stageSize = size }

                PhotoPlaceholder(toneIndex: photo.toneIndex, data: photo.image)
                    .frame(width: image.width, height: image.height)
                    // Its own edges, so the bounds of the photograph read even
                    // against a dark one.
                    .overlay {
                        Rectangle().strokeBorder(ArchColor.hairline, lineWidth: 1)
                    }
                    .offset(x: placed.width, y: placed.height)

                // What is being left out, not thrown away. Lighter than the sheet
                // scrim on purpose: a sheet's scrim hides what is behind it, and
                // this one has to let you read it.
                CropSurround(hole: frame, radius: ArchRadius.photo)
                    .fill(ArchColor.night.opacity(0.55), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                RoundedRectangle(cornerRadius: ArchRadius.photo, style: .continuous)
                    .strokeBorder(ArchColor.quietBorder, lineWidth: 1)
                    .frame(width: frame.width, height: frame.height)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { drag = $0.translation }
                    .onEnded { _ in
                        offset = placed
                        drag = .zero
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoom = clampZoom(Int(Double(zoomBase) * value.magnification))
                    }
                    .onEnded { _ in zoomBase = zoom }
            )
            .accessibilityLabel("The photograph. Drag to move it inside the frame.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, ArchSpacing.m)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
            Text("Drag to move it. The slider zooms.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)

            // The slider writes the pinch's starting point too, so the next pinch
            // continues from where the slider left off instead of jumping.
            ValueSlider(
                value: Binding(
                    get: { zoom },
                    set: { zoom = $0; zoomBase = $0 }
                ),
                bounds: Self.zoomRange
            )
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
    }

    private var footer: some View {
        ArchButton(title: step < total ? "Next" : useTitle) { onUse(crop()) }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.top, ArchSpacing.s)
            .padding(.bottom, ArchSpacing.s)
            .archBar(.bottom)
    }

    private var useTitle: String {
        total > 1 ? "Add \(ArchCopy.word(total)) photos" : "Add photo"
    }

    // MARK: Geometry

    /// The frame, in the shape the rest of the app draws photos in, as large as it
    /// can be inside the stage with a margin left over on every side for the part
    /// of the photograph you are cutting off.
    private func frameSize(in stage: CGSize) -> CGSize {
        let available = CGSize(width: max(stage.width - Self.inset * 2, 1),
                               height: max(stage.height - Self.inset * 2, 1))
        var width = max(min(available.width, available.height * PhotoCard.aspect), 1)

        // **The frame also has to be small enough to see the photograph around
        // it.** At zoom 100 the picture exactly covers the frame, and the frame
        // was as large as the stage would allow -- so a landscape photograph came
        // out wider than the stage and was clipped at both edges before the
        // reader had touched anything. The first sight of your own photograph was
        // one already cut, with no way to see what had been lost and nothing
        // saying any had been.
        //
        // Shrinking the frame until the covering picture fits is what makes the
        // opening view the whole picture. It costs frame size on wide photographs
        // and buys the thing this screen is for: choosing, rather than being
        // shown a choice already made.
        let covering = imageSize(covering: CGSize(width: width,
                                                  height: width / PhotoCard.aspect),
                                 atZoom: 100)
        let overflow = max(covering.width / max(stage.width, 1),
                           covering.height / max(stage.height, 1))
        if overflow > 1 { width /= overflow }

        // A floor, because a 3:1 panorama would otherwise shrink the frame to a
        // postage stamp to show two strips of sky. Past this the edges are
        // clipped again, which is the right trade at that shape.
        width = max(width, available.width * 0.45)
        return CGSize(width: width, height: width / PhotoCard.aspect)
    }

    /// The photograph at its own shape, scaled so it covers the frame, then zoomed.
    private func imageSize(covering frame: CGSize) -> CGSize {
        imageSize(covering: frame, atZoom: zoom)
    }

    /// Taking the zoom rather than reading it, so `frameSize` can ask what the
    /// picture would measure at rest without the answer moving as somebody
    /// pinches.
    private func imageSize(covering frame: CGSize, atZoom zoom: Int) -> CGSize {
        let factor = max(frame.width / max(photo.aspect, 0.01), frame.height)
        let scale = CGFloat(zoom) / 100
        return CGSize(width: photo.aspect * factor * scale, height: factor * scale)
    }

    /// How far it can travel before a corner of the frame would be empty.
    private func limitSize(image: CGSize, frame: CGSize) -> CGSize {
        CGSize(
            width: max(0, (image.width - frame.width) / 2),
            height: max(0, (image.height - frame.height) / 2)
        )
    }

    private func clamped(_ value: CGSize, to limit: CGSize) -> CGSize {
        CGSize(
            width: min(max(value.width, -limit.width), limit.width),
            height: min(max(value.height, -limit.height), limit.height)
        )
    }

    private func clampZoom(_ value: Int) -> Int {
        min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    /// What is inside the frame, as a fraction of the source photograph.
    ///
    /// Built from the same four helpers the stage draws with, in the same order,
    /// so the exported rect is the rectangle that was on screen rather than a
    /// second opinion about it.
    ///
    /// The image is drawn centred and then moved by `placed`, so the frame sits at
    /// the image's centre *minus* that movement. Dividing by the drawn image size
    /// cancels both the cover factor and the zoom, which is why the result is
    /// independent of how large the stage happened to be.
    private func crop() -> PhotoCrop {
        let frame = frameSize(in: stageSize)
        let image = imageSize(covering: frame)
        guard stageSize.width > 0, image.width > 0, image.height > 0 else {
            return .full
        }
        let limit = limitSize(image: image, frame: frame)
        let placed = clamped(
            CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
            to: limit
        )

        let x = (image.width / 2 - placed.width - frame.width / 2) / image.width
        let y = (image.height / 2 - placed.height - frame.height / 2) / image.height

        // Clamped because a rect that starts a hair outside the source is a
        // decoding error later, a long way from here.
        let w = min(1, frame.width / image.width)
        let h = min(1, frame.height / image.height)
        return PhotoCrop(
            origin: CGPoint(x: min(max(x, 0), 1 - w), y: min(max(y, 0), 1 - h)),
            size: CGSize(width: w, height: h)
        )
    }
}

/// Everything except the frame.
///
/// Two subpaths filled even-odd, so the frame is a hole rather than four rectangles
/// that have to be kept in agreement with each other.
///
/// **A size, centred in whatever space the shape is given — not a rect.** It took
/// a `CGRect` computed from the stage's size, and a shape inside that `ZStack` is
/// not laid out in the stage's space: the stack grows to fit the zoomed
/// photograph, which overflows sideways long before it overflows vertically. So
/// the hole was drawn at stage coordinates inside a wider rect and slid left by
/// half the overflow, while the frame's outline — centred by the stack, like
/// everything else — stayed put. Two rectangles, a hand's width apart, and the
/// lit part of the picture matching neither.
///
/// Centring it here is not a correction applied to the old arithmetic; it removes
/// the arithmetic. The hole and the outline are now centred by the same rule in
/// the same space, so there is no longer a way for them to disagree.
struct CropSurround: Shape {
    let hole: CGSize
    var radius: CGFloat = ArchRadius.photo

    func path(in rect: CGRect) -> Path {
        let cut = CGRect(
            x: rect.midX - hole.width / 2,
            y: rect.midY - hole.height / 2,
            width: hole.width,
            height: hole.height
        )
        var path = Path(rect)
        path.addPath(Path(roundedRect: cut, cornerRadius: radius, style: .continuous))
        return path
    }
}

// MARK: - Previews

#Preview("A portrait photo") {
    NavigationStack {
        PhotoCropView(photo: MockData.photoLibrary[0]) { _ in }
    }
    .preferredColorScheme(.dark)
}

/// The case the screen exists for: a wide photograph that has to lose most of
/// itself to become a portrait.
#Preview("A landscape photo, second of three") {
    NavigationStack {
        PhotoCropView(photo: MockData.photoLibrary[6], step: 2, total: 3) { _ in }
    }
    .preferredColorScheme(.dark)
}

#Preview("A panorama") {
    NavigationStack {
        PhotoCropView(photo: MockData.photoLibrary[17]) { _ in }
    }
    .preferredColorScheme(.dark)
}
