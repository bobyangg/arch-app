import SwiftUI

/// **Straight after onboarding, a tap through what Arch is for.** Five things,
/// each on its own tab: the tab underneath moves to it, the tab is cut out of a
/// dimmed screen, and a card says what it is for. Skip leaves at any point; it
/// can be taken again from Settings > Help.
///
/// It replaced the one popup that used to follow onboarding -- the Date
/// planner's -- and keeps its one action: the planner's step offers the five
/// questions, the way the popup did.
struct ArchTourStep {
    /// The tab it is about, shown underneath and cut out. Nil for the welcome
    /// and the end, which sit in the middle of a dimmed screen.
    let tab: ArchTab?
    let kicker: String
    let title: (String) -> String
    let body: String

    static let all: [ArchTourStep] = [
        ArchTourStep(tab: nil, kicker: "Welcome",
                     title: { "Welcome to Arch, \($0)" },
                     body: "A quick look at how it works. Five things, under a minute."),
        ArchTourStep(tab: .daily, kicker: "Daily 5",
                     title: { _ in "Five people, every morning" },
                     body: "At 9am Arch picks five people for you from your answers. There is no swiping: write to someone to start talking. Not for you? Dismiss them, and the spot refills tomorrow morning."),
        ArchTourStep(tab: .messages, kicker: "Messages",
                     title: { _ in "Where conversations live" },
                     body: "Everyone you write to, and everyone who writes to you first, is here. Keep up to ten going at once."),
        ArchTourStep(tab: .planner, kicker: "Date planner",
                     title: { _ in "Plan the date together" },
                     body: "Pick someone you are talking to and Arch helps plan out a date for you to send to them. Or make a Self Plan, just for you."),
        ArchTourStep(tab: .you, kicker: "You",
                     title: { _ in "Your profile" },
                     body: "Your photos, answers and interests, as other people see them."),
        ArchTourStep(tab: nil, kicker: "Ready",
                     title: { _ in "That\u{2019}s Arch" },
                     body: "Your five are waiting.")
    ]
}

/// Where each tab sits, for the tour to cut it out. Reported by the tab bar.
struct ArchTabFramesKey: PreferenceKey {
    static var defaultValue: [ArchTab: Anchor<CGRect>] = [:]
    static func reduce(value: inout [ArchTab: Anchor<CGRect>], nextValue: () -> [ArchTab: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The tour on screen: the dimmed screen with the tab cut out, and the card.
/// Laid over the whole screen, safe areas and all, by whoever shows it -- in
/// the same space the tab's frame was resolved in.
///
/// The screen underneath cannot be touched while it is up -- a tap on a tab
/// would move the app out from under the card -- so the whole of it takes
/// taps and does nothing with them.
struct ArchTourOverlay: View {
    let index: Int
    let name: String
    /// The tab's frame, in this view's space, when the step is about a tab.
    let tabFrame: CGRect?
    /// The planner's step offers the five questions while they are unanswered.
    let offersQuestions: Bool
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void
    let onQuestions: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var step: ArchTourStep { ArchTourStep.all[index] }
    private var isFirst: Bool { index == 0 }
    private var isLast: Bool { index == ArchTourStep.all.count - 1 }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let hole = tabFrame?.insetBy(dx: 4, dy: 4)
            ZStack(alignment: .topLeading) {
                // The dimmed screen, with the tab cut out of it.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    if let hole {
                        path.addRoundedRect(in: hole, cornerSize: CGSize(width: 16, height: 16))
                    }
                }
                .fill(ArchColor.scrim, style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)

                if let hole {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(ArchColor.lamp, lineWidth: 2)
                        .frame(width: hole.width + 6, height: hole.height + 6)
                        .position(x: hole.midX, y: hole.midY)
                        .accessibilityHidden(true)
                }

                card(width: size.width)
                    .position(x: size.width / 2, y: cardY(in: size))
            }
            .animation(ArchMotion.honouring(reduceMotion, ArchMotion.standard), value: index)
        }
        .transition(.opacity)
    }

    /// Above the tab it is about, or in the middle of the screen.
    private func cardY(in size: CGSize) -> CGFloat {
        let height = cardHeight
        guard let frame = tabFrame else { return size.height / 2 }
        return frame.minY - 16 - height / 2
    }

    /// Measured, so the card can sit just above its tab whatever its words.
    @State private var cardHeight: CGFloat = 280

    private func card(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    ForEach(ArchTourStep.all.indices, id: \.self) { dot in
                        Capsule()
                            .fill(dot == index ? ArchColor.lamp : ArchColor.quietBorder)
                            .frame(width: dot == index ? 18 : 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
                Spacer(minLength: 0)
                if !isLast {
                    Button(action: onSkip) {
                        Text("Skip")
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.mortar)
                            .padding(.vertical, ArchSpacing.xxs)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tour.skip")
                }
            }

            Text(step.kicker)
                .archText(.caption)
                .foregroundStyle(ArchColor.lamp)
                .padding(.top, ArchSpacing.m)
            Text(step.title(name))
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.xxs)
            Text(step.body)
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.s)

            if step.tab == .planner && offersQuestions {
                ArchButton(title: "Answer 5 quick questions", kind: .quiet, action: onQuestions)
                    .accessibilityIdentifier("tour.questions")
                    .padding(.top, ArchSpacing.m)
            }

            HStack(spacing: ArchSpacing.xs) {
                if !isFirst && !isLast {
                    ArchTextButton(title: "Back", action: onBack)
                        .fixedSize()
                        .accessibilityIdentifier("tour.back")
                }
                ArchButton(title: isFirst ? "Show me" : (isLast ? "Start" : "Next"), action: onNext)
                    .accessibilityIdentifier("tour.next")
            }
            .padding(.top, ArchSpacing.m)
        }
        .padding(ArchSpacing.l)
        .frame(width: width - 2 * ArchSpacing.screenMargin, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(ArchColor.stoneRaised)
        )
        // A small point down at the tab it is about.
        .overlay(alignment: .bottomLeading) {
            if let frame = tabFrame {
                Rectangle()
                    .fill(ArchColor.stoneRaised)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(45))
                    .offset(x: min(max(frame.midX - ArchSpacing.screenMargin - 7, 16),
                                   width - 2 * ArchSpacing.screenMargin - 30),
                            y: 7)
                    .accessibilityHidden(true)
            }
        }
        .background(
            GeometryReader { card in
                Color.clear
                    .onAppear { cardHeight = card.size.height }
                    .onChange(of: card.size.height) { _, height in cardHeight = height }
            }
        )
        // Not marked modal: the tab underneath is part of what it is showing,
        // and the dimmed screen already keeps it from being tapped.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("A look around Arch, \(index + 1) of \(ArchTourStep.all.count)")
        .accessibilityIdentifier("tour")
    }
}
