import SwiftUI

/// A two-handled range, for the age you want to be shown.
///
/// SwiftUI has no range slider, and the two obvious substitutes both fail: two
/// stacked sliders make you hold the relationship between them in your head, and
/// steppers make you tap twenty times to move ten years. So this is hand-built.
///
/// `lamp` on the handles and the selected span, because a handle is the most
/// literally actionable thing in the app — you drag it and something changes.
struct RangeSlider: View {
    @Binding var low: Int
    @Binding var high: Int
    var bounds: ClosedRange<Int>
    /// Keeps the handles from crossing or landing on top of each other.
    var minimumSpan: Int = 1

    private let handleSize: CGFloat = 26
    private let trackHeight: CGFloat = 4
    private let space = "rangeTrack"

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let usable = max(1, width - handleSize)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ArchColor.stone)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(ArchColor.lamp)
                    .frame(width: max(0, x(high, usable) - x(low, usable)), height: trackHeight)
                    .offset(x: x(low, usable) + handleSize / 2)

                handle(at: x(low, usable), label: "Youngest, \(low)") { position in
                    let value = value(at: position, usable: usable)
                    low = min(max(bounds.lowerBound, value), high - minimumSpan)
                }
                handle(at: x(high, usable), label: "Oldest, \(high)") { position in
                    let value = value(at: position, usable: usable)
                    high = max(min(bounds.upperBound, value), low + minimumSpan)
                }
            }
            .frame(height: handleSize)
            .frame(maxHeight: .infinity)
            .coordinateSpace(name: space)
        }
        .frame(height: 44)
    }

    // MARK: Geometry

    private var span: CGFloat {
        CGFloat(max(1, bounds.upperBound - bounds.lowerBound))
    }

    /// Leading edge of a handle for a value.
    private func x(_ value: Int, _ usable: CGFloat) -> CGFloat {
        CGFloat(value - bounds.lowerBound) / span * usable
    }

    private func value(at position: CGFloat, usable: CGFloat) -> Int {
        let clamped = min(max(0, position - handleSize / 2), usable)
        return bounds.lowerBound + Int((clamped / usable * span).rounded())
    }

    private func handle(
        at x: CGFloat,
        label: String,
        move: @escaping (CGFloat) -> Void
    ) -> some View {
        Circle()
            .fill(ArchColor.lamp)
            .frame(width: handleSize, height: handleSize)
            .offset(x: x)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                    .onChanged { move($0.location.x) }
            )
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }
}

/// One handle, for a single value. Same construction, half the parts.
struct ValueSlider: View {
    @Binding var value: Int
    var bounds: ClosedRange<Int>

    var body: some View {
        Slider(
            value: Binding(
                get: { Double(value) },
                set: { value = Int($0.rounded()) }
            ),
            in: Double(bounds.lowerBound)...Double(bounds.upperBound),
            step: 1
        )
        .tint(ArchColor.lamp)
        .frame(height: 44)
    }
}

#Preview("Sliders") {
    SliderPreview()
}

private struct SliderPreview: View {
    @State private var low = 26
    @State private var high = 36
    @State private var distance = 10

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xxl) {
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text("\(low) to \(high)")
                    .archText(.titleL)
                    .foregroundStyle(ArchColor.limestone)
                RangeSlider(low: $low, high: $high, bounds: 18...70)
            }
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text("Within \(distance) miles")
                    .archText(.titleL)
                    .foregroundStyle(ArchColor.limestone)
                ValueSlider(value: $distance, bounds: 1...50)
            }
        }
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
    }
}
