import SwiftUI

/// The five slots, drawn as the five stones of an arch.
///
/// This is a **state** indicator, not a progress bar. There is nothing to work
/// through and nothing to complete — it answers one question at a glance: is my
/// roster full? A filled slot is a solid stone in `lamp`. An open slot is the place
/// a stone should be, drawn as an outline.
///
/// Stones fill left to right, which mirrors the list below it: people first, open
/// slots after.
///
/// **Why open slots are outlines and not true voids.** At one filled slot, a
/// literal gap leaves a single wedge floating with nothing around it, which reads
/// as damage. The outline is a mason's setting-out line — the place is marked, the
/// stone is not there yet — so one stone still reads as one of five.
struct ArchSlotIndicator: View {

    /// How many of the slots are currently holding someone.
    var filled: Int
    var capacity: Int = 5
    var width: CGFloat = 132

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Presentation-only state: which stone is mid-fall, and how far it has fallen.
    /// The store just removes the person; the arch animates its own loss.
    @State private var droppingIndex: Int?
    @State private var dropProgress: CGFloat = 0

    private let band = ArchBand(thickness: 18)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(0..<capacity), id: \.self) { index in
                    stone(index, in: geometry.size)
                }
            }
        }
        .frame(width: width, height: band.height(forWidth: width))
        .onChange(of: filled) { previous, current in
            // Arrivals are never animated — only a loss gets a moment.
            guard current < previous else { return }
            dropStone(at: previous - 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func stone(_ index: Int, in size: CGSize) -> some View {
        let segment = band.segment(index, in: size)
        let isDropping = index == droppingIndex

        ZStack {
            if index < filled || isDropping {
                segment.fill(ArchColor.lamp)
            } else {
                segment
                    .stroke(ArchColor.mortar.opacity(0.30), lineWidth: 1)
                    .animation(ArchMotion.quick, value: droppingIndex)
            }
        }
        .offset(y: isDropping ? ArchMotion.offset(reduceMotion, 14 * dropProgress) : 0)
        .opacity(isDropping ? 1 - dropProgress : 1)
    }

    private func dropStone(at index: Int) {
        droppingIndex = index
        dropProgress = 0

        Task { @MainActor in
            await Task.yield()
            withAnimation(ArchMotion.honouring(reduceMotion, ArchMotion.stoneFall)) {
                dropProgress = 1
            }
            try? await Task.sleep(for: .milliseconds(360))
            droppingIndex = nil
            dropProgress = 0
        }
    }

    /// Sighted users read the state off the shape, so it carries no number. VoiceOver
    /// has no shape to read, so here the count is the only way to convey it.
    private var accessibilityLabel: String {
        switch filled {
        case capacity: return "All \(capacity) of your slots are filled."
        case 0:        return "All \(capacity) of your slots are open."
        case 1:        return "1 of your \(capacity) slots is filled."
        default:       return "\(filled) of your \(capacity) slots are filled."
        }
    }
}

// MARK: - Previews

#Preview("Slot states") {
    VStack(spacing: ArchSpacing.xxl) {
        ForEach(Array((0...5).reversed()), id: \.self) { count in
            ArchSlotIndicator(filled: count)
        }
    }
    .padding(ArchSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}

#Preview("A stone drops") {
    StoneDropDemo()
}

/// Not shipped — a harness for the one orchestrated moment, so the weight of the
/// drop can be judged without walking the whole dismiss flow.
private struct StoneDropDemo: View {
    @State private var filled = 5

    var body: some View {
        VStack(spacing: ArchSpacing.xxxl) {
            ArchSlotIndicator(filled: filled, width: 200)

            VStack(spacing: ArchSpacing.s) {
                ArchButton(title: "Dismiss someone", kind: .quiet, isEnabled: filled > 0) {
                    filled -= 1
                }
                ArchTextButton(title: "Refill") { filled = 5 }
            }
        }
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
    }
}
