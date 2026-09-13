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
/// It has to exist at all because almost nothing on anybody's phone is already square.
/// The alternative is centre-cropping for people, which is how you get profiles
/// where the first photo is somebody's forehead.
struct PhotoCropView: View {
    let photo: LibraryPhoto
    /// Which of the chosen photos this is, for the counter.
    var step: Int = 1
    var total: Int = 1
    let onUse: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Zoom as a percentage, so the slider the rest of the app uses fits it.
    @State private var zoom: Int = 100
    @State private var zoomBase: Int = 100
    @State private var offset: CGSize = .zero
    @State private var drag: CGSize = .zero

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
        .overlay(alignment: .bottom) {
            Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
        }
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
            let hole = CGRect(
                x: (geo.size.width - frame.width) / 2,
                y: (geo.size.height - frame.height) / 2,
                width: frame.width,
                height: frame.height
            )

            ZStack {
                Color.clear

                PhotoPlaceholder(toneIndex: photo.toneIndex)
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
                CropSurround(hole: hole, radius: ArchRadius.photo)
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
        ArchButton(title: step < total ? "Next" : useTitle, action: onUse)
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.top, ArchSpacing.s)
            .padding(.bottom, ArchSpacing.s)
            .background(ArchColor.stoneRaised)
            .overlay(alignment: .top) {
                Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
            }
    }

    private var useTitle: String {
        total > 1 ? "Add \(ArchCopy.word(total)) photos" : "Add photo"
    }

    // MARK: Geometry

    /// The frame, in the shape the rest of the app draws photos in, as large as it
    /// can be inside the stage with a margin left over on every side for the part
    /// of the photograph you are cutting off.
    private func frameSize(in stage: CGSize) -> CGSize {
        let width = min(
            stage.width - Self.inset * 2,
            (stage.height - Self.inset * 2) * PhotoCard.aspect
        )
        let safe = max(width, 1)
        return CGSize(width: safe, height: safe / PhotoCard.aspect)
    }

    /// The photograph at its own shape, scaled so it covers the frame, then zoomed.
    private func imageSize(covering frame: CGSize) -> CGSize {
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
}

/// Everything except the frame.
///
/// Two subpaths filled even-odd, so the frame is a hole rather than four rectangles
/// that have to be kept in agreement with each other.
struct CropSurround: Shape {
    let hole: CGRect
    var radius: CGFloat = ArchRadius.photo

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addPath(Path(roundedRect: hole, cornerRadius: radius, style: .continuous))
        return path
    }
}

// MARK: - Previews

#Preview("A portrait photo") {
    NavigationStack {
        PhotoCropView(photo: MockData.photoLibrary[0]) {}
    }
    .preferredColorScheme(.dark)
}

/// The case the screen exists for: a wide photograph that has to lose most of
/// itself to become a portrait.
#Preview("A landscape photo, second of three") {
    NavigationStack {
        PhotoCropView(photo: MockData.photoLibrary[6], step: 2, total: 3) {}
    }
    .preferredColorScheme(.dark)
}

#Preview("A panorama") {
    NavigationStack {
        PhotoCropView(photo: MockData.photoLibrary[17]) {}
    }
    .preferredColorScheme(.dark)
}
