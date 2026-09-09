import SwiftUI

/// The Daily Arch.
///
/// Today's five people are five stones of an arch. Each one fills with lamplight
/// as you finish reading that person, and the arch is only complete when all five
/// are set. This replaces the "3 of 5" counter every other app would put here —
/// the arch *is* the counter, and it is also the reason the app is called Arch.
///
/// The centre stone is drawn proud of the band on both faces, so it reads as the
/// keystone before any colour is applied to it.
///
/// The view holds no state. The one piece of orchestrated motion in Arch — the
/// keystone dropping home on a connection — is driven by whoever owns the moment,
/// which is `ConnectionRevealView`.
struct DailyArchProgress: View {

    /// How many of today's people have been read.
    var completed: Int
    /// The person currently being read, if any. Outlined, not filled.
    var currentIndex: Int?
    var total: Int = 5

    /// A connection has been made: the band turns verdigris, washing outward from
    /// the keystone. The only place verdigris appears in the whole app.
    var isConnected: Bool = false

    /// False while the keystone is still sitting proud, waiting to drop into place.
    var keystoneSeated: Bool = true

    var width: CGFloat = 180

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let band = ArchBand()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(0..<total), id: \.self) { index in
                    stone(index, in: geometry.size)
                }
            }
        }
        .frame(width: width, height: band.height(forWidth: width))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func stone(_ index: Int, in size: CGSize) -> some View {
        let segment = band.segment(index, in: size)
        let isKeystone = band.isKeystone(index)

        ZStack {
            segment
                .fill(fill(for: index))
                .animation(
                    ArchMotion.honouring(reduceMotion, ArchMotion.wash.delay(washDelay(index))),
                    value: isConnected
                )

            if index == currentIndex {
                segment.stroke(ArchColor.lampQuiet, lineWidth: 1)
            }

            // A finished arch should look lit, not merely full.
            if isKeystone && isComplete {
                segment.stroke(ArchColor.limestone.opacity(0.15), lineWidth: 1)
            }
        }
        .offset(
            x: settleOffset(index),
            y: isKeystone ? keystoneOffset : 0
        )
    }

    // MARK: State

    private var isComplete: Bool { completed >= total }

    private func fill(for index: Int) -> Color {
        guard index < completed else { return ArchColor.stoneRaised }
        return isConnected ? ArchColor.verdigris : ArchColor.lamp
    }

    /// The wash travels outward from the keystone rather than left to right.
    private func washDelay(_ index: Int) -> Double {
        Double(abs(index - band.keystoneIndex)) * 0.06
    }

    private var keystoneOffset: CGFloat {
        keystoneSeated ? 0 : ArchMotion.offset(reduceMotion, -8)
    }

    /// The two stones either side settle against the keystone once it lands.
    private func settleOffset(_ index: Int) -> CGFloat {
        guard isConnected, keystoneSeated, !reduceMotion else { return 0 }
        if index == band.keystoneIndex - 1 { return 1 }
        if index == band.keystoneIndex + 1 { return -1 }
        return 0
    }

    private var accessibilityLabel: String {
        if isConnected {
            return "The arch is complete. You have connected."
        }
        if isComplete {
            return "All \(total) read today. The arch is complete."
        }
        return "\(completed) of \(total) read today."
    }
}

// MARK: - Previews

#Preview("All states") {
    VStack(spacing: ArchSpacing.xxl) {
        ForEach(0...5, id: \.self) { done in
            VStack(spacing: ArchSpacing.s) {
                DailyArchProgress(
                    completed: done,
                    currentIndex: done < 5 ? done : nil,
                    width: 150
                )
                Text(done == 5 ? "Complete" : "\(done) set, one open")
                    .archText(.caption)
                    .foregroundStyle(ArchColor.mortar)
            }
        }
    }
    .padding(ArchSpacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}

#Preview("Keystone lock") {
    KeystoneLockDemo()
}

/// Not shipped — a preview harness for the one orchestrated moment in the app,
/// so the timing can be judged without walking through the whole flow.
private struct KeystoneLockDemo: View {
    @State private var connected = false
    @State private var seated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: ArchSpacing.xxxl) {
            DailyArchProgress(
                completed: 5,
                currentIndex: nil,
                isConnected: connected,
                keystoneSeated: seated,
                width: 220
            )

            ArchButton(title: seated ? "Reset" : "Lock the keystone") {
                if seated {
                    seated = false
                    connected = false
                } else {
                    withAnimation(ArchMotion.honouring(reduceMotion, ArchMotion.keystoneLock)) {
                        seated = true
                    }
                    withAnimation(ArchMotion.honouring(reduceMotion, ArchMotion.wash)) {
                        connected = true
                    }
                }
            }
        }
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
    }
}
